import 'dart:async';
import 'dart:convert';

import '../domain/ai_provider.dart';
import '../domain/chat_message.dart';

typedef AgentToolHandler = FutureOr<Object?> Function(
  Map<String, dynamic> arguments,
);

class AgentTool {
  const AgentTool({
    required this.name,
    required this.description,
    required this.handler,
    this.parameters = const <String, String>{},
  });

  final String name;
  final String description;
  final AgentToolHandler handler;
  final Map<String, String> parameters;

  Map<String, Object?> toPromptMap() => {
        'name': name,
        'description': description,
        'parameters': parameters,
      };
}

class AgentToolRegistry {
  AgentToolRegistry(Iterable<AgentTool> tools)
      : _tools = {for (final tool in tools) tool.name: tool};

  final Map<String, AgentTool> _tools;

  List<AgentTool> get tools => List.unmodifiable(_tools.values);

  Future<String> execute(String name, Map<String, dynamic> arguments) async {
    final tool = _tools[name];
    if (tool == null) {
      return jsonEncode({
        'ok': false,
        'error': 'Unknown tool: $name',
        'available_tools': _tools.keys.toList(),
      });
    }
    try {
      final result = await tool.handler(arguments);
      return jsonEncode({'ok': true, 'result': result});
    } catch (error) {
      return jsonEncode({'ok': false, 'error': error.toString()});
    }
  }
}

/// Runs a real Thought/Action/Observation loop over an existing AI provider.
///
/// The model's private reasoning is never forwarded to the chat transcript.
/// Only tool execution status and tool observations are shown to the user.
class ReActAgentProvider implements AiProvider {
  ReActAgentProvider({
    required AiProvider delegate,
    required AgentToolRegistry tools,
    this.maxSteps = 8,
    this.maxTranscriptCharacters = 80000,
  })  : _delegate = delegate,
        _tools = tools {
    if (maxSteps < 1) {
      throw ArgumentError.value(maxSteps, 'maxSteps', 'Must be positive.');
    }
  }

  final AiProvider _delegate;
  final AgentToolRegistry _tools;
  final int maxSteps;
  final int maxTranscriptCharacters;

  @override
  String get id => 'react(${_delegate.id})';

  @override
  Stream<String> generate(AiGenerationRequest request) async* {
    final transcript = <ChatMessage>[
      ChatMessage(
        id: 'react-system-${DateTime.now().microsecondsSinceEpoch}',
        conversationId: request.conversationId,
        role: MessageRole.system,
        content: _systemPrompt,
        createdAt: DateTime.now(),
      ),
      ...request.messages,
    ];

    for (var step = 1; step <= maxSteps; step++) {
      final promptSize = transcript.fold<int>(
        0,
        (total, message) => total + message.content.length,
      );
      if (promptSize > maxTranscriptCharacters) {
        yield '\n\nتم إيقاف الوكيل لحماية سياق النموذج من تجاوز الحد المسموح.';
        return;
      }

      final response = StringBuffer();
      await for (final delta in _delegate.generate(AiGenerationRequest(
        conversationId: request.conversationId,
        messages: List.unmodifiable(transcript),
        model: request.model,
        attachments: step == 1 ? request.attachments : const [],
        temperature: request.temperature,
        maxOutputTokens: request.maxOutputTokens,
      ))) {
        response.write(delta);
      }

      final raw = response.toString().trim();
      if (raw.isEmpty) {
        yield '\n\nلم يُرجع النموذج قراراً في دورة التنفيذ $step.';
        return;
      }

      final decision = _parseDecision(raw);
      transcript.add(_message(
        request.conversationId,
        MessageRole.assistant,
        raw,
      ));

      if (decision.finalAnswer != null) {
        final answer = decision.finalAnswer!.trim();
        yield answer.isEmpty ? 'اكتملت المعالجة دون نص إجابة.' : answer;
        return;
      }

      final action = decision.action;
      if (action == null) {
        yield '\n\nتعذر فهم قرار النموذج. أعد صياغة الطلب أو جرّب نموذجاً يدعم اتباع تعليمات الأدوات.';
        return;
      }

      yield '\n\n⏳ تنفيذ الأداة ${action.name} (الخطوة $step من $maxSteps)…\n';
      final observation = await _tools.execute(action.name, action.arguments);
      yield '📋 نتيجة الأداة: $observation\n';

      transcript.add(_message(
        request.conversationId,
        MessageRole.user,
        'Observation for ${action.name}: $observation\n'
        'Use this observation to decide the next action. '
        'Do not repeat a completed action unless necessary. '
        'Return another Action or a Final Answer.',
      ));
    }

    yield '\n\nتوقف الوكيل بأمان بعد بلوغ الحد الأقصى ($maxSteps خطوات) دون إعلان اكتمال المهمة.';
  }

  String get _systemPrompt {
    final toolDefinitions = jsonEncode(
      _tools.tools.map((tool) => tool.toPromptMap()).toList(),
    );
    return '''
أنت وكيل تنفيذي يستخدم حلقة ReAct متعددة الخطوات.
الأدوات المتاحة فعلياً (لا تخترع أدوات غير موجودة):
$toolDefinitions

في كل دورة أخرج قراراً واحداً فقط بالتنسيق التالي عند الحاجة إلى أداة:
Thought: ملخص داخلي موجز لا يتضمنه الرد النهائي
Action: اسم_الأداة
Action Input: {"argument":"value"}

وعند اكتمال المهمة:
Final Answer: الإجابة النهائية للمستخدم

قواعد إلزامية:
- لا تدّع تنفيذ أداة قبل استدعائها واستلام Observation.
- استخدم Action واحداً في كل دورة.
- يجب أن تكون Action Input كائن JSON صالحاً.
- بعد كل Observation أعد تقييم المهمة، ويمكنك استدعاء أداة أخرى.
- إذا فشلت أداة، اقرأ الخطأ وحاول إصلاح المدخلات أو اشرح التعذر.
- لا تكشف سلسلة التفكير الداخلية. أخرج فقط قرار الأداة أو الإجابة النهائية.
- لا تخترع نتائج أو معلومات لم تُرجعها الأدوات.
''';
  }

  ChatMessage _message(
    String conversationId,
    MessageRole role,
    String content,
  ) =>
      ChatMessage(
        id: 'react-${DateTime.now().microsecondsSinceEpoch}-${role.name}',
        conversationId: conversationId,
        role: role,
        content: content,
        createdAt: DateTime.now(),
      );

  _AgentDecision _parseDecision(String output) {
    final finalMatch = RegExp(
      r'Final Answer:\s*([\s\S]*)',
      caseSensitive: false,
    ).firstMatch(output);
    if (finalMatch != null) {
      return _AgentDecision(finalAnswer: finalMatch.group(1) ?? '');
    }

    final actionMatch = RegExp(
      r'Action:\s*([a-zA-Z0-9_.-]+)\s*Action Input:\s*',
      caseSensitive: false,
    ).firstMatch(output);
    if (actionMatch != null) {
      final jsonStart = actionMatch.end;
      final jsonText = _extractJsonObject(output, jsonStart);
      if (jsonText == null) {
        throw const FormatException('Action Input must be a JSON object.');
      }
      final decoded = jsonDecode(jsonText);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Action Input must decode to an object.');
      }
      return _AgentDecision(
        action: _AgentAction(actionMatch.group(1)!, decoded),
      );
    }

    // Also accept a strict JSON envelope for models that follow JSON better.
    try {
      final decoded = jsonDecode(output);
      if (decoded is Map<String, dynamic>) {
        if (decoded['final_answer'] is String) {
          return _AgentDecision(finalAnswer: decoded['final_answer'] as String);
        }
        final name = decoded['action'];
        final arguments = decoded['action_input'];
        if (name is String && arguments is Map<String, dynamic>) {
          return _AgentDecision(
            action: _AgentAction(name, arguments),
          );
        }
      }
    } on FormatException {
      // Fall through to a clear protocol error.
    }
    return const _AgentDecision();
  }

  String? _extractJsonObject(String source, int start) {
    final opening = source.indexOf('{', start);
    if (opening < 0) return null;
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var index = opening; index < source.length; index++) {
      final char = source[index];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (char == '\\') {
          escaped = true;
        } else if (char == '"') {
          inString = false;
        }
        continue;
      }
      if (char == '"') {
        inString = true;
      } else if (char == '{') {
        depth++;
      } else if (char == '}') {
        depth--;
        if (depth == 0) return source.substring(opening, index + 1);
      }
    }
    return null;
  }
}

class _AgentAction {
  const _AgentAction(this.name, this.arguments);

  final String name;
  final Map<String, dynamic> arguments;
}

class _AgentDecision {
  const _AgentDecision({this.action, this.finalAnswer});

  final _AgentAction? action;
  final String? finalAnswer;
}
