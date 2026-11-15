import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:giant_agent_x/agent/architecture/react_decision.dart';

void main() {
  group('ReactDecisionParser', () {
    test('parses one valid tool call', () {
      final call = ReactDecisionParser.parseToolCall(
        'prefix <tool_call>{"name":"read_file","arguments":{"path":"README.md"}}</tool_call>',
      );
      expect(call, isNotNull);
      expect(call!.name, 'read_file');
      expect(call.arguments, {'path': 'README.md'});
    });

    test('returns null for a normal final answer', () {
      expect(ReactDecisionParser.parseToolCall('الإجابة النهائية'), isNull);
    });

    test('rejects malformed JSON before dispatch', () {
      expect(() => ReactDecisionParser.parseToolCall('<tool_call>{"name":</tool_call>'), throwsFormatException);
    });

    test('rejects missing and additional top-level fields', () {
      for (final json in ['{"name":"read_file"}', '{"name":"read_file","arguments":{},"approved":true}']) {
        expect(() => ReactDecisionParser.parseToolCall('<tool_call>$json</tool_call>'), throwsFormatException);
      }
    });

    test('rejects wrong field types and invalid tool names', () {
      for (final json in [
        '{"name":12,"arguments":{}}',
        '{"name":"bad tool","arguments":{}}',
        '{"name":"read_file","arguments":[]}',
      ]) {
        expect(() => ReactDecisionParser.parseToolCall('<tool_call>$json</tool_call>'), throwsFormatException);
      }
    });

    test('rejects multiple or incomplete envelopes', () {
      expect(
        () => ReactDecisionParser.parseToolCall(
          '<tool_call>{"name":"a","arguments":{}}</tool_call><tool_call>{"name":"b","arguments":{}}</tool_call>',
        ),
        throwsFormatException,
      );
      expect(() => ReactDecisionParser.parseToolCall('<tool_call>{"name":"a"}'), throwsFormatException);
      expect(() => ReactDecisionParser.parseToolCall('</tool_call>'), throwsFormatException);
    });

    test('rejects oversized payloads and excessive argument counts', () {
      final large = 'x' * (ReactDecisionParser.maxEnvelopeCharacters + 1);
      expect(() => ReactDecisionParser.parseToolCall('<tool_call>$large</tool_call>'), throwsFormatException);
      final args = {for (var i = 0; i <= ReactDecisionParser.maxArguments; i++) 'k$i': i};
      final envelope = jsonEncode({'name': 'read_file', 'arguments': args});
      expect(() => ReactDecisionParser.parseToolCall('<tool_call>$envelope</tool_call>'), throwsFormatException);
    });

    test('canonical signatures ignore map key order but preserve list order', () {
      final first = ReactDecisionParser.signature('tool', {
        'b': 2, 'a': {'y': 1, 'x': 0}, 'items': [1, 2],
      });
      final reordered = ReactDecisionParser.signature('tool', {
        'items': [1, 2], 'a': {'x': 0, 'y': 1}, 'b': 2,
      });
      final changedList = ReactDecisionParser.signature('tool', {
        'items': [2, 1], 'a': {'x': 0, 'y': 1}, 'b': 2,
      });
      expect(first, reordered);
      expect(first, isNot(changedList));
    });
  });
}
