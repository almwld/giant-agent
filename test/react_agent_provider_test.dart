import 'package:flutter_test/flutter_test.dart';
import 'package:giant_agent_x/features/assistant/application/default_agent_tools.dart';
import 'package:giant_agent_x/features/assistant/application/react_agent_provider.dart';
import 'package:giant_agent_x/features/assistant/domain/ai_provider.dart';
import 'package:giant_agent_x/features/assistant/domain/chat_message.dart';

void main() {
  group('default local agent tools', () {
    test('calculator evaluates arithmetic and parentheses safely', () async {
      final registry = createDefaultAgentTools();
      final result = await registry.execute('calculator', {
        'expression': '(42 / 2) + 3 * 4',
      });
      expect(result, contains('"ok":true'));
      expect(result, contains('33.0'));
    });

    test('calculator rejects division by zero', () async {
      final result = await createDefaultAgentTools().execute(
        'calculator',
        {'expression': '9 / 0'},
      );
      expect(result, contains('"ok":false'));
      expect(result, contains('Division by zero'));
    });

    test('unknown tools return a structured observation', () async {
      final result = await createDefaultAgentTools().execute(
        'not_a_tool',
        const {},
      );
      expect(result, contains('"ok":false'));
      expect(result, contains('calculator'));
    });
  });

  test('ReAct feeds tool observations into the next model cycle', () async {
    _TwoStepProvider.observationWasReturnedToModel = false;
    final provider = ReActAgentProvider(
      delegate: _TwoStepProvider(),
      tools: createDefaultAgentTools(),
      maxSteps: 3,
    );
    final output = StringBuffer();
    await for (final part in provider.generate(AiGenerationRequest(
      conversationId: 'react-test',
      messages: [
        ChatMessage(
          id: 'user-1',
          conversationId: 'react-test',
          role: MessageRole.user,
          content: 'What is half of 42?',
          createdAt: DateTime(2026),
        ),
      ],
    ))) {
      output.write(part);
    }

    expect(_TwoStepProvider.observationWasReturnedToModel, isTrue);
    expect(output.toString(), contains('تنفيذ الأداة calculator'));
    expect(output.toString(), contains('نصف 42 يساوي 21'));
    expect(output.toString(), isNot(contains('Thought:')));
  });
}

class _TwoStepProvider implements AiProvider {
  static bool observationWasReturnedToModel = false;

  @override
  String get id => 'fake';

  @override
  Stream<String> generate(AiGenerationRequest request) async* {
    final observation = request.messages.any(
      (message) => message.content.contains('"result":21.0'),
    );
    if (observation) {
      observationWasReturnedToModel = true;
      yield 'Final Answer: نصف 42 يساوي 21.';
    } else {
      yield 'Thought: I need to calculate this.\\n'
          'Action: calculator\\n'
          'Action Input: {"expression":"42 / 2"}';
    }
  }
}
