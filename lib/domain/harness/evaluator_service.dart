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
      case 'create_subagent':
        final child = toolResult['subagent'];
        final passed = child is Map && child['id'] == toolArgs['id'] &&
            child['status'] == 'idle';
        return ToolVerificationResult(
          passed: passed,
          message: passed ? 'Subagent registration was persisted in the request lifecycle.' : 'Subagent registration could not be verified.',
          evidence: <String, Object?>{'registered': passed, 'agent_id': toolArgs['id']},
        );
      case 'spawn_subagent':
        final child = toolResult['subagent'];
        final passed = child is Map && child['status'] == 'completed' &&
            (child['result']?.toString() ?? '').trim().isNotEmpty;
        return ToolVerificationResult(
          passed: passed,
          message: passed ? 'Subagent completed and returned a durable result.' : 'Subagent did not produce a verified completed result.',
          evidence: <String, Object?>{'completed': passed, 'agent_id': toolArgs['id']},
        );
      case 'delete_subagent':
        final child = toolResult['subagent'];
        final passed = child is Map && child['dismissed'] == true;
        return ToolVerificationResult(
          passed: passed,
          message: passed ? 'Subagent was dismissed without erasing its audit history.' : 'Subagent dismissal was not confirmed.',
          evidence: <String, Object?>{'dismissed': passed, 'agent_id': toolArgs['id']},
        );
      case 'check_subagent_status':
        final child = toolResult['subagent'];
        final passed = child is Map && child['id'] == toolArgs['id'] && child['status'] != null;
        return ToolVerificationResult(
          passed: passed,
          message: passed ? 'Subagent status snapshot was returned.' : 'Subagent status snapshot is invalid.',
          evidence: <String, Object?>{'snapshot_received': passed},
        );
      case 'send_message':
        final passed = toolResult['message_queued'] == true &&
            toolResult['agent_id'] == toolArgs['agent_id'];
        return ToolVerificationResult(
          passed: passed,
          message: passed ? 'Message was accepted by the target subagent mailbox.' : 'Message delivery could not be confirmed.',
          evidence: <String, Object?>{'message_queued': passed},
        );
      case 'wait_for_message':
        final passed = toolResult['received'] == true || toolResult['timed_out'] == true;
        return ToolVerificationResult(
          passed: passed,
          message: passed ? 'Mailbox wait completed; received and timeout outcomes are both explicit.' : 'Mailbox wait returned an invalid state.',
          evidence: <String, Object?>{'received': toolResult['received'] == true, 'timed_out': toolResult['timed_out'] == true},
        );
      case 'ask_user':
        final passed = toolResult.containsKey('cancelled') &&
            (toolResult['cancelled'] == true || toolResult['answer'] is String);
        return ToolVerificationResult(
          passed: passed,
          message: passed ? 'User response or explicit cancellation was received.' : 'No user response was confirmed.',
          evidence: <String, Object?>{'answered': toolResult['answer'] is String, 'cancelled': toolResult['cancelled'] == true},
        );
      case 'update_goal':
        final passed = toolResult['goal'] == toolArgs['goal'];
        return ToolVerificationResult(
          passed: passed,
          message: passed ? 'Updated request goal was stored in the active lifecycle.' : 'Updated request goal could not be read back.',
          evidence: <String, Object?>{'goal_updated': passed},
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
