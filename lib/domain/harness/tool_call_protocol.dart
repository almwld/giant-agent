import 'dart:convert';

/// Parses and validates the single tagged tool-call envelope used by the
/// ReAct executor. Nested JSON objects and escaped strings are supported.
class ToolCallProtocol {
  ToolCallProtocol._();

  static const String openingTag = '<tool_call>';
  static const String closingTag = '</tool_call>';
  static const int maxEnvelopeCharacters = 16000;
  static const int maxArguments = 64;

  /// Returns null for a normal final answer. Malformed or ambiguous tool calls
  /// fail closed before any tool is dispatched.
  static Map<String, dynamic>? extract(String output) {
    final tagStart = output.indexOf(openingTag);
    if (tagStart < 0) {
      if (output.contains(closingTag)) {
        throw const FormatException('Tool call closing tag has no opening tag.');
      }
      return null;
    }

    final contentStart = tagStart + openingTag.length;
    if (output.indexOf(openingTag, contentStart) >= 0) {
      throw const FormatException('Multiple tool-call envelopes are not allowed.');
    }

    final objectStart = output.indexOf('{', contentStart);
    if (objectStart < 0 ||
        output.substring(contentStart, objectStart).trim().isNotEmpty) {
      throw const FormatException('Tool call must contain one JSON object.');
    }

    var depth = 0;
    var inString = false;
    var escaped = false;
    var objectEnd = -1;

    for (var i = objectStart; i < output.length; i++) {
      final char = output[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (char == r'\') {
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
        if (depth < 0) {
          throw const FormatException('Tool call JSON has unbalanced braces.');
        }
        if (depth == 0) {
          objectEnd = i + 1;
          break;
        }
      }
    }

    if (objectEnd < 0 || inString || depth != 0) {
      throw const FormatException('Tool call JSON is incomplete.');
    }

    final tagEnd = output.indexOf(closingTag, objectEnd);
    if (tagEnd < 0 ||
        output.substring(objectEnd, tagEnd).trim().isNotEmpty) {
      throw const FormatException('Tool call closing tag is missing or malformed.');
    }
    if (tagEnd - contentStart > maxEnvelopeCharacters ||
        output.indexOf(closingTag, tagEnd + closingTag.length) >= 0) {
      throw const FormatException('Tool-call envelope is ambiguous or exceeds its limit.');
    }

    final decoded = jsonDecode(output.substring(objectStart, objectEnd));
    if (decoded is! Map) {
      throw const FormatException('Tool call payload must be a JSON object.');
    }

    final payload = Map<String, dynamic>.from(decoded);
    if (payload.length != 2 ||
        !payload.containsKey('name') ||
        !payload.containsKey('arguments')) {
      throw const FormatException('Tool call payload has an invalid schema.');
    }

    final name = payload['name'];
    final rawArguments = payload['arguments'];
    if (name is! String ||
        !RegExp(r'^[a-zA-Z][a-zA-Z0-9_]{0,63}$').hasMatch(name)) {
      throw const FormatException('Tool name is invalid.');
    }
    if (rawArguments is! Map || rawArguments.length > maxArguments) {
      throw const FormatException('Tool arguments must be a bounded JSON object.');
    }

    payload['arguments'] = Map<String, dynamic>.from(rawArguments);
    return payload;
  }
}
