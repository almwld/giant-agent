import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:giant_agent_x/agent/architecture/tool_call_registry.dart';
import 'package:giant_agent_x/agent/architecture/agent_timeline_event.dart';
import 'package:giant_agent_x/domain/mcp/mcp_tool_result.dart';
import 'package:giant_agent_x/services/streaming/server_sent_event_parser.dart';

void main() {
  group('MCP result envelope', () {
    test('preserves text, resource blocks, structured data, metadata and errors', () {
      final result = McpToolResult.fromJson(<String, dynamic>{
        'content': [
          {'type': 'text', 'text': 'hello'},
          {'type': 'resource_link', 'uri': 'file:///tmp/report.pdf', 'mimeType': 'application/pdf'},
          {'type': 'image', 'data': 'YWJj', 'mimeType': 'image/png', 'vendorField': 7},
        ],
        'isError': true,
        'structuredContent': {'count': 3},
        '_meta': {'trace': 'abc'},
      });
      expect(result.isError, isTrue);
      expect(result.textPreview, 'hello');
      expect(result.content[1].uri, 'file:///tmp/report.pdf');
      expect(result.content[2].extra['vendorField'], 7);
      final roundTrip = McpToolResult.fromJson(result.toJson());
      expect(roundTrip.structuredContent?['count'], 3);
      expect(roundTrip.meta?['trace'], 'abc');
      expect(roundTrip.content.length, 3);
    });

    test('rejects malformed content and non-object structured content', () {
      expect(
        () => McpToolResult.fromJson({'content': 'not-an-array'}),
        throwsFormatException,
      );
      expect(
        () => McpToolResult.fromJson({'content': [], 'structuredContent': []}),
        throwsFormatException,
      );
    });

    test('validates resource links', () {
      expect(
        () => McpResourceLink.fromJson({'uri': 'relative/path'}),
        throwsFormatException,
      );
    });
  });

  group('SSE parser', () {
    test('parses multiline data, comments, IDs and CRLF', () {
      final parser = ServerSentEventParser();
      final events = parser.add(utf8.encode(': keepalive\r\nid: 42\r\nevent: delta\r\ndata: one\r\ndata: two\r\n\r\n'));
      expect(events, hasLength(1));
      expect(events.single.event, 'delta');
      expect(events.single.id, '42');
      expect(events.single.data, 'one\ntwo');
      expect(parser.lastEventId, '42');
    });

    test('preserves UTF-8 characters split at every network byte boundary', () {
      final bytes = utf8.encode('data: مرحبا 🌍\n\n');
      for (var split = 1; split < bytes.length; split++) {
        final parser = ServerSentEventParser();
        expect(parser.add(bytes.sublist(0, split)), isEmpty);
        final events = <ServerSentEvent>[
          ...parser.add(bytes.sublist(split)),
          ...parser.close(),
        ];
        expect(events.single.data, 'مرحبا 🌍', reason: 'split at byte $split');
      }
    });

    test('ignores NUL event IDs and dispatches final unterminated event', () {
      final parser = ServerSentEventParser();
      parser.add(utf8.encode('id: bad\u0000id\ndata: final'));
      final events = parser.close();
      expect(events.single.data, 'final');
      expect(events.single.id, isNull);
    });
  });

  group('timeline tool-call identity', () {
    test('round-trips tool_call_id independently from request and step IDs', () {
      final event = AgentTimelineEvent(
        id: 'event-1',
        requestId: 'request-1',
        type: 'tool_call_started',
        title: 'Tool started',
        status: 'running',
        timestamp: DateTime.utc(2026, 11, 11),
        stepId: 'step-1',
        toolCallId: 'call-1',
      );
      final restored = AgentTimelineEvent.fromMap(event.toMap());
      expect(restored.requestId, 'request-1');
      expect(restored.stepId, 'step-1');
      expect(restored.toolCallId, 'call-1');
    });
  });

  group('tool call registry', () {
    test('cancels only the addressed invocation and removes terminal calls', () {
      final registry = ToolCallRegistry();
      final first = registry.begin(toolCallId: 'call-1', requestId: 'req', toolName: 'read_file');
      final second = registry.begin(toolCallId: 'call-2', requestId: 'req', toolName: 'write_file');
      expect(registry.cancel('call-1'), isTrue);
      expect(first.isCancelled, isTrue);
      expect(second.isCancelled, isFalse);
      expect(registry.cancel('missing'), isFalse);
      registry.finish('call-1');
      expect(registry.get('call-1'), isNull);
      expect(registry.activeCount, 1);
    });

    test('rejects duplicate active identities', () {
      final registry = ToolCallRegistry();
      registry.begin(toolCallId: 'same', requestId: 'req', toolName: 'read_file');
      expect(
        () => registry.begin(toolCallId: 'same', requestId: 'req', toolName: 'write_file'),
        throwsStateError,
      );
    });

    test('interruption carries the exact tool_call_id', () {
      final registry = ToolCallRegistry();
      final call = registry.begin(
        toolCallId: 'call-specific',
        requestId: 'request-parent',
        toolName: 'write_file',
      );
      registry.cancel('call-specific');
      expect(call.throwIfCancelled, throwsA(
        isA<ToolCallInterrupted>().having(
          (error) => error.toolCallId,
          'toolCallId',
          'call-specific',
        ),
      ));
    });
  });
}
