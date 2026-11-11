import 'package:flutter_test/flutter_test.dart';
import 'package:giant_agent_x/domain/mcp/mcp_client.dart';
import 'package:giant_agent_x/domain/mcp/mcp_tool_result.dart';

void main() {
  group('MCP discovery contracts', () {
    test('server configuration round-trips endpoint and credential fields', () {
      final server = McpServerConfig(
        id: 'workspace',
        name: 'Workspace',
        endpoint: 'https://mcp.example.com/mcp',
        bearerToken: 'test-token',
      );
      final restored = McpServerConfig.fromJson(server.toJson());
      expect(restored.id, 'workspace');
      expect(restored.endpoint, 'https://mcp.example.com/mcp');
      expect(restored.bearerToken, 'test-token');
    });

    test('remote tool discovery preserves the JSON input schema', () {
      final tool = McpRemoteTool.fromJson({
        'name': 'search',
        'description': 'Search indexed documents',
        'annotations': {'readOnlyHint': true, 'destructiveHint': false},
        'inputSchema': {
          'type': 'object',
          'required': ['query'],
          'properties': {'query': {'type': 'string'}},
        },
      });
      expect(tool.name, 'search');
      expect(tool.annotations['readOnlyHint'], isTrue);
      expect(tool.inputSchema['required'], ['query']);
      expect((tool.inputSchema['properties'] as Map)['query']['type'], 'string');
    });

    test('rejects discovered tools without names', () {
      expect(() => McpRemoteTool.fromJson({'description': 'missing name'}), throwsFormatException);
    });
  });

  group('MCP result projection', () {
    test('joins text blocks with actual line separators and retains structured output', () {
      final result = McpToolResult.fromJson({
        'content': [
          {'type': 'resource_link', 'uri': 'file:///tmp/report.pdf', 'name': 'report', 'mimeType': 'application/pdf'},
          {'type': 'text', 'text': 'first'},
          {'type': 'text', 'text': 'second'},
        ],
        'structuredContent': {'count': 2},
        '_meta': {'trace': 'round-trip'},
      });
      expect(result.textPreview, 'first\nsecond');
      expect(result.structuredContent?['count'], 2);
      expect(result.resourceLinks, hasLength(1));
      expect(result.resourceLinks.single.uri, 'file:///tmp/report.pdf');
      expect(result.toJson()['_meta']['trace'], 'round-trip');
    });
  });
}
