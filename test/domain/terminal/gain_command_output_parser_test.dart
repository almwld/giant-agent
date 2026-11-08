import 'package:flutter_test/flutter_test.dart';
import 'package:giant_agent_x/domain/terminal/gain_command_output_parser.dart';

void main() {
  const marker = '__GAIN_DONE_nonce_';
  test('parses a completion marker split across stream chunks', () {
    final parser = GainCommandOutputParser(marker: marker);
    parser.add('command output\r\n__GAIN');
    parser.add('_DONE_nonce_');
    parser.add('127__prompt> ');
    expect(parser.exitCode, 127);
    expect(parser.isComplete, isTrue);
    expect(parser.output, 'command output\r\n');
  });
  test('parses successful and non-zero exit codes exactly', () {
    for (final code in [0, 1, 2, 127]) {
      final parser = GainCommandOutputParser(marker: marker);
      parser.add('result-$code\n' + marker + code.toString() + '__');
      expect(parser.exitCode, code);
      expect(parser.output, 'result-$code\n');
    }
  });
  test('keeps scanning after output capture reaches its limit', () {
    final parser = GainCommandOutputParser(marker: marker, maxOutputCharacters: 8);
    parser.add('123456789012345');
    parser.add(marker + '127__');
    expect(parser.output, '12345678');
    expect(parser.exitCode, 127);
  });
  test('does not accept a marker for a different execution token', () {
    final parser = GainCommandOutputParser(marker: marker);
    parser.add('output __GAIN_DONE_other_0__');
    expect(parser.exitCode, isNull);
    expect(parser.output, 'output __GAIN_DONE_other_0__');
  });
  test('does not append data after the first valid completion marker', () {
    final parser = GainCommandOutputParser(marker: marker);
    parser.add('before ' + marker + '2__after');
    parser.add('later output');
    expect(parser.exitCode, 2);
    expect(parser.output, 'before ');
  });
}