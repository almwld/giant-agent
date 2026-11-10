class ToolVerificationResult {
  const ToolVerificationResult({required this.passed, required this.message, this.evidence});
  final bool passed;
  final String message;
  final Map<String, Object?>? evidence;
}

/// Checks observable tool effects instead of trusting model text or a success flag.
class EvaluatorService {
  EvaluatorService({required Future<Map<String, dynamic>> Function(String path) readWorkspaceFile})
      : _readWorkspaceFile = readWorkspaceFile;

  final Future<Map<String, dynamic>> Function(String path) _readWorkspaceFile;

  Future<ToolVerificationResult> verify(
    String goal,
    String toolName,
    Map<String, dynamic> toolArgs,
    Map<String, dynamic> toolResult,
  ) async {
    if (toolResult['ok'] != true) {
      return ToolVerificationResult(
        passed: false,
        message: toolResult['error']?.toString() ?? 'The tool did not report successful execution.',
      );
    }
    switch (toolName) {
      case 'create_file':
      case 'write_file':
        final path = toolArgs['path']?.toString().trim() ?? '';
        final expected = toolArgs['content'];
        if (path.isEmpty || expected is! String) {
          return const ToolVerificationResult(passed: false, message: 'File verification requires path and expected content.');
        }
        try {
          final actual = await _readWorkspaceFile(path);
          if (actual['ok'] != true || actual['content'] is! String) {
            return ToolVerificationResult(
              passed: false,
              message: actual['error']?.toString() ?? 'The file could not be read back after writing.',
            );
          }
          final content = actual['content'] as String;
          final matches = content == expected;
          return ToolVerificationResult(
            passed: matches,
            message: matches
                ? 'Read-back verification passed: file content matches exactly.'
                : 'Read-back verification failed: saved content differs from requested content.',
            evidence: <String, Object?>{
              'path': path,
              'expected_characters': expected.length,
              'actual_characters': content.length,
              'content_matches': matches,
            },
          );
        } catch (error) {
          return ToolVerificationResult(passed: false, message: 'Read-back verification failed: $error');
        }
      case 'read_file':
        final expectedPath = toolArgs['path']?.toString();
        final actualPath = toolResult['path']?.toString();
        final content = toolResult['content'];
        final passed = expectedPath != null && expectedPath.isNotEmpty &&
            actualPath == expectedPath && content is String;
        return ToolVerificationResult(
          passed: passed,
          message: passed
              ? 'Read verification passed: requested path returned readable content.'
              : 'Read verification failed: requested path did not return readable content.',
          evidence: <String, Object?>{
            'requested_path': expectedPath,
            'returned_path': actualPath,
            'content_characters': content is String ? content.length : 0,
          },
        );
      case 'list_files':
        final files = toolResult['files'];
        final passed = files is List;
        return ToolVerificationResult(
          passed: passed,
          message: passed ? 'Workspace listing returned a structured file list.' : 'Workspace listing did not return a file list.',
          evidence: <String, Object?>{'file_count': files is List ? files.length : 0},
        );
      case 'execute_python':
        final output = toolResult['output']?.toString() ?? '';
        final error = toolResult['error']?.toString() ?? '';
        final failedOutput = RegExp(r'Traceback|SyntaxError|NameError|Exception:', caseSensitive: false)
            .hasMatch('$output\n$error');
        final passed = error.isEmpty && !failedOutput;
        return ToolVerificationResult(
          passed: passed,
          message: passed
              ? 'Python runtime reported success with no error output; script goal semantics are not independently asserted.'
              : 'Python execution failed its error-output checks.',
          evidence: <String, Object?>{
            'execution_confirmed': passed,
            'goal_semantics_independently_asserted': false,
          },
        );
      default:
        return ToolVerificationResult(
          passed: false,
          message: 'No independent verifier is registered for tool "$toolName".',
        );
    }
  }
}
