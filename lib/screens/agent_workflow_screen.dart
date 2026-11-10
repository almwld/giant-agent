import 'package:flutter/material.dart';
import '../widgets/agent_activity_indicators.dart';
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
          return ListView(
            padding: const EdgeInsets.all(14),
            children: [
              _summaryCard(rows),
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
