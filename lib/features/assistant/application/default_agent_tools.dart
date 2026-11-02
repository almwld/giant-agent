import 'dart:math' as math;
import 'react_agent_provider.dart';

AgentToolRegistry createDefaultAgentTools() => AgentToolRegistry([
  AgentTool(
    name: 'calculator',
    description: 'Evaluate arithmetic. Supports +, -, *, /, %, ^ and parentheses.',
    parameters: const {'expression': 'Arithmetic expression as a string.'},
    requiredParameters: const ['expression'],
    handler: (arguments) {
      final expression = arguments['expression'];
      if (expression is! String || expression.trim().isEmpty) {
        throw const FormatException('expression is required.');
      }
      if (expression.length > 256) throw const FormatException('Expression is too long.');
      final value = _ArithmeticParser(expression).parse();
      if (!value.isFinite) throw const FormatException('The result is not finite.');
      return value;
    },
  ),
  AgentTool(
    name: 'get_current_datetime',
    description: 'Return the device current local date and time in ISO-8601 format.',
    handler: (_) => DateTime.now().toIso8601String(),
  ),
]);

class _ArithmeticParser {
  _ArithmeticParser(String source) {
    var offset = 0;
    while (offset < source.length) {
      final match = RegExp(r'\s*(\d+(?:\.\d*)?|\.\d+|[()+\-*/%^])').matchAsPrefix(source, offset);
      if (match == null) {
        if (source.substring(offset).trim().isEmpty) break;
        throw FormatException('Unsupported character near "' + source.substring(offset) + '".');
      }
      _tokens.add(match.group(1)!);
      offset = match.end;
    }
  }

  final List<String> _tokens = [];
  int _position = 0;
  double parse() {
    if (_tokens.isEmpty) throw const FormatException('Expression is empty.');
    final value = _expression();
    if (_position != _tokens.length) throw FormatException('Unexpected token: ' + (_peek() ?? ''));
    return value;
  }
  double _expression() {
    var value = _term();
    while (_match('+') || _match('-')) {
      final op = _previous(), right = _term();
      value = op == '+' ? value + right : value - right;
    }
    return value;
  }
  double _term() {
    var value = _power();
    while (_match('*') || _match('/') || _match('%')) {
      final op = _previous(), right = _power();
      if ((op == '/' || op == '%') && right == 0) throw const FormatException('Division by zero is not allowed.');
      if (op == '*') value *= right; else if (op == '/') value /= right; else value %= right;
    }
    return value;
  }
  double _power() {
    final value = _unary();
    if (_match('^')) return math.pow(value, _power()).toDouble();
    return value;
  }
  double _unary() {
    if (_match('+')) return _unary();
    if (_match('-')) return -_unary();
    return _primary();
  }
  double _primary() {
    if (_match('(')) {
      final value = _expression();
      if (!_match(')')) throw const FormatException('Missing closing parenthesis.');
      return value;
    }
    if (_position >= _tokens.length) throw const FormatException('Unexpected end of expression.');
    final token = _tokens[_position++], value = double.tryParse(token);
    if (value == null) throw FormatException('Expected a number, got "' + token + '".');
    return value;
  }
  bool _match(String token) {
    if (_peek() != token) return false;
    _position++;
    return true;
  }
  String? _peek() => _position < _tokens.length ? _tokens[_position] : null;
  String _previous() => _tokens[_position - 1];
}
