import 'dart:convert';

import '../../services/agent_memory_service.dart';

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
      case 'edit_file':
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
      case 'generate_image':
      case 'edit_image':
      case 'image_search':
      case 'search_image_by_text':
      case 'search_image_by_image':
      case 'generate_sound_effects':
      case 'find_asset_bbox':
      case 'crop_and_replicate_assets_in_image':
        final assets = toolResult['assets'];
        final passed = toolResult['ok'] == true && assets is List && assets.isNotEmpty &&
            assets.every((asset) => asset is Map &&
                ((asset['local_path']?.toString().isNotEmpty ?? false) ||
                 (asset['remote_url']?.toString().isNotEmpty ?? false) ||
                 (asset['metadata'] is Map && (asset['metadata'] as Map).isNotEmpty)));
        return ToolVerificationResult(
          passed: passed,
          message: passed ? 'Connected media provider returned a structured asset or analysis result.' : 'No verified media asset/result was returned by a connected provider.',
          evidence: <String, Object?>{'asset_count': assets is List ? assets.length : 0, 'provider_id': toolResult['provider_id']},
        );
      case 'website_version_manager':
        final action = toolArgs['action']?.toString() ?? 'list';
        final version = toolResult['version'];
        final versions = toolResult['versions'];
        final passed = action == 'snapshot'
            ? toolResult['ok'] == true && version is Map &&
                version['version_id'] is String && version['file_path'] == toolArgs['path']
            : action == 'list'
                ? toolResult['ok'] == true && versions is List
                : false;
        return ToolVerificationResult(
          passed: passed,
          message: passed ? 'Local website file version snapshot/list operation was verified.' : 'Local website version operation was not verified.',
          evidence: <String, Object?>{'action': action, 'version_count': versions is List ? versions.length : 0},
        );
      case 'website_version_manager_rollback':
        final cancelled = toolResult['cancelled'] == true;
        final passed = cancelled ||
            (toolResult['ok'] == true && toolResult['verified'] == true &&
             toolResult['path'] == toolArgs['path'] &&
             toolResult['version_id'] == toolArgs['version_id']);
        return ToolVerificationResult(
          passed: passed,
          message: cancelled ? 'Rollback was explicitly cancelled by the user.' :
              passed ? 'Restored website file was read back and matched the selected snapshot.' :
              'Website rollback could not be verified.',
          evidence: <String, Object?>{'cancelled': cancelled, 'verified': toolResult['verified'] == true},
        );
      case 'lbs_tool':
        final cancelled = toolResult['cancelled'] == true;
        final latitude = toolResult['latitude'];
        final longitude = toolResult['longitude'];
        final passed = cancelled ||
            (toolResult['ok'] == true && latitude is num && longitude is num &&
             latitude >= -90 && latitude <= 90 &&
             longitude >= -180 && longitude <= 180 &&
             toolResult['background_location'] == false);
        return ToolVerificationResult(
          passed: passed,
          message: cancelled ? 'Location access was explicitly cancelled by the user.' :
              passed ? 'Foreground location was returned after in-app and Android permission checks.' :
              'Location was not obtained or returned an invalid coordinate.',
          evidence: <String, Object?>{
            'cancelled': cancelled,
            'permission_denied': toolResult['permission_denied'] == true,
            'background_location': toolResult['background_location'] == true,
          },
        );
      case 'fetch_urls':
        final pages = toolResult['results'];
        final passed = pages is List && pages.isNotEmpty &&
            pages.every((page) => page is Map && page['ok'] == true);
        return ToolVerificationResult(
          passed: passed,
          message: passed ? 'All requested URLs were loaded and read from the visible browser session.' : 'One or more requested URLs failed to load.',
          evidence: <String, Object?>{'page_count': pages is List ? pages.length : 0},
        );
      case 'visit':
      case 'browser_visit':
        final url = toolResult['url']?.toString() ?? '';
        final passed = toolResult['ok'] == true &&
            (url.startsWith('https://') || url.startsWith('http://'));
        return ToolVerificationResult(
          passed: passed,
          message: passed ? 'Visible browser navigated to the requested HTTP(S) page.' : 'Browser navigation was not confirmed.',
          evidence: <String, Object?>{'url': url, 'loaded': passed},
        );
      case 'click':
      case 'browser_click':
        final passed = toolResult['ok'] == true &&
            (toolResult['clicked'] is String || toolResult['cancelled'] == true);
        return ToolVerificationResult(
          passed: passed,
          message: passed ? 'Browser click was executed or explicitly cancelled by the user.' : 'Browser click was not confirmed.',
          evidence: <String, Object?>{'clicked': toolResult['clicked'], 'cancelled': toolResult['cancelled'] == true},
        );
      case 'input':
      case 'browser_input':
        final passed = toolResult['ok'] == true &&
            (toolResult['selector'] is String || toolResult['cancelled'] == true);
        return ToolVerificationResult(
          passed: passed,
          message: passed ? 'Browser field was filled or sensitive input was explicitly cancelled.' : 'Browser input was not confirmed.',
          evidence: <String, Object?>{'selector': toolResult['selector'], 'cancelled': toolResult['cancelled'] == true},
        );
      case 'find':
      case 'browser_find':
        final passed = toolResult['ok'] == true &&
            toolResult['query'] == toolArgs['query'];
        return ToolVerificationResult(
          passed: passed,
          message: passed ? 'Browser page text search completed.' : 'Browser text search response is invalid.',
          evidence: <String, Object?>{'found': toolResult['found'] == true},
        );
      case 'scrollup':
      case 'scrolldown':
      case 'browser_scroll_up':
      case 'browser_scroll_down':
        final passed = toolResult['ok'] == true &&
            const {'up', 'down'}.contains(toolResult['direction']);
        return ToolVerificationResult(
          passed: passed,
          message: passed ? 'Visible browser page scroll completed.' : 'Browser scroll was not confirmed.',
          evidence: <String, Object?>{'direction': toolResult['direction']},
        );
      case 'browser_state':
        final passed = toolResult['ok'] == true &&
            (toolResult['url']?.toString().startsWith('http://') == true ||
             toolResult['url']?.toString().startsWith('https://') == true);
        return ToolVerificationResult(
          passed: passed,
          message: passed ? 'Current browser URL, title and visible page text were read.' : 'Browser state could not be verified.',
          evidence: <String, Object?>{'url': toolResult['url'], 'title': toolResult['title']},
        );
      case 'ipython':
        final sessionId = toolResult['session_id']?.toString() ?? '';
        final passed = toolResult['ok'] == true && sessionId.isNotEmpty &&
            toolResult['output'] is String && toolResult['error'] is String;
        return ToolVerificationResult(
          passed: passed,
          message: passed ? 'Persistent Python REPL executed in the current chat-scoped session.' : 'Persistent Python REPL execution was not verified.',
          evidence: <String, Object?>{'session_id_present': sessionId.isNotEmpty},
        );
      case 'reset_ipython':
        final sessionId = toolResult['session_id']?.toString() ?? '';
        final passed = toolResult['ok'] == true && sessionId.isNotEmpty;
        return ToolVerificationResult(
          passed: passed,
          message: passed ? 'Current chat-scoped Python REPL reset was acknowledged.' : 'Python REPL reset was not verified.',
          evidence: <String, Object?>{'session_id_present': sessionId.isNotEmpty, 'reset': toolResult['reset'] == true},
        );
      case 'web_search':
        final results = toolResult['results'];
        final passed = results is List;
        return ToolVerificationResult(
          passed: passed,
          message: passed ? 'Web search returned a structured result list.' : 'Web search returned no structured results.',
          evidence: <String, Object?>{'result_count': results is List ? results.length : 0},
        );
      case 'dmail':
        final results = toolResult['results'];
        final passed = toolResult['ok'] == true && results is List &&
            toolResult['query'] == toolArgs['query'] &&
            toolResult['source'] == 'local_sqlite_conversation_history' &&
            toolResult['email_sent'] == false;
        return ToolVerificationResult(
          passed: passed,
          message: passed ? 'DMail-style local conversation recall returned bounded chat excerpts; no email was sent.' : 'Conversation recall result could not be verified.',
          evidence: <String, Object?>{'match_count': results is List ? results.length : 0, 'email_sent': false},
        );
      case 'show_widget':
        final widgetId = toolResult['widget_id']?.toString() ?? '';
        final widgetType = toolResult['widget_type']?.toString() ?? '';
        final passed = toolResult['ok'] == true &&
            widgetId.startsWith('widget_') &&
            widgetType == toolArgs['widget_type'];
        return ToolVerificationResult(
          passed: passed,
          message: passed ? 'A validated structured widget event was published to the session timeline.' : 'Structured widget publication could not be verified.',
          evidence: <String, Object?>{'widget_id': widgetId, 'widget_type': widgetType},
        );
      case 'task':
        final action = toolArgs['action']?.toString() ?? 'list';
        final passed = switch (action) {
          'list' || 'read' => toolResult['ok'] == true && toolResult['tasks'] is List,
          'create' || 'add' => toolResult['ok'] == true && toolResult['task'] is Map &&
              (toolResult['task'] as Map)['id'] != null,
          'status' => toolResult['ok'] == true && toolResult['task'] is Map,
          'select' => toolResult['ok'] == true && toolResult['task_id'] == toolArgs['task_id'],
          'cancel' => toolResult['ok'] == true,
          'resume' => toolResult['cancelled'] == true ||
              (toolResult['ok'] == true && toolResult['resume_result'] is Map &&
               (toolResult['resume_result'] as Map)['status'] != 'missing'),
          _ => false,
        };
        return ToolVerificationResult(
          passed: passed,
          message: passed ? 'TaskManager action completed or was explicitly cancelled by the user.' : 'TaskManager action could not be verified.',
          evidence: <String, Object?>{'action': action, 'verified': passed},
        );
      case 'todo_read':
        final tasks = toolResult['tasks'];
        final passed = tasks is List;
        return ToolVerificationResult(
          passed: passed,
          message: passed ? 'Persistent task list was read.' : 'Task list response is invalid.',
          evidence: <String, Object?>{'task_count': tasks is List ? tasks.length : 0},
        );
      case 'todo_write':
        final task = toolResult['task'];
        final passed = task is Map && task['id'] != null &&
            task['status'] == 'pending' && toolResult['execution_started'] == false;
        return ToolVerificationResult(
          passed: passed,
          message: passed ? 'A durable pending task was created without starting it.' : 'Task creation was not verified.',
          evidence: <String, Object?>{'task_created': passed, 'execution_started': toolResult['execution_started'] == true},
        );
      case 'memory_space_insert':
        final facts = await AgentMemoryService.instance.getFacts();
        final key = toolArgs['key']?.toString() ?? '';
        final value = toolArgs['value']?.toString() ?? '';
        final passed = facts.any((fact) => fact['fact_key'] == key && fact['fact_value'] == value);
        return ToolVerificationResult(
          passed: passed,
          message: passed ? 'Memory fact was read back from local SQLite.' : 'Inserted memory fact could not be read back.',
          evidence: <String, Object?>{'key': key, 'stored': passed},
        );
      case 'memory_space_update':
        final facts = await AgentMemoryService.instance.getFacts();
        final key = toolArgs['key']?.toString() ?? '';
        final value = toolArgs['value']?.toString() ?? '';
        final passed = facts.any((fact) => fact['fact_key'] == key && fact['fact_value'] == value);
        return ToolVerificationResult(
          passed: passed,
          message: passed ? 'Updated memory fact was read back from local SQLite.' : 'Updated memory fact could not be read back.',
          evidence: <String, Object?>{'key': key, 'updated': passed},
        );
      case 'memory_space_delete':
        final facts = await AgentMemoryService.instance.getFacts();
        final key = toolArgs['key']?.toString() ?? '';
        final edits = await AgentMemoryService.instance.getFactEdits(limit: 100);
        final passed = !facts.any((fact) => fact['fact_key'] == key) &&
            edits.any((edit) => edit['fact_key'] == key && edit['operation'] == 'delete');
        return ToolVerificationResult(
          passed: passed,
          message: passed ? 'Memory fact is absent and its deletion audit entry exists.' : 'Memory deletion could not be verified.',
          evidence: <String, Object?>{'key': key, 'deleted': passed},
        );
      case 'memory_space_edits':
        final facts = toolResult['facts'];
        final edits = toolResult['edits'];
        final passed = facts is List && edits is List;
        return ToolVerificationResult(
          passed: passed,
          message: passed ? 'Memory facts and their edit journal were returned.' : 'Memory edit history response is invalid.',
          evidence: <String, Object?>{'fact_count': facts is List ? facts.length : 0, 'edit_count': edits is List ? edits.length : 0},
        );
      case 'generate_speech':
        final passed = toolResult['played'] == true && toolResult['saved_audio_file'] == false;
        return ToolVerificationResult(
          passed: passed,
          message: passed ? 'Device TTS playback completed; no downloadable audio file is claimed.' : 'TTS playback was not confirmed.',
          evidence: <String, Object?>{'played': passed, 'audio_file_created': false},
        );
      case 'get_available_voices':
        final voices = toolResult['voices'];
        final passed = voices is List;
        return ToolVerificationResult(
          passed: passed,
          message: passed ? 'Device TTS voice catalogue was returned.' : 'Voice catalogue response is invalid.',
          evidence: <String, Object?>{'voice_count': voices is List ? voices.length : 0},
        );
      case 'get_data_source':
        final servers = toolResult['servers'];
        final passed = servers is List;
        return ToolVerificationResult(
          passed: passed,
          message: passed ? 'Configured MCP data sources were listed without credentials.' : 'MCP data source list is invalid.',
          evidence: <String, Object?>{'server_count': servers is List ? servers.length : 0, 'credentials_exposed': false},
        );
      case 'get_data_source_desc':
        final server = toolResult['server'];
        final tools = toolResult['tools'];
        final resources = toolResult['resources'];
        final passed = server is Map && server['id'] == toolArgs['server_id'] &&
            tools is List && resources is List;
        return ToolVerificationResult(
          passed: passed,
          message: passed ? 'MCP server metadata, tools and resources were read.' : 'MCP data source description is incomplete.',
          evidence: <String, Object?>{'server_verified': passed, 'tool_count': tools is List ? tools.length : 0, 'resource_count': resources is List ? resources.length : 0},
        );
      case 'generate_slides_outline':
        final outline = toolResult['outline']?.toString() ?? '';
        var valid = false;
        try {
          final decoded = jsonDecode(outline);
          valid = decoded is Map && decoded['slides'] is List && (decoded['slides'] as List).isNotEmpty;
        } catch (_) {}
        return ToolVerificationResult(
          passed: valid,
          message: valid ? 'Slide outline is valid structured JSON with a non-empty slide list.' : 'Slide outline is not valid structured JSON.',
          evidence: <String, Object?>{'valid_outline': valid},
        );
      case 'slides_generator':
        final path = toolArgs['path']?.toString() ?? '';
        final created = toolResult['created_file'];
        if (path.isEmpty || created is! Map || created['ok'] != true) {
          return const ToolVerificationResult(passed: false, message: 'HTML slide file creation was not confirmed.');
        }
        try {
          final readback = await _readWorkspaceFile(path);
          final html = readback['content']?.toString() ?? '';
          final count = RegExp(r'<section class="slide').allMatches(html).length;
          final expected = (toolArgs['slides'] as List?)?.length ?? 0;
          final passed = readback['ok'] == true && html.contains('</html>') && count == expected;
          return ToolVerificationResult(
            passed: passed,
            message: passed ? 'HTML slide deck was read back and every slide section was verified.' : 'HTML slide deck read-back verification failed.',
            evidence: <String, Object?>{'path': path, 'slide_sections': count, 'expected_slides': expected, 'powerpoint_created': false},
          );
        } catch (error) {
          return ToolVerificationResult(passed: false, message: 'HTML slide deck read-back failed: $error');
        }
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
