import 'dart:convert';

/// Strict parser for the single-tool ReAct envelope consumed by ModelService.
class ReactToolCall {
  const ReactToolCall({required this.name, required this.arguments});
  final String name;
  final Map<String, dynamic> arguments;
}

class ReactDecisionParser {
  ReactDecisionParser._();

  static const int maxEnvelopeCharacters = 16000;
  static const int maxArguments = 64;

  /// Returns null for a normal final answer; malformed envelopes fail closed.
  static ReactToolCall? parseToolCall(String output) {
    const open = '<tool_call>';
    const close = '</tool_call>';
    final start = output.indexOf(open);
    final endTag = output.indexOf(close);
    if (start < 0) {
      if (endTag >= 0) throw const FormatException('Malformed tool-call envelope.');
      return null;
    }
    if (endTag < start + open.length ||
        output.indexOf(open, start + open.length) >= 0 ||
        output.indexOf(close, endTag + close.length) >= 0) {
      throw const FormatException('Ambiguous tool-call envelope.');
    }
    final json = output.substring(start + open.length, endTag).trim();
    if (json.isEmpty || json.length > maxEnvelopeCharacters) {
      throw const FormatException('Tool-call payload is empty or exceeds its limit.');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      throw const FormatException('Tool-call payload is not valid JSON.');
    }
    if (decoded is! Map) throw const FormatException('Tool-call payload must be a JSON object.');
    final payload = Map<String, dynamic>.from(decoded);
    if (payload.length != 2 || !payload.containsKey('name') || !payload.containsKey('arguments')) {
      throw const FormatException('Tool-call payload has an invalid schema.');
    }
    final name = payload['name'];
    final rawArguments = payload['arguments'];
    if (name is! String || !RegExp(r'^[a-zA-Z][a-zA-Z0-9_]{0,63}$').hasMatch(name)) {
      throw const FormatException('Tool name is invalid.');
    }
    if (rawArguments is! Map || rawArguments.length > maxArguments) {
      throw const FormatException('Tool arguments must be a bounded JSON object.');
    }
    final arguments = <String, dynamic>{};
    for (final entry in rawArguments.entries) {
      if (entry.key is! String) throw const FormatException('Tool argument names must be strings.');
      arguments[entry.key as String] = entry.value;
    }
    return ReactToolCall(name: name, arguments: arguments);
  }

  /// Stable signatures make duplicate-action checks independent of map key order.
  static String signature(String name, Map<String, dynamic> arguments) =>
      jsonEncode(<String, Object?>{'name': name, 'arguments': _canonicalize(arguments)});

  static Object? _canonicalize(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return <String, Object?>{for (final key in keys) key: _canonicalize(value[key])};
    }
    if (value is List) return value.map(_canonicalize).toList(growable: false);
    return value;
  }
}
