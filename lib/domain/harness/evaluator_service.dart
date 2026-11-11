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
      case 'mcp_read_resource':
        final resource = toolResult['resource_result'];
        final contents = resource is Map ? resource['contents'] : null;
        final passed = toolResult['ok'] == true && contents is List;
        return ToolVerificationResult(
          passed: passed,
          message: passed
              ? 'MCP resource verification passed: the server returned structured resource contents.'
              : 'MCP resource verification failed: no structured contents were returned.',
          evidence: <String, Object?>{
            'resource_contents_received': passed,
            'content_items': contents is List ? contents.length : 0,
          },
        );
      case 'mcp_call':
        final envelope = toolResult['mcp_result'];
        final content = envelope is Map ? envelope['content'] : null;
        final structured = envelope is Map ? envelope['structuredContent'] : null;
        final passed = toolResult['ok'] == true &&
            envelope is Map &&
            (content is List || structured is Map);
        return ToolVerificationResult(
          passed: passed,
          message: passed
              ? 'MCP transport verification passed: the remote server returned a typed result envelope. Remote business effects are not independently asserted.'
              : 'MCP verification failed: the remote server did not return a valid typed result envelope.',
          evidence: <String, Object?>{
            'transport_result_received': passed,
            'content_blocks': content is List ? content.length : 0,
            'has_structured_content': structured is Map,
            'remote_effect_independently_asserted': false,
          },
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
      case 'create_subagent':
      case 'spawn_subagent':
      case 'delete_subagent':
      case 'check_subagent_status':
      case 'send_message':
      case 'wait_for_message':
      case 'ask_user':
      case 'update_goal':
        final operation = toolResult['status']?.toString() ??
            (toolResult['received'] == true ? 'message_received' : 'accepted');
        final passed = toolResult['ok'] == true &&
            (toolResult['task_id'] == null || toolResult['task_id'].toString().isNotEmpty);
        return ToolVerificationResult(
          passed: passed,
          message: passed
              ? 'Orchestration control-plane operation was accepted by the active scheduler.'
              : 'Orchestration control-plane operation was rejected or returned an invalid result.',
          evidence: <String, Object?>{
            'operation': toolName,
            'accepted': passed,
            'state': operation,
            'task_id': toolResult['task_id'],
            'received_message': toolResult['received'] == true,
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
