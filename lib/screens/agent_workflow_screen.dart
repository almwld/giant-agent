import 'package:flutter/material.dart';

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
      case 'pending':
        return const Color(0xFF38BDF8);
      case 'failed':
      case 'error':
        return const Color(0xFFF87171);
      case 'interrupted':
      case 'cancelled':
        return const Color(0xFFFBBF24);
      default:
        return const Color(0xFF34D399);
    }
  }

  String _statusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'running':
      case 'pending':
        return 'قيد التنفيذ';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101820),
      appBar: AppBar(
        backgroundColor: const Color(0xFF17212B),
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
          final ordered = rows.reversed.toList(growable: false);
          return ListView(
            padding: const EdgeInsets.all(14),
            children: [
              _summaryCard(rows),
              if (finalOutput.value.trim().isNotEmpty) _finalOutputCard(finalOutput.value),
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
              return Container(
                margin: const EdgeInsets.only(bottom: 9),
                decoration: BoxDecoration(
                  color: const Color(0xFF1B2835),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: color.withOpacity(.28)),
                ),
                child: ExpansionTile(
                  iconColor: Colors.white70,
                  collapsedIconColor: Colors.white54,
                  title: Text(title,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600)),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Row(
                      children: [
                        if (tool.isNotEmpty) ...[
                          Flexible(
                            child: Text(tool,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Colors.white54, fontSize: 11)),
                          ),
                          const SizedBox(width: 9),
                        ],
                        Text(_statusLabel(status),
                            style: TextStyle(color: color, fontSize: 11)),
                      ],
                    ),
                  ),
                  children: [
                    if (event['content'] != null)
                      _detailBlock('المحتوى', event['content'].toString()),
                    if (details.isNotEmpty) _detailBlock('التفاصيل', details),
                    if (event['file_name'] != null)
                      _detailBlock('الملف', event['file_name'].toString()),
                    if (event['command'] != null)
                      _detailBlock('الأمر', event['command'].toString()),
                    if (event['output'] != null && details != event['output'].toString())
                      _detailBlock('المخرجات', event['output'].toString()),
                    ...event.entries.where((entry) => !{'id','title','status','tool_name','type','details','content','file_name','command','output','subtitle'}.contains(entry.key)).map((entry) => _detailBlock(entry.key, entry.value is String ? entry.value as String : entry.value.toString())),
                  ],
                ),
              );
              }),
            ],
          );
        },
      ),
    );
  }


  Widget _summaryCard(List<Map<String, dynamic>> rows) {
    final completed = rows.where((e) => {'completed','success'}.contains((e['status'] ?? '').toString().toLowerCase())).length;
    final failed = rows.where((e) => {'failed','error'}.contains((e['status'] ?? '').toString().toLowerCase())).length;
    final active = rows.where((e) => {'running','pending'}.contains((e['status'] ?? '').toString().toLowerCase())).length;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFF1B2835), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFF38BDF8).withOpacity(.25))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('ملخص الجلسة', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 10),
        Wrap(spacing: 16, runSpacing: 8, children: [
          _metric('إجمالي الأحداث', rows.length.toString(), Colors.white70),
          _metric('مكتمل', completed.toString(), const Color(0xFF34D399)),
          _metric('قيد التنفيذ', active.toString(), const Color(0xFF38BDF8)),
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
    decoration: BoxDecoration(color: const Color(0xFF12352F), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFF34D399).withOpacity(.45))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Row(children: [Icon(Icons.task_alt, color: Color(0xFF34D399), size: 19), SizedBox(width: 8), Text('المخرج النهائي للجلسة', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700))]),
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
                    color: Color(0xFF5EEAD4),
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 5),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF101820),
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
