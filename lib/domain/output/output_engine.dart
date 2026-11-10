import 'dart:convert';

import '../kernel/agent_kernel_store.dart';
import '../../services/model_service.dart';
import '../../agent/architecture/agent_event_bus.dart';

class OutputCollectionResult {
  const OutputCollectionResult({
    required this.artifacts,
    required this.verified,
    required this.summary,
  });

  final List<Map<String, dynamic>> artifacts;
  final bool verified;
  final String summary;
}

/// Collects worker results and real workspace artifacts before a durable
/// request is allowed to enter its completed state.
class OutputEngine {
  OutputEngine({required AgentKernelStore store, required ModelService models})
      : _store = store,
        _models = models;

  final AgentKernelStore _store;
  final ModelService _models;

  Future<OutputCollectionResult> finalize({
    required String requestId,
    required String conversationId,
    required String finalText,
    required String requestStatus,
    String? failure,
  }) async {
    _emit(requestId, 'output_collection_started', 'يجمع محرك المخرجات النتائج والملفات',
        'running', details: 'ربط نتائج الوكلاء والتحقق من وجود الملفات قبل إغلاق المهمة.');
    final artifacts = <Map<String, dynamic>>[];
    final now = DateTime.now().toUtc().toIso8601String();

    if (finalText.trim().isNotEmpty) {
      final preview = _preview(finalText, 2400);
      final artifact = _artifact(
        id: 'output_${requestId}_final_text',
        requestId: requestId,
        conversationId: conversationId,
        kind: 'text',
        title: 'النتيجة النهائية',
        mimeType: 'text/plain; charset=utf-8',
        content: finalText,
        preview: preview,
        status: requestStatus == 'completed' ? 'available' : 'partial',
        verified: true,
        verificationMessage: 'تم التحقق من وجود النص النهائي وحفظه. هذا تحقق من سلامة المخرج، وليس تدقيقاً مستقلاً لكل ادعاءاته.',
        metadata: <String, Object?>{'source': 'parent_synthesis', 'verification_scope': 'content_presence'},
        createdAt: now,
      );
      await _save(artifact);
      artifacts.add(artifact);
    }

    final children = await _store.subagentsForRequest(requestId);
    final childById = <String, Map<String, dynamic>>{
      for (final child in children) child['id'].toString(): child,
    };
    final childFailures = children.where((child) => child['status'] != 'completed').length;
    final emptyChildResults = children.where((child) =>
        child['status'] == 'completed' &&
        (child['last_result']?.toString() ?? '').trim().isEmpty).length;
    var dependencyFailures = 0;
    for (final child in children) {
      final dependencies = child['depends_on'];
      if (dependencies is! List) continue;
      for (final dependency in dependencies) {
        final upstream = childById[dependency.toString()];
        if (upstream == null || upstream['status'] != 'completed' ||
            (upstream['last_result']?.toString() ?? '').trim().isEmpty) {
          dependencyFailures++;
        }
      }
    }
    for (final child in children) {
      final childResult = child['last_result']?.toString() ?? '';
      if (child['status'] != 'completed' || childResult.trim().isEmpty) continue;
      final taskId = child['id']?.toString() ?? '';
      final artifact = _artifact(
        id: 'output_${requestId}_child_$taskId',
        requestId: requestId,
        conversationId: conversationId,
        taskId: taskId,
        kind: 'text',
        title: 'نتيجة الوكيل: ${child['title'] ?? taskId}',
        mimeType: 'text/plain; charset=utf-8',
        content: childResult,
        preview: _preview(childResult, 1600),
        status: 'available',
        verified: true,
        verificationMessage: 'تم استرجاع النص الكامل من سجل الوكيل الفرعي الدائم.',
        metadata: <String, Object?>{
          'source': 'subagent_result',
          'agent_type': child['agent_type'],
          'verification_scope': 'durable_result_presence',
        },
        createdAt: now,
      );
      await _save(artifact);
      artifacts.add(artifact);
    }

    final events = await _store.eventsFor(requestId);
    final fileEvents = <String, Map<String, Object?>>{};
    for (final row in events) {
      final event = row.payload;
      final type = event['type']?.toString() ?? row.type;
      if (!{'file_created', 'file_updated'}.contains(type)) continue;
      final path = (event['file_name'] ?? event['path'] ?? event['output'])?.toString().trim() ?? '';
      if (path.isEmpty || path.startsWith('{')) continue;
      fileEvents[path] = event;
    }

    for (final entry in fileEvents.entries) {
      final path = entry.key;
      final event = entry.value;
      final kind = _kindFor(path);
      final mimeType = _mimeFor(path);
      Map<String, dynamic>? fileMetadata;
      String? inspectError;
      try {
        fileMetadata = await _models.inspectWorkspaceFile(path: path);
      } catch (error) {
        inspectError = error.toString();
      }
      final exists = fileMetadata != null;
      final sizeBytes = (fileMetadata?['size_bytes'] as num?)?.toInt() ?? 0;
      String? content;
      String? readError;
      if (exists && kind == 'code_or_text' && sizeBytes <= 1024 * 1024) {
        try {
          final read = await _models.readFile(path: path);
          content = (read['content'] ?? read['text'] ?? read['output'])?.toString();
        } catch (error) {
          readError = error.toString();
        }
      }
      final contentReadable = kind == 'code_or_text'
          ? (content != null && content.isNotEmpty) || sizeBytes > 1024 * 1024
          : exists;
      final verified = exists && contentReadable;
      final verificationMessage = !exists
          ? 'تعذر التحقق من وجود الملف داخل مساحة العمل: ${inspectError ?? 'الملف غير موجود.'}'
          : !contentReadable
              ? 'الملف موجود، لكن تعذرت قراءة محتواه للتحقق: ${readError ?? 'محتوى فارغ أو غير متاح.'}'
              : kind == 'image'
                  ? 'تم التحقق من وجود الصورة وحجمها؛ يمكن طلب معاينتها عند الحاجة.'
                  : kind == 'binary_document'
                      ? 'تم التحقق من وجود المستند وحجمه؛ معاينته تعتمد على عارض المستندات.'
                      : kind == 'code_or_text' && sizeBytes > 1024 * 1024
                          ? 'تم التحقق من وجود الملف وحجمه؛ تجاوز حد القراءة النصية للمعاينة.'
                          : kind == 'code_or_text'
                              ? 'تم العثور على الملف وقراءة محتواه بنجاح.'
                              : 'تم التحقق من وجود الملف داخل مساحة العمل.';
      final artifact = _artifact(
        id: 'output_${requestId}_file_${base64Url.encode(utf8.encode(path)).replaceAll('=', '')}',
        requestId: requestId,
        conversationId: conversationId,
        taskId: event['task_id']?.toString(),
        kind: kind,
        title: path.split('/').last,
        mimeType: mimeType,
        filePath: path,
        content: content,
        preview: content == null ? null : _preview(content, 1800),
        status: verified ? 'available' : 'partial',
        verified: verified,
        verificationMessage: verificationMessage,
        metadata: <String, Object?>{
          'source_event': event['type'],
          'tool_name': event['tool_name'],
          'extension': _extension(path),
          'workspace_inspection': fileMetadata != null,
          'size_bytes': sizeBytes,
          'verification_scope': 'workspace_presence_and_readability',
        },
        createdAt: now,
      );
      await _save(artifact);
      artifacts.add(artifact);
    }

    final verifiedCount = artifacts.where((item) => item['verified'] == true).length;
    final missingCount = artifacts.length - verifiedCount;
    final hasFinalText = finalText.trim().isNotEmpty;
    final verified = hasFinalText && missingCount == 0 && childFailures == 0 && emptyChildResults == 0 &&
        dependencyFailures == 0 && requestStatus == 'completed';
    final summary = 'حُفظ ${artifacts.length} مخرجاً؛ تحقق $verifiedCount، وغير المتحقق $missingCount؛ الوكلاء غير المكتملين: $childFailures؛ نتائجهم الفارغة: $emptyChildResults؛ تبعيات غير مكتملة: $dependencyFailures.';
    _emit(requestId, verified ? 'output_collection_completed' : 'output_collection_partial',
        verified ? 'اكتملت منظومة المخرجات والتحقق منها' : 'المخرجات جزئية وتحتاج مراجعة',
        verified ? 'completed' : 'interrupted',
        details: '$summary${failure == null ? '' : ' سبب الفشل: $failure'}',
        extra: <String, Object?>{
          'artifact_count': artifacts.length,
          'verified_count': verifiedCount,
          'unverified_count': missingCount,
          'incomplete_child_count': childFailures,
          'empty_child_result_count': emptyChildResults,
          'dependency_failure_count': dependencyFailures,
          'artifact_ids': artifacts.map((item) => item['id']).toList(),
        });
    return OutputCollectionResult(
      artifacts: artifacts,
      verified: verified,
      summary: summary,
    );
  }

  Map<String, dynamic> _artifact({
    required String id,
    required String requestId,
    required String conversationId,
    String? taskId,
    required String kind,
    required String title,
    required String mimeType,
    String? filePath,
    String? content,
    String? preview,
    required String status,
    required bool verified,
    required String verificationMessage,
    required Map<String, Object?> metadata,
    required String createdAt,
  }) => <String, dynamic>{
        'id': id,
        'request_id': requestId,
        'conversation_id': conversationId,
        if (taskId != null && taskId.isNotEmpty) 'task_id': taskId,
        'kind': kind,
        'title': title,
        'mime_type': mimeType,
        if (filePath != null) 'file_path': filePath,
        if (content != null) 'content': content,
        if (preview != null) 'preview': preview,
        'status': status,
        'verified': verified,
        'verification_message': verificationMessage,
        'metadata': metadata,
        'created_at': createdAt,
      };

  Future<void> _save(Map<String, dynamic> artifact) async {
    await _store.saveOutputArtifact(artifact);
    _emit(
      artifact['request_id'].toString(),
      'output_artifact_available',
      artifact['title'].toString(),
      artifact['verified'] == true ? 'completed' : 'interrupted',
      details: artifact['verification_message']?.toString(),
      extra: <String, Object?>{
        'artifact_id': artifact['id'],
        'kind': artifact['kind'],
        'mime_type': artifact['mime_type'],
        'file_path': artifact['file_path'],
        'preview': artifact['preview'],
        'verified': artifact['verified'],
        'status': artifact['status'],
        'task_id': artifact['task_id'],
      },
    );
  }

  void _emit(String requestId, String type, String title, String status,
      {String? details, Map<String, Object?>? extra}) {
    AgentEventBus.instance.publish(<String, Object?>{
      'id': 'output_${requestId}_${type}_${DateTime.now().microsecondsSinceEpoch}',
      'request_id': requestId,
      'type': type,
      'title': title,
      'status': status,
      'details': details,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      ...?extra,
    }..removeWhere((key, value) => value == null));
  }

  String _extension(String path) =>
      path.contains('.') ? path.split('.').last.toLowerCase() : '';

  String _kindFor(String path) {
    final ext = _extension(path);
    if ({'png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp'}.contains(ext)) return 'image';
    if ({'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'odt', 'ods', 'odp'}.contains(ext)) return 'binary_document';
    if ({'dart', 'py', 'js', 'ts', 'tsx', 'jsx', 'html', 'css', 'json', 'xml', 'yaml', 'yml', 'sql', 'sh', 'kt', 'java', 'swift', 'go', 'rs', 'c', 'cpp', 'h', 'md', 'txt', 'csv', 'toml', 'gradle', 'svg'}.contains(ext)) return 'code_or_text';
    return 'file';
  }

  String _mimeFor(String path) {
    const types = <String, String>{
      'png': 'image/png', 'jpg': 'image/jpeg', 'jpeg': 'image/jpeg',
      'webp': 'image/webp', 'gif': 'image/gif', 'svg': 'image/svg+xml',
      'pdf': 'application/pdf', 'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      'json': 'application/json', 'html': 'text/html', 'md': 'text/markdown',
      'csv': 'text/csv', 'dart': 'text/x-dart', 'py': 'text/x-python',
      'js': 'text/javascript', 'ts': 'text/typescript', 'css': 'text/css',
    };
    return types[_extension(path)] ?? 'application/octet-stream';
  }

  String _preview(String value, int max) =>
      value.length <= max ? value : '${value.substring(0, max)}…';
}
