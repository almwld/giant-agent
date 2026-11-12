import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/kernel/agent_kernel_store.dart';
import '../domain/kernel/agent_observability.dart';

/// Local-only Gain Agents timeline and diagnostics for one conversation.
class AgentObservabilityScreen extends StatefulWidget {
  const AgentObservabilityScreen({
    super.key,
    required this.conversationId,
  });

  final String conversationId;

  @override
  State<AgentObservabilityScreen> createState() =>
      _AgentObservabilityScreenState();
}

class _AgentObservabilityScreenState extends State<AgentObservabilityScreen> {
  final AgentKernelStore _store = AgentKernelStore();
  AgentObservabilitySummary? _summary;
  final List<AgentObservabilityEvent> _events = <AgentObservabilityEvent>[];
  String? _statusFilter;
  int? _cursor;
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    unawaited(_store.close());
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _cursor = null;
      _events.clear();
    });
    try {
      final summary = await _store.observabilitySummaryForConversation(
        widget.conversationId,
      );
      final page = await _store.observabilityEventsForConversation(
        widget.conversationId,
        limit: 40,
        status: _statusFilter,
      );
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _events.addAll(page.events);
        _cursor = page.nextCursor;
        _hasMore = page.hasMore;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _cursor == null) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _store.observabilityEventsForConversation(
        widget.conversationId,
        limit: 40,
        beforeRowId: _cursor,
        status: _statusFilter,
      );
      if (!mounted) return;
      setState(() {
        _events.addAll(page.events);
        _cursor = page.nextCursor;
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loadingMore = false;
      });
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'completed':
        return const Color(0xFF34D399);
      case 'failed':
      case 'error':
        return const Color(0xFFF87171);
      case 'interrupted':
      case 'cancelled':
        return const Color(0xFFFBBF24);
      case 'running':
        return const Color(0xFF60A5FA);
      default:
        return const Color(0xFF94A3B8);
    }
  }

  Widget _metric(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFF181D29),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF293244)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF5EEAD4)),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: Color(0xFF94A3B8), fontSize: 11)),
                const SizedBox(height: 4),
                Text(value,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _eventTitle(AgentObservabilityEvent event) {
    final title = event.payload['title']?.toString().trim() ?? '';
    return title.isEmpty ? event.type.replaceAll('_', ' ') : title;
  }

  String _eventSubtitle(AgentObservabilityEvent event) {
    final taskId = event.taskId;
    final toolId = event.payload['tool_call_id']?.toString();
    final parts = <String>[
      event.type,
      if (taskId != null && taskId.isNotEmpty) 'task: $taskId',
      if (toolId != null && toolId.isNotEmpty) 'tool: $toolId',
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    return Scaffold(
      backgroundColor: const Color(0xFF10131B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF10131B),
        foregroundColor: Colors.white,
        title: const Text('Gain Agents · المراقبة'),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && summary == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!,
                        style: const TextStyle(color: Colors.redAccent)),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                    children: [
                      if (summary != null) ...[
                        const Text('ملخص الجلسة',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 12),
                        GridView.count(
                          crossAxisCount: 2,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: 2.25,
                          children: [
                            _metric('الطلبات', '${summary.requestCount}',
                                Icons.account_tree_outlined),
                            _metric('قيد التنفيذ', '${summary.activeRequests}',
                                Icons.pending_actions_rounded),
                            _metric('نجاح الأدوات',
                                '${(summary.toolSuccessRate * 100).toStringAsFixed(0)}%',
                                Icons.check_circle_outline_rounded),
                            _metric('إخفاقات الأدوات',
                                '${summary.toolFailureCount}',
                                Icons.warning_amber_rounded),
                            _metric('متوسط زمن الأداة',
                                summary.averageToolLatencyMs == null
                                    ? '—'
                                    : '${summary.averageToolLatencyMs!.toStringAsFixed(0)} ms',
                                Icons.speed_rounded),
                            _metric('الأحداث', '${summary.eventCount}',
                                Icons.timeline_rounded),
                          ],
                        ),
                      ],
                      const SizedBox(height: 22),
                      Row(
                        children: [
                          const Expanded(
                            child: Text('سجل التنفيذ',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700)),
                          ),
                          DropdownButton<String?>(
                            value: _statusFilter,
                            dropdownColor: const Color(0xFF181D29),
                            underline: const SizedBox.shrink(),
                            style: const TextStyle(
                                color: Color(0xFFCBD5E1), fontSize: 12),
                            items: const [
                              DropdownMenuItem<String?>(
                                  value: null, child: Text('كل الحالات')),
                              DropdownMenuItem<String?>(
                                  value: 'running', child: Text('قيد التنفيذ')),
                              DropdownMenuItem<String?>(
                                  value: 'completed', child: Text('مكتمل')),
                              DropdownMenuItem<String?>(
                                  value: 'failed', child: Text('فشل')),
                              DropdownMenuItem<String?>(
                                  value: 'interrupted', child: Text('متوقف')),
                            ],
                            onChanged: (value) {
                              setState(() => _statusFilter = value);
                              _refresh();
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (_events.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 36),
                          child: Center(
                            child: Text('لا توجد أحداث مسجلة لهذه الجلسة.',
                                style: TextStyle(color: Color(0xFF94A3B8))),
                          ),
                        ),
                      ..._events.map((event) {
                        final color = _statusColor(event.status);
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(13),
                          decoration: BoxDecoration(
                            color: const Color(0xFF181D29),
                            borderRadius: BorderRadius.circular(13),
                            border: Border.all(color: const Color(0xFF293244)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                margin: const EdgeInsets.only(top: 5),
                                decoration: BoxDecoration(
                                    color: color, shape: BoxShape.circle),
                              ),
                              const SizedBox(width: 11),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(_eventTitle(event),
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13)),
                                    const SizedBox(height: 4),
                                    Text(_eventSubtitle(event),
                                        style: const TextStyle(
                                            color: Color(0xFF94A3B8),
                                            fontSize: 10)),
                                    const SizedBox(height: 5),
                                    Text(
                                      '${event.createdAt.toLocal()}  ·  ${event.status}',
                                      style: TextStyle(
                                          color: color, fontSize: 10),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                      if (_hasMore)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: OutlinedButton(
                            onPressed: _loadingMore ? null : _loadMore,
                            child: _loadingMore
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : const Text('تحميل أحداث أقدم'),
                          ),
                        ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(_error!,
                              style: const TextStyle(
                                  color: Colors.redAccent, fontSize: 11)),
                        ),
                      const SizedBox(height: 8),
                      const Text(
                        'تُحفظ هذه القياسات محلياً. لا يتم إرسال بيانات الجلسة إلى خدمة مراقبة خارجية.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 10,
                            height: 1.4),
                      ),
                    ],
                  ),
                ),
    );
  }
}
