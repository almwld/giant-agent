import 'package:flutter_test/flutter_test.dart';
import 'package:giant_agent_x/features/assistant/application/default_agent_tools.dart';
import 'package:giant_agent_x/features/assistant/application/react_agent_provider.dart';
import 'package:giant_agent_x/features/assistant/domain/ai_provider.dart';
import 'package:giant_agent_x/features/assistant/domain/chat_message.dart';

void main() {
  group('agent tools', () {
    test('calculator evaluates arithmetic safely', () async {
      final result = await createDefaultAgentTools().execute('calculator', {'expression': '(42 / 2) + 3 * 4'});
      expect(result, contains('"ok":true'));
      expect(result, contains('33.0'));
    });
    test('calculator rejects division by zero', () async {
      final result = await createDefaultAgentTools().execute('calculator', {'expression': '9 / 0'});
      expect(result, contains('"ok":false'));
      expect(result, contains('Division by zero'));
    });
    test('unknown tools return structured errors', () async {
      final result = await createDefaultAgentTools().execute('not_a_tool', {});
      expect(result, contains('"code":"unknown_tool"'));
      expect(result, contains('calculator'));
    });
    test('rejects missing and unexpected arguments', () async {
      final registry = createDefaultAgentTools();
      expect(await registry.execute('calculator', {}), contains('"code":"missing_arguments"'));
      expect(await registry.execute('calculator', {'expression': '1+1', 'shell': 'bad'}),
          contains('"code":"unexpected_arguments"'));
    });
    test('tool schema exposes required JSON properties', () {
      final schema = createDefaultAgentTools().tools.first.toPromptMap()['parameters'] as Map;
      expect(schema['type'], 'object');
      expect(schema['required'], ['expression']);
      expect(schema['additionalProperties'], false);
    });
  });

  group('ReAct reliability', () {
    test('feeds tool observations into the next model cycle', () async {
      _ScriptedProvider.responses = [
        '{"type":"tool_call","name":"calculator","arguments":{"expression":"42 / 2"}}',
        '{"type":"final","answer":"نصف 42 يساوي 21."}',
      ];
      final output = await _collect(ReActAgentProvider(
        delegate: _ScriptedProvider(), tools: createDefaultAgentTools(), maxSteps: 3,
      ));
      expect(_ScriptedProvider.observationWasReturnedToModel, isTrue);
      expect(output, contains('تنفيذ الأداة calculator'));
      expect(output, contains('نصف 42 يساوي 21'));
      expect(output, isNot(contains('Thought:')));
    });
    test('refuses malformed free-form decisions without running tools', () async {
      _ScriptedProvider.responses = [
        'I think the answer is 21.',
        'Still not JSON: try again.',
      ];
      final output = await _collect(ReActAgentProvider(
        delegate: _ScriptedProvider(), tools: createDefaultAgentTools(),
        maxSteps: 3, maxProtocolRetries: 1,
      ));
      expect(output, contains('تنسيق قرار النموذج غير صالح'));
      expect(output, contains('تعذّر الحصول على قرار'));
      expect(_ScriptedProvider.observationWasReturnedToModel, isFalse);
    });
    test('blocks identical repeated actions', () async {
      _ScriptedProvider.responses = [
        '{"type":"tool_call","name":"calculator","arguments":{"expression":"6 * 7"}}',
        '{"type":"tool_call","name":"calculator","arguments":{"expression":"6 * 7"}}',
        '{"type":"final","answer":"تم التحقق من النتيجة."}',
      ];
      final output = await _collect(ReActAgentProvider(
        delegate: _ScriptedProvider(), tools: createDefaultAgentTools(), maxSteps: 4,
      ));
      expect(output, contains('تم منع تكرار الإجراء'));
    });
    test('does not claim completion after exhausting steps', () async {
      _ScriptedProvider.responses = [
        '{"type":"tool_call","name":"calculator","arguments":{"expression":"2+2"}}',
      ];
      final output = await _collect(ReActAgentProvider(
        delegate: _ScriptedProvider(), tools: createDefaultAgentTools(), maxSteps: 1,
      ));
      expect(output, contains('دون إعلان اكتمال المهمة'));
    });
    test('rejects empty final answers', () async {
      _ScriptedProvider.responses = ['{"type":"final","answer":"  "}'];
      final output = await _collect(ReActAgentProvider(
        delegate: _ScriptedProvider(), tools: createDefaultAgentTools(),
      ));
      expect(output, contains('تعذّر الحصول على قرار'));
    });
  });
}

Future<String> _collect(ReActAgentProvider provider) async {
  final output = StringBuffer();
  await for (final part in provider.generate(AiGenerationRequest(
    conversationId: 'react-test',
    messages: [ChatMessage(
      id: 'user-1', conversationId: 'react-test', role: MessageRole.user,
      content: 'احسب نصف 42', createdAt: DateTime(2026),
    )],
  ))) { output.write(part); }
  return output.toString();
}

class _ScriptedProvider implements AiProvider {
  static List<String> responses = [];
  static bool observationWasReturnedToModel = false;
  int _index = 0;
  @override
  String get id => 'scripted-test-provider';
  @override
  Stream<String> generate(AiGenerationRequest request) async* {
    observationWasReturnedToModel = request.messages.any(
      (message) => message.content.contains('"result":21.0'),
    );
    if (_index >= responses.length) {
      yield '{"type":"final","answer":"لا توجد استجابة اختبارية أخرى."}';
    } else {
      yield responses[_index++];
    }
  }
}
