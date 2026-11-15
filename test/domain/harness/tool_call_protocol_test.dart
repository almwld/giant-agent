import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:giant_agent_x/domain/harness/tool_call_protocol.dart';

void main() {
  group('ToolCallProtocol.extract', () {
    test('returns null when the model produced a normal final response', () {
      expect(ToolCallProtocol.extract('هذه إجابة نهائية.'), isNull);
    });

    test('parses nested objects, arrays, braces and escaped quotes in strings', () {
      const output = r'''prefix
<tool_call>
{"name":"write_file","arguments":{"path":"src/main.dart","metadata":{"tags":["a","b"],"template":"{ \"key\": \"value\" }"},"content":"line 1\nline 2"}}
</tool_call>
''';
      final result = ToolCallProtocol.extract(output);
      expect(result?['name'], 'write_file');
      final args = result?['arguments'] as Map<String, dynamic>;
      expect(args['path'], 'src/main.dart');
      expect((args['metadata'] as Map<String, dynamic>)['tags'], ['a', 'b']);
      expect(args['content'], 'line 1\nline 2');
    });

    test('rejects a missing closing tag', () {
      expect(
        () => ToolCallProtocol.extract('<tool_call>{"name":"x","arguments":{}}'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects non-JSON prose inside the protocol envelope', () {
      expect(
        () => ToolCallProtocol.extract('<tool_call>run this: {"name":"x"}</tool_call>'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects trailing content after the JSON object', () {
      expect(
        () => ToolCallProtocol.extract('<tool_call>{"name":"x","arguments":{}} trailing</tool_call>'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects missing or additional top-level fields', () {
      for (final json in [
        '{"name":"read_file"}',
        '{"name":"read_file","arguments":{},"approved":true}',
      ]) {
        expect(
          () => ToolCallProtocol.extract('<tool_call>$json</tool_call>'),
          throwsA(isA<FormatException>()),
        );
      }
    });

    test('rejects invalid tool names and non-object arguments', () {
      for (final json in [
        '{"name":12,"arguments":{}}',
        '{"name":"bad tool","arguments":{}}',
        '{"name":"read_file","arguments":[]}',
      ]) {
        expect(
          () => ToolCallProtocol.extract('<tool_call>$json</tool_call>'),
          throwsA(isA<FormatException>()),
        );
      }
    });

    test('rejects multiple envelopes and unmatched closing tags', () {
      expect(
        () => ToolCallProtocol.extract(
          '<tool_call>{"name":"a","arguments":{}}</tool_call>'
          '<tool_call>{"name":"b","arguments":{}}</tool_call>',
        ),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => ToolCallProtocol.extract('</tool_call>'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects oversized envelopes and excessive argument counts', () {
      final large = 'x' * (ToolCallProtocol.maxEnvelopeCharacters + 1);
      expect(
        () => ToolCallProtocol.extract(
          '<tool_call>{"name":"read_file","arguments":{"x":"$large"}}</tool_call>',
        ),
        throwsA(isA<FormatException>()),
      );

      final args = {
        for (var i = 0; i <= ToolCallProtocol.maxArguments; i++) 'k$i': i,
      };
      final encoded = jsonEncode({'name': 'read_file', 'arguments': args});
      expect(
        () => ToolCallProtocol.extract('<tool_call>$encoded</tool_call>'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
