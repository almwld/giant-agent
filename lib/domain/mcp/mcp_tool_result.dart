import 'dart:convert';

/// Lossless, validated representation of MCP tool output.
class McpToolResult {
  const McpToolResult({
    required this.content,
    required this.isError,
    this.structuredContent,
    this.meta,
  });

  final List<McpContentBlock> content;
  final bool isError;
  final Map<String, dynamic>? structuredContent;
  final Map<String, dynamic>? meta;

  factory McpToolResult.fromJson(Map<String, dynamic> json) {
    final rawContent = json['content'];
    if (rawContent is! List) {
      throw const FormatException('MCP result content must be an array.');
    }
    if (rawContent.length > 256) {
      throw const FormatException('MCP result contains too many content blocks.');
    }
    final structured = json['structuredContent'];
    final metadata = json['_meta'] ?? json['meta'];
    if (structured != null && structured is! Map) {
      throw const FormatException('MCP structuredContent must be an object.');
    }
    if (metadata != null && metadata is! Map) {
      throw const FormatException('MCP metadata must be an object.');
    }
    return McpToolResult(
      content: rawContent.map((item) {
        if (item is! Map<String, dynamic>) {
          throw const FormatException('MCP content block must be an object.');
        }
        return McpContentBlock.fromJson(item);
      }).toList(growable: false),
      isError: json['isError'] == true,
      structuredContent: structured == null
          ? null
          : Map<String, dynamic>.from(structured as Map),
      meta: metadata == null ? null : Map<String, dynamic>.from(metadata as Map),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'content': content.map((block) => block.toJson()).toList(),
        'isError': isError,
        if (structuredContent != null) 'structuredContent': structuredContent,
        if (meta != null) '_meta': meta,
      };

  /// File/resource links remain addressable objects for UI and follow-up reads.
  List<McpResourceLink> get resourceLinks => content
      .where((block) => block.type == 'resource_link' && block.uri != null)
      .map((block) => McpResourceLink(
            uri: block.uri!,
            name: block.name,
            title: block.title,
            description: block.extra['description']?.toString(),
            mimeType: block.mimeType,
            size: block.extra['size'] is num
                ? (block.extra['size'] as num).toInt()
                : null,
          ))
      .toList(growable: false);

  /// Explicit display helper; never use this as the persisted source of truth.
  String get textPreview => content
      .where((block) => block.type == 'text')
      .map((block) => block.text ?? '')
      .where((value) => value.isNotEmpty)
      .join('\n');
}

class McpContentBlock {
  const McpContentBlock({
    required this.type,
    this.text,
    this.data,
    this.mimeType,
    this.uri,
    this.name,
    this.title,
    this.annotations,
    this.extra = const <String, dynamic>{},
  });

  final String type;
  final String? text;
  final String? data;
  final String? mimeType;
  final String? uri;
  final String? name;
  final String? title;
  final Map<String, dynamic>? annotations;
  final Map<String, dynamic> extra;

  factory McpContentBlock.fromJson(Map<String, dynamic> json) {
    final type = json['type']?.toString();
    if (type == null || type.isEmpty) {
      throw const FormatException('MCP content block has no type.');
    }
    const known = {'type', 'text', 'data', 'mimeType', 'uri', 'name', 'title', 'annotations'};
    return McpContentBlock(
      type: type,
      text: json['text']?.toString(),
      data: json['data']?.toString(),
      mimeType: json['mimeType']?.toString(),
      uri: json['uri']?.toString(),
      name: json['name']?.toString(),
      title: json['title']?.toString(),
      annotations: json['annotations'] is Map
          ? Map<String, dynamic>.from(json['annotations'] as Map)
          : null,
      extra: Map<String, dynamic>.fromEntries(
        json.entries.where((entry) => !known.contains(entry.key)),
      ),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'type': type,
        if (text != null) 'text': text,
        if (data != null) 'data': data,
        if (mimeType != null) 'mimeType': mimeType,
        if (uri != null) 'uri': uri,
        if (name != null) 'name': name,
        if (title != null) 'title': title,
        if (annotations != null) 'annotations': annotations,
        ...extra,
      };
}

/// Resource links are kept separately from text so callers can render files.
class McpResourceLink {
  const McpResourceLink({
    required this.uri,
    this.name,
    this.title,
    this.description,
    this.mimeType,
    this.size,
  });

  final String uri;
  final String? name;
  final String? title;
  final String? description;
  final String? mimeType;
  final int? size;

  factory McpResourceLink.fromJson(Map<String, dynamic> json) {
    final uri = (json['uri'] ?? json['url'])?.toString() ?? '';
    final parsed = Uri.tryParse(uri);
    if (parsed == null || !parsed.hasScheme) {
      throw const FormatException('MCP resource link must contain an absolute URI.');
    }
    return McpResourceLink(
      uri: uri,
      name: json['name']?.toString(),
      title: json['title']?.toString(),
      description: json['description']?.toString(),
      mimeType: json['mimeType']?.toString(),
      size: json['size'] is num ? (json['size'] as num).toInt() : null,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'uri': uri,
        if (name != null) 'name': name,
        if (title != null) 'title': title,
        if (description != null) 'description': description,
        if (mimeType != null) 'mimeType': mimeType,
        if (size != null) 'size': size,
      };
}

/// JSON-safe canonical representation for durable persistence.
String encodeMcpResult(McpToolResult result) => jsonEncode(result.toJson());
