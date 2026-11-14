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
        () => ToolCallProtocol.extract('<tool_call>{"name":"x"} trailing</tool_call>'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
