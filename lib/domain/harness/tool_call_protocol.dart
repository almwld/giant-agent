import 'dart:convert';

/// Parses the existing tagged tool-call envelope without using a non-greedy
/// regular expression, which breaks when arguments contain nested JSON objects.
class ToolCallProtocol {
  ToolCallProtocol._();

  static const String openingTag = '<tool_call>';
  static const String closingTag = '</tool_call>';

  /// Returns null when [output] contains no tool-call tag.
  ///
  /// Throws [FormatException] for malformed, truncated, or non-object payloads.
  static Map<String, dynamic>? extract(String output) {
    final tagStart = output.indexOf(openingTag);
    if (tagStart < 0) return null;

    final contentStart = tagStart + openingTag.length;
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
        } else if (char == '\\\\') {
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

    final decoded = jsonDecode(output.substring(objectStart, objectEnd));
    if (decoded is! Map) {
      throw const FormatException('Tool call payload must be a JSON object.');
    }
    return Map<String, dynamic>.from(decoded);
  }
}
