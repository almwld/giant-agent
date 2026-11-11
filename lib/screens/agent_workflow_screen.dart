import 'dart:convert';
import 'package:flutter/material.dart';
import '../widgets/agent_activity_indicators.dart';
import '../services/agent_service.dart';
import '../theme/giant_palette.dart';

/// Execution history view backed by the same event list used by the chat
/// timeline. Events are published by ChatScreen as the native agent streams.
class AgentWorkflowScreen extends StatelessWidget {
  const AgentWorkflowScreen({super.key});

  static final ValueNotifier<List<Map<String, dynamic>>> events =
      ValueNotifier<List<Map<String, dynamic>>>(const []);
  static final ValueNotifier<String> finalOutput = ValueNotifier<String>('');

  static void publish(List<Map<String, dynamic>> value, {String? finalOutputText}) {
    AgentWorkflowScreen.finalOutput.value = finalOutputText ?? '';
    events.value = value
        .map((event) => Map<String, dynamic>.from(event))
        .toList(growable: false);
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'running':
        return GiantPalette.primaryLight;
      case 'pending':
        return GiantPalette.muted;
      case 'failed':
      case 'error':
        return const Color(0xFFF87171);
      case 'interrupted':
      case 'cancelled':
        return const Color(0xFFFBBF24);
      default:
        return GiantPalette.success;
    }
  }

  String _statusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'running':
        return 'قيد التنفيذ';
      case 'pending':
        return 'بانتظار التنفيذ';
      case 'failed':
      case 'error':
        return 'فشل';
      case 'interrupted':
      case 'cancelled':
        return 'متوقف';
      case 'completed':
      case 'success':
        return 'مكتمل';
      default:
        return status.isEmpty ? 'حدث' : status;
    }
  }

  String _agentRoleLabel(String role) {
    switch (role) {
      case 'explore': return 'استكشاف';
      case 'plan': return 'تخطيط';
      case 'coder': return 'تنفيذ';
      case 'reviewer': return 'مراجعة';
      default: return role;
    }
  }

  IconData _eventIcon(String type, String tool, String title) {
    final value = '$type $tool $title'.toLowerCase();
    if (value.contains('python') || value.contains('terminal') ||
        value.contains('tool') || value.contains('أداة') ||
        value.contains('طرفية')) {
      return Icons.terminal_rounded;
    }
    if (value.contains('file') || value.contains('ملف')) {
      return Icons.description_outlined;
    }
    if (value.contains('think') || value.contains('inference') ||
        value.contains('استدلال') || value.contains('تحليل') ||
        value.contains('خطة') || value.contains('plan')) {
      return Icons.psychology_alt_rounded;
    }
    if (value.contains('fail') || value.contains('error') ||
        value.contains('خطأ') || value.contains('تعذر')) {
      return Icons.error_outline_rounded;
    }
    if (value.contains('complete') || value.contains('finished') ||
        value.contains('مكتمل') || value.contains('اكتمل')) {
      return Icons.check_circle_outline_rounded;
    }
    return Icons.account_tree_outlined;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GiantPalette.background,
      appBar: AppBar(
        backgroundColor: GiantPalette.surface,
        foregroundColor: Colors.white,
        title: const Text('مساحة عمل الجلسة'),
      ),
      body: ValueListenableBuilder<List<Map<String, dynamic>>>(
        valueListenable: events,
        builder: (context, rows, _) {
          if (rows.isEmpty && finalOutput.value.isEmpty) {
            return const Center(
              child: Text(
                'لا توجد خطوات تنفيذ في هذه المحادثة بعد.',
                style: TextStyle(color: Colors.white60),
              ),
            );
          }
          final ordered = rows.toList(growable: false);
          final latestSubagentEvent = <String, String>{};
          for (final event in ordered) {
            final taskId = event['task_id']?.toString() ?? '';
            final eventId = event['id']?.toString() ?? '';
            if (taskId.isNotEmpty && eventId.isNotEmpty) {
              latestSubagentEvent[taskId] = eventId;
            }
          }
          return ListView(
            padding: const EdgeInsets.all(14),
            children: [
              _summaryCard(rows),
              if (ordered.any((event) => event['type'] == 'output_artifact_available'))
                _outputArtifactsCard(ordered.where((event) =>
                    event['type'] == 'output_artifact_available').toList(growable: false), context),
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 16, 4, 9),
                child: Text('التسلسل الكامل لتنفيذ الوكيل', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
              ),
              ...ordered.map((event) {
              final status = event['status']?.toString() ?? '';
              final color = _statusColor(status);
              final title = event['title']?.toString() ??
                  event['tool_name']?.toString() ??
                  event['type']?.toString() ??
                  'خطوة تنفيذ';
              final details = event['details']?.toString() ??
                  event['output']?.toString() ??
                  event['subtitle']?.toString() ??
                  '';
              final tool = event['tool_name']?.toString() ?? '';
              final eventType = event['type']?.toString() ?? '';
              final agentType = event['agent_type']?.toString() ?? '';
              final icon = _eventIcon(eventType, tool, title);
              return Container(
                margin: const EdgeInsets.only(bottom: 9),
                decoration: BoxDecoration(
                  color: GiantPalette.surface,
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: color.withOpacity(.28)),
                ),
                child: ExpansionTile(
                  iconColor: Colors.white70,
                  collapsedIconColor: Colors.white54,
                  leading: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: color.withOpacity(.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: color, size: 18),
                  ),
                  title: status.toLowerCase() == 'running'
                      ? AgentShimmerText(
                          title,
                          maxLines: 2,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                        )
                      : Text(title,
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.w600)),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Row(
                      children: [
                        if (agentType.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: GiantPalette.primaryLight.withOpacity(.12),
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: Text(_agentRoleLabel(agentType),
                                style: const TextStyle(color: GiantPalette.primaryLight, fontSize: 10)),
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (tool.isNotEmpty) ...[
                          Flexible(
                            child: Text(tool,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Colors.white54, fontSize: 11)),
                          ),
                          const SizedBox(width: 9),
                        ],
                        if (status.toLowerCase() == 'running') ...[
                          const AgentPulseDot(size: 8),
                          const SizedBox(width: 7),
                        ] else if (status.toLowerCase() == 'pending') ...[
                          const Icon(Icons.schedule_rounded, color: GiantPalette.muted, size: 13),
                          const SizedBox(width: 7),
                        ],
                        Text(_statusLabel(status),
                            style: TextStyle(color: color, fontSize: 11)),
                      ],
                    ),
                  ),
                  children: [
                    if (event['agent_type'] != null)
                      _detailBlock('نوع الوكيل الفرعي', _agentRoleLabel(event['agent_type'].toString())),
                    if (event['task_id'] != null)
                      _detailBlock('معرّف الوكيل الفرعي', event['task_id'].toString()),
                    if (event['content'] != null)
                      _detailBlock('المحتوى', event['content'].toString()),
                    if (details.isNotEmpty) _detailBlock('التفاصيل', details),
                    if (event['file_name'] != null)
                      _detailBlock('الملف', event['file_name'].toString()),
                    if (event['command'] != null)
                      _detailBlock('الأمر', event['command'].toString()),
                    if (event['task_id'] != null &&
                        latestSubagentEvent[event['task_id'].toString()] == event['id']?.toString() &&
                        {'running', 'pending'}.contains(status.toLowerCase()))
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: TextButton.icon(
                            onPressed: () async {
                              final stopped = await AgentService.instance
                                  .cancelSubagent(event['task_id'].toString());
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(stopped
                                      ? 'تم إرسال طلب إيقاف الوكيل الفرعي.'
                                      : 'لم يعد هذا الوكيل قيد التنفيذ.'),
                                ),
                              );
                            },
                            icon: const Icon(Icons.stop_circle_outlined, size: 17),
                            label: const Text('إيقاف هذا الوكيل'),
                          ),
                        ),
                      ),
                    if (event['task_id'] != null &&
                        latestSubagentEvent[event['task_id'].toString()] == event['id']?.toString() &&
                        {'interrupted', 'failed'}.contains(status.toLowerCase()))
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final disposition = await showDialog<String>(
                                context: context,
                                builder: (dialogContext) => AlertDialog(
                                  backgroundColor: GiantPalette.surface,
                                  title: const Text('استئناف الوكيل الفرعي', style: TextStyle(color: Colors.white)),
                                  content: const Text(
                                    'قد تكون بعض العمليات قد نُفذت قبل الانقطاع. افحص آثارها أولاً، ثم اختر كيف تريد المتابعة.',
                                    style: TextStyle(color: Colors.white70),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(dialogContext, 'verified_no_side_effects'),
                                      child: const Text('تحققت: لا توجد آثار جانبية'),
                                    ),
                                    FilledButton(
                                      onPressed: () => Navigator.pop(dialogContext, 'user_authorized_retry'),
                                      child: const Text('أوافق على الاستئناف بعد مراجعة الحالة'),
                                    ),
                                  ],
                                ),
                              );
                              if (disposition == null || !context.mounted) return;
                              try {
                                await AgentService.instance.resumeSubagent(
                                  event['task_id'].toString(),
                                  sideEffectDisposition: disposition,
                                );
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('اكتمل استئناف الوكيل الفرعي وحُفظت نتيجته.')),
                                );
                              } catch (error) {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('تعذر استئناف الوكيل: $error')),
                                );
                              }
                            },
                            icon: const Icon(Icons.restart_alt_rounded, size: 17),
                            label: const Text('مراجعة الحالة واستئناف الوكيل'),
                          ),
                        ),
                      ),
                    if (event['task_id'] != null &&
                        latestSubagentEvent[event['task_id'].toString()] == event['id']?.toString() &&
                        {'completed', 'failed', 'interrupted', 'cancelled', 'skipped'}
                            .contains(status.toLowerCase()) &&
                        event['type'] != 'subagent_dismissed')
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              try {
                                final dismissed = await AgentService.instance
                                    .dismissSubagent(event['task_id'].toString());
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(dismissed
                                        ? 'تم إخفاء الوكيل مع الاحتفاظ بسجل عملياته.'
                                        : 'لا يمكن إخفاء وكيل ما زال قيد التنفيذ.'),
                                  ),
                                );
                              } catch (error) {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('تعذر إخفاء الوكيل: $error')),
                                );
                              }
                            },
                            icon: const Icon(Icons.archive_outlined, size: 17),
                            label: const Text('إخفاء الوكيل مع حفظ السجل'),
                          ),
                        ),
                      ),
                    if (event['output'] != null && details != event['output'].toString())
                      _detailBlock('المخرجات', event['output'].toString()),
                    ...event.entries.where((entry) => !{
                      'id','title','status','tool_name','type','details','content',
                      'file_name','command','output','subtitle','request_id','agent_type','task_id',
                      'session_id','timestamp'
                    }.contains(entry.key)).map((entry) => _detailBlock(
                      entry.key,
                      entry.value is String ? entry.value as String : entry.value.toString(),
                    )),
                    if (event['request_id'] != null ||
                        event['session_id'] != null ||
                        event['timestamp'] != null)
                      ExpansionTile(
                        title: const Text(
                          'تفاصيل متقدمة',
                          style: TextStyle(color: Colors.white54, fontSize: 11),
                        ),
                        children: [
                          if (event['request_id'] != null)
                            _detailBlock('معرّف الطلب', event['request_id'].toString()),
                          if (event['session_id'] != null)
                            _detailBlock('معرّف الجلسة', event['session_id'].toString()),
                          if (event['timestamp'] != null)
                            _detailBlock('الوقت', event['timestamp'].toString()),
                        ],
                      ),
                  ],
                ),
              );
              }),
              if (finalOutput.value.trim().isNotEmpty) _finalOutputCard(finalOutput.value),
            ],
          );
        },
      ),
    );
  }


  Widget _outputArtifactsCard(
    List<Map<String, dynamic>> rows,
    BuildContext context,
  ) {
    final latest = <String, Map<String, dynamic>>{};
    for (final row in rows) {
      final id = row['artifact_id']?.toString() ?? '';
      if (id.isNotEmpty) latest[id] = row;
    }
    final artifacts = latest.values.toList(growable: false);
    final verified = artifacts.where((item) => item['verified'] == true).length;
    final exportPaths = artifacts
        .map((item) => item['file_path']?.toString() ?? '')
        .where((path) => path.isNotEmpty)
        .toSet()
        .toList(growable: false);
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: GiantPalette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: GiantPalette.primaryLight.withOpacity(.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.inventory_2_outlined, color: GiantPalette.primaryLight, size: 19),
          const SizedBox(width: 8),
          const Expanded(child: Text('مخرجات المهمة', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
          Text('$verified/${artifacts.length} تم التحقق', style: const TextStyle(color: GiantPalette.success, fontSize: 11)),
        ]),
        const SizedBox(height: 10),
        ...artifacts.map((artifact) {
          final kind = artifact['kind']?.toString() ?? 'file';
          final path = artifact['file_path']?.toString();
          final preview = artifact['preview']?.toString() ?? '';
          final isVerified = artifact['verified'] == true;
          final icon = kind == 'image' ? Icons.image_outlined
              : kind == 'binary_document' ? Icons.picture_as_pdf_outlined
              : kind == 'code_or_text' ? Icons.code_rounded
              : Icons.description_outlined;
          return Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: GiantPalette.background,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: (isVerified ? GiantPalette.success : const Color(0xFFFBBF24)).withOpacity(.25)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(icon, color: isVerified ? GiantPalette.success : const Color(0xFFFBBF24), size: 17),
                const SizedBox(width: 8),
                Expanded(child: Text(artifact['title']?.toString() ?? 'مخرج', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12))),
                Icon(isVerified ? Icons.verified_rounded : Icons.warning_amber_rounded,
                    color: isVerified ? GiantPalette.success : const Color(0xFFFBBF24), size: 16),
              ]),
              if (path != null && path.isNotEmpty) ...[
                const SizedBox(height: 5),
                SelectableText(path, style: const TextStyle(color: Colors.white54, fontSize: 10, fontFamily: 'monospace')),
              ],
              if (preview.isNotEmpty) ...[
                const SizedBox(height: 7),
                Text(preview, maxLines: 7, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 11, height: 1.45)),
              ],
              if ((kind == 'binary_document' || kind == 'file') && path != null)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: () async {
                      try {
                        await AgentService.instance.openWorkspaceFile(path);
                      } catch (error) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('تعذر فتح الملف: $error')),
                        );
                      }
                    },
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    label: const Text('فتح الملف'),
                  ),
                ),
              if (kind == 'image' && path != null)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: () => _showImagePreview(context, path),
                    icon: const Icon(Icons.visibility_outlined, size: 16),
                    label: const Text('معاينة الصورة'),
                  ),
                ),
              if (kind != 'image' && path != null)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: () async {
                      try {
                        await AgentService.instance.openWorkspaceFile(path);
                      } catch (error) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('تعذر فتح المستند: $error')),
                        );
                      }
                    },
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    label: const Text('فتح المستند'),
                  ),
                ),
              if (!isVerified && artifact['details'] != null)
                Padding(padding: const EdgeInsets.only(top: 5), child: Text(artifact['details'].toString(), style: const TextStyle(color: Color(0xFFFBBF24), fontSize: 10))),
            ]),
          );
        }),
        const SizedBox(height: 10),
        if (exportPaths.isNotEmpty)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: OutlinedButton.icon(
              onPressed: () async {
                try {
                  await AgentService.instance.shareWorkspace(exportPaths);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('تم فتح نافذة مشاركة ملفات المهمة.'),
                  ));
                } catch (error) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('تعذر تصدير المخرجات: $error')),
                  );
                }
              },
              icon: const Icon(Icons.download_rounded, size: 17),
              label: const Text('مشاركة / حفظ ملفات المهمة المحددة'),
            ),
          ),
      ]),
    );
  }

  Future<void> _showImagePreview(BuildContext context, String path) async {
    try {
      final result = await AgentService.instance.readImagePreview(path);
      final bytes = base64Decode(result['base64'].toString());
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => Dialog(
          backgroundColor: GiantPalette.surface,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(path, style: const TextStyle(color: Colors.white70, fontSize: 11)),
              ),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 520, maxWidth: 520),
                child: Image.memory(bytes, fit: BoxFit.contain),
              ),
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إغلاق')),
            ]),
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذرت معاينة الصورة: $error')),
      );
    }
  }

  Widget _summaryCard(List<Map<String, dynamic>> rows) {
    final completed = rows.where((e) => {'completed','success'}.contains((e['status'] ?? '').toString().toLowerCase())).length;
    final failed = rows.where((e) => {'failed','error'}.contains((e['status'] ?? '').toString().toLowerCase())).length;
    final active = rows.where((e) => (e['status'] ?? '').toString().toLowerCase() == 'running').length;
    final pending = rows.where((e) => (e['status'] ?? '').toString().toLowerCase() == 'pending').length;
    final subagents = rows.map((e) => e['task_id']?.toString() ?? '').where((id) => id.isNotEmpty).toSet().length;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: GiantPalette.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: GiantPalette.primaryLight.withOpacity(.25))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('ملخص الجلسة', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 10),
        Wrap(spacing: 16, runSpacing: 8, children: [
          _metric('إجمالي الأحداث', rows.length.toString(), Colors.white70),
          _metric('الوكلاء الفرعيون', subagents.toString(), GiantPalette.primaryLight),
          _metric('مكتمل', completed.toString(), GiantPalette.success),
          _metric('قيد التنفيذ', active.toString(), GiantPalette.primaryLight),
          _metric('بانتظار التنفيذ', pending.toString(), GiantPalette.muted),
          _metric('أخطاء', failed.toString(), const Color(0xFFF87171)),
        ]),
      ]),
    );
  }

  Widget _metric(String label, String value, Color color) => Row(mainAxisSize: MainAxisSize.min, children: [
    Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
    const SizedBox(width: 5),
    Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
  ]);

  Widget _finalOutputCard(String output) => Container(
    margin: const EdgeInsets.only(top: 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: GiantPalette.successSurface, borderRadius: BorderRadius.circular(14), border: Border.all(color: GiantPalette.success.withOpacity(.45))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Row(children: [Icon(Icons.task_alt, color: GiantPalette.success, size: 19), SizedBox(width: 8), Text('المخرج النهائي للجلسة', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700))]),
      const SizedBox(height: 10),
      SelectableText(output, style: const TextStyle(color: Colors.white, height: 1.55, fontSize: 13)),
    ]),
  );

  Widget _detailBlock(String label, String value) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    color: GiantPalette.primaryLight,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 5),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: GiantPalette.background,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(value,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontFamily: 'monospace')),
            ),
          ],
        ),
      );
}
