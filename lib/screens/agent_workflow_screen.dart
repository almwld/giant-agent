import 'package:flutter/material.dart';

/// Execution history view backed by the same event list used by the chat
/// timeline. Events are published by ChatScreen as the native agent streams.
class AgentWorkflowScreen extends StatelessWidget {
  const AgentWorkflowScreen({super.key});

  static final ValueNotifier<List<Map<String, dynamic>>> events =
      ValueNotifier<List<Map<String, dynamic>>>(const []);

  static void publish(List<Map<String, dynamic>> value) {
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
        title: const Text('تنفيذ الوكيل'),
      ),
      body: ValueListenableBuilder<List<Map<String, dynamic>>>(
        valueListenable: events,
        builder: (context, rows, _) {
          if (rows.isEmpty) {
            return const Center(
              child: Text(
                'لا توجد خطوات تنفيذ في هذه المحادثة بعد.',
                style: TextStyle(color: Colors.white60),
              ),
            );
          }
          final ordered = rows.reversed.toList(growable: false);
          return ListView.separated(
            padding: const EdgeInsets.all(14),
            itemCount: ordered.length,
            separatorBuilder: (_, __) => const SizedBox(height: 9),
            itemBuilder: (context, index) {
              final event = ordered[index];
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
                    if (event['output'] != null &&
                        details != event['output'].toString())
                      _detailBlock('المخرجات', event['output'].toString()),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

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
