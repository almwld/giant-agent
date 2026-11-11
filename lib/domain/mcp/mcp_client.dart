import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../../services/streaming/server_sent_event_parser.dart';
import 'mcp_tool_result.dart';

/// Streamable-HTTP MCP client. One shared client owns server sessions; it does
/// not create or own a model/runtime instance.
class McpClient {
  McpClient._();

  static final McpClient instance = McpClient._();
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _serversKey = 'giant_mcp_servers_v1';
  static const String _protocolVersion = '2025-03-26';
  static const Duration _timeout = Duration(seconds: 45);

  final http.Client _http = http.Client();
  final Map<String, _McpSession> _sessions = <String, _McpSession>{};
  final Map<String, List<McpRemoteTool>> _toolCache = <String, List<McpRemoteTool>>{};
  int _requestId = 0;
  Future<void> _storageTail = Future<void>.value();

  Future<List<McpServerConfig>> servers() async {
    final raw = await _storage.read(key: _serversKey);
    if (raw == null || raw.isEmpty) return const <McpServerConfig>[];
    final decoded = jsonDecode(raw);
    if (decoded is! List) throw const FormatException('MCP server storage is invalid.');
    return decoded
        .whereType<Map>()
        .map((item) => McpServerConfig.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }

  Future<void> addServer({
    required String id,
    required String name,
    required String endpoint,
    String? bearerToken,
  }) async {
    final normalizedId = id.trim();
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,48}$').hasMatch(normalizedId)) {
      throw ArgumentError.value(id, 'id', 'Use 1-48 letters, digits, _ or -.');
    }
    final uri = _validateEndpoint(endpoint);
    final cleanName = name.trim();
    if (cleanName.isEmpty || cleanName.length > 100) {
      throw ArgumentError.value(name, 'name', 'Server name must be 1-100 characters.');
    }
    final current = await servers();
    final updated = current.where((server) => server.id != normalizedId).toList();
    updated.add(McpServerConfig(
      id: normalizedId,
      name: cleanName,
      endpoint: uri.toString(),
      bearerToken: bearerToken?.trim().isEmpty == true ? null : bearerToken?.trim(),
    ));
    await _writeServers(updated);
    _sessions.remove(normalizedId);
    _toolCache.remove(normalizedId);
  }

  Future<bool> removeServer(String id) async {
    final current = await servers();
    final updated = current.where((server) => server.id != id).toList();
    if (updated.length == current.length) return false;
    await _writeServers(updated);
    _sessions.remove(id);
    _toolCache.remove(id);
    return true;
  }

  Future<void> _writeServers(List<McpServerConfig> values) async {
    final previous = _storageTail;
    final gate = Completer<void>();
    _storageTail = gate.future;
    try {
      await previous;
      await _storage.write(
        key: _serversKey,
        value: jsonEncode(values.map((server) => server.toJson()).toList()),
      );
    } finally {
      if (!gate.isCompleted) gate.complete();
    }
  }

  Uri _validateEndpoint(String value) {
    final uri = Uri.tryParse(value.trim());
    final localHost = uri != null &&
        (uri.host == 'localhost' || uri.host == '127.0.0.1' || uri.host == '::1');
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'https' && !(uri.scheme == 'http' && localHost)) ||
        uri.userInfo.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      throw ArgumentError.value(value, 'endpoint',
          'MCP endpoint must use HTTPS; HTTP is allowed only for localhost.');
    }
    return uri;
  }

  Future<McpServerConfig> _server(String id) async {
    for (final server in await servers()) {
      if (server.id == id) return server;
    }
    throw StateError('MCP server is not configured: $id');
  }

  Future<Map<String, dynamic>> initialize(String serverId) async {
    final server = await _server(serverId);
    final existing = _sessions[serverId];
    if (existing != null && existing.initialized) return existing.serverInfo;

    final session = _McpSession(server: server);
    final response = await _post(session, <String, dynamic>{
      'jsonrpc': '2.0',
      'id': ++_requestId,
      'method': 'initialize',
      'params': <String, dynamic>{
        'protocolVersion': _protocolVersion,
        'capabilities': <String, dynamic>{},
        'clientInfo': <String, dynamic>{
          'name': 'Giant Agent',
          'version': '6.0.0',
        },
      },
    });
    final result = _rpcResult(response);
    final negotiated = result['protocolVersion']?.toString();
    if (negotiated == null || negotiated.isEmpty) {
      throw const FormatException('MCP initialize response omitted protocolVersion.');
    }
    session.protocolVersion = negotiated;
    session.serverInfo = result['serverInfo'] is Map
        ? Map<String, dynamic>.from(result['serverInfo'] as Map)
        : <String, dynamic>{};
    session.initialized = true;
    _sessions[serverId] = session;

    await _post(session, <String, dynamic>{
      'jsonrpc': '2.0',
      'method': 'notifications/initialized',
    }, allowAccepted: true);
    return Map<String, dynamic>.unmodifiable(session.serverInfo);
  }

  Future<List<McpRemoteTool>> listTools(String serverId) async {
    await initialize(serverId);
    final session = _sessions[serverId]!;
    final tools = <McpRemoteTool>[];
    String? cursor;
    final seenCursors = <String>{};
    for (var page = 0; page < 20; page++) {
      final params = <String, dynamic>{if (cursor != null) 'cursor': cursor};
      final response = await _post(session, <String, dynamic>{
        'jsonrpc': '2.0',
        'id': ++_requestId,
        'method': 'tools/list',
        'params': params,
      });
      final result = _rpcResult(response);
      final rawTools = result['tools'];
      if (rawTools is! List) {
        throw const FormatException('MCP tools/list response omitted tools array.');
      }
      for (final raw in rawTools) {
        if (raw is Map) tools.add(McpRemoteTool.fromJson(Map<String, dynamic>.from(raw)));
      }
      final next = result['nextCursor']?.toString();
      if (next == null || next.isEmpty) {
        final result = List<McpRemoteTool>.unmodifiable(tools);
        _toolCache[serverId] = result;
        return result;
      }
      if (!seenCursors.add(next)) {
        throw const FormatException('MCP tools/list repeated a pagination cursor.');
      }
      cursor = next;
    }
    throw const FormatException('MCP tools/list exceeded the 20-page safety limit.');
  }

  Future<McpToolResult> callTool({
    required String serverId,
    required String toolName,
    required Map<String, dynamic> arguments,
    bool Function()? isCancelled,
  }) async {
    if (isCancelled?.call() == true) throw StateError('MCP tool call cancelled before dispatch.');
    await initialize(serverId);
    final availableTools = _toolCache[serverId] ?? await listTools(serverId);
    if (!availableTools.any((tool) => tool.name == toolName)) {
      throw StateError('MCP tool is not present in the latest tools/list result: $toolName');
    }
    final session = _sessions[serverId]!;
    final response = await _post(session, <String, dynamic>{
      'jsonrpc': '2.0',
      'id': ++_requestId,
      'method': 'tools/call',
      'params': <String, dynamic>{
        'name': toolName,
        'arguments': arguments,
      },
    }, isCancelled: isCancelled);
    if (isCancelled?.call() == true) throw StateError('MCP tool call cancelled.');
    final result = _rpcResult(response);
    final normalized = <String, dynamic>{
      ...result,
      'content': result['content'] is List ? result['content'] : const <dynamic>[],
      'isError': result['isError'] == true,
    };
    return McpToolResult.fromJson(normalized);
  }

  Future<Map<String, dynamic>?> _post(
    _McpSession session,
    Map<String, dynamic> payload, {
    bool allowAccepted = false,
    bool Function()? isCancelled,
  }) async {
    if (isCancelled?.call() == true) throw StateError('MCP request cancelled.');
    final request = http.Request('POST', Uri.parse(session.server.endpoint))
      ..followRedirects = false
      ..headers.addAll(<String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json, text/event-stream',
        'MCP-Protocol-Version': session.protocolVersion ?? _protocolVersion,
        if (session.server.bearerToken?.isNotEmpty == true)
          'Authorization': 'Bearer ${session.server.bearerToken}',
        if (session.sessionId != null) 'Mcp-Session-Id': session.sessionId!,
      })
      ..body = jsonEncode(payload);

    final streamed = await _http.send(request).timeout(_timeout);
    final sessionId = streamed.headers['mcp-session-id'];
    if (sessionId != null && sessionId.isNotEmpty) session.sessionId = sessionId;
    if (streamed.isRedirect) {
      throw StateError('MCP endpoint redirects are rejected (HTTP ${streamed.statusCode}).');
    }
    if (allowAccepted && streamed.statusCode == 202) {
      await streamed.stream.drain<void>();
      return null;
    }
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      final body = await streamed.stream.bytesToString();
      final excerptLength = body.length > 2048 ? 2048 : body.length;
      throw StateError('MCP HTTP ${streamed.statusCode}: ${body.substring(0, excerptLength)}');
    }
    if (streamed.statusCode == 202) {
      await streamed.stream.drain<void>();
      return null;
    }
    final contentType = streamed.headers['content-type']?.toLowerCase() ?? '';
    if (contentType.contains('text/event-stream')) {
      final parser = ServerSentEventParser();
      final messages = <Map<String, dynamic>>[];
      await for (final chunk in streamed.stream.timeout(_timeout)) {
        if (isCancelled?.call() == true) throw StateError('MCP request cancelled.');
        for (final event in parser.add(chunk)) {
          final decoded = jsonDecode(event.data);
          if (decoded is Map) messages.add(Map<String, dynamic>.from(decoded));
        }
      }
      for (final event in parser.close()) {
        final decoded = jsonDecode(event.data);
        if (decoded is Map) messages.add(Map<String, dynamic>.from(decoded));
      }
      if (messages.isEmpty) return null;
      return messages.last;
    }
    final body = await streamed.stream.bytesToString();
    if (body.trim().isEmpty) return null;
    final decoded = jsonDecode(body);
    if (decoded is! Map) throw const FormatException('MCP response must be a JSON object.');
    return Map<String, dynamic>.from(decoded);
  }

  Map<String, dynamic> _rpcResult(Map<String, dynamic>? response) {
    if (response == null) throw const FormatException('MCP server returned no JSON-RPC response.');
    if (response['jsonrpc'] != '2.0') {
      throw const FormatException('MCP response has an invalid JSON-RPC version.');
    }
    if (response['error'] is Map) {
      final error = Map<String, dynamic>.from(response['error'] as Map);
      throw StateError('MCP JSON-RPC ${error['code']}: ${error['message']}');
    }
    final result = response['result'];
    if (result is! Map) throw const FormatException('MCP JSON-RPC response omitted result object.');
    return Map<String, dynamic>.from(result);
  }

  /// Human-readable tool catalogue injected into the existing agent prompt.
  Future<String> promptCatalog() async {
    final buffer = StringBuffer();
    for (final server in await servers()) {
      try {
        final tools = _toolCache[server.id] ??
            await listTools(server.id).timeout(const Duration(seconds: 12));
        for (final tool in tools) {
          buffer
            ..writeln('- mcp_call: ${server.name} / ${tool.name}')
            ..writeln('  description: ${tool.description}')
            ..writeln('  server_id: ${server.id}')
            ..writeln('  arguments_schema: ${jsonEncode(tool.inputSchema)}');
        }
      } catch (error) {
        buffer.writeln('- MCP server ${server.name} unavailable: ${error.toString()}');
      }
    }
    return buffer.toString();
  }

  void close() {
    _http.close();
    _sessions.clear();
    _toolCache.clear();
  }
}

class McpServerConfig {
  const McpServerConfig({
    required this.id,
    required this.name,
    required this.endpoint,
    this.bearerToken,
  });

  final String id;
  final String name;
  final String endpoint;
  final String? bearerToken;

  factory McpServerConfig.fromJson(Map<String, dynamic> json) => McpServerConfig(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        endpoint: json['endpoint']?.toString() ?? '',
        bearerToken: json['bearerToken']?.toString(),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'endpoint': endpoint,
        if (bearerToken != null && bearerToken!.isNotEmpty) 'bearerToken': bearerToken,
      };
}

class McpRemoteTool {
  const McpRemoteTool({
    required this.name,
    required this.description,
    required this.inputSchema,
  });

  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;

  factory McpRemoteTool.fromJson(Map<String, dynamic> json) {
    final name = json['name']?.toString() ?? '';
    if (name.isEmpty) throw const FormatException('MCP tool has no name.');
    final schema = json['inputSchema'];
    return McpRemoteTool(
      name: name,
      description: json['description']?.toString() ?? '',
      inputSchema: schema is Map ? Map<String, dynamic>.from(schema) : <String, dynamic>{},
    );
  }
}

class _McpSession {
  _McpSession({required this.server});
  final McpServerConfig server;
  String? sessionId;
  String? protocolVersion;
  bool initialized = false;
  Map<String, dynamic> serverInfo = <String, dynamic>{};
}
