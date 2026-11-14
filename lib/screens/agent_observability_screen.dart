import 'dart:async';

import 'package:flutter/material.dart';

import '../services/agent_service.dart';
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
  AgentObservabilitySummary? _summary;
  final List<AgentObservabilityEvent> _events = <AgentObservabilityEvent>[];
  String? _statusFilter;
  String? _typeFilter;
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  Timer? _liveRefreshTimer;
  bool _refreshInProgress = false;
  int? _cursor;
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
    _liveRefreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted && !_loadingMore) _refresh(silent: true);
    });
  }

  @override
  void dispose() {
    _liveRefreshTimer?.cancel();
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    if (mounted) setState(() {});
    _searchDebounce = Timer(const Duration(milliseconds: 300), _refresh);
  }

  Future<void> _refresh({bool silent = false}) async {
    if (!mounted || _refreshInProgress) return;
    _refreshInProgress = true;
    if (!silent) {
      setState(() {
        _loading = _events.isEmpty;
        _error = null;
        if (_events.isEmpty) {
          _cursor = null;
          _hasMore = false;
        }
      });
    }
    try {
      final summary = await AgentService.instance.observabilitySummaryForConversation(
        widget.conversationId,
      );
      final page = await AgentService.instance.observabilityEventsForConversation(
        widget.conversationId,
        limit: 40,
        status: _statusFilter,
        type: _typeFilter,
        search: _searchController.text,
      );
      if (!mounted) return;
      setState(() {
        final byId = <String, AgentObservabilityEvent>{};
        for (final event in page.events) {
          byId[event.id] = event;
        }
        if (silent) {
          for (final event in _events) {
            byId.putIfAbsent(event.id, () => event);
          }
        }
        final merged = byId.values.toList()
          ..sort((a, b) => b.rowId.compareTo(a.rowId));
        _events
          ..clear()
          ..addAll(merged);
        _summary = summary;
        _cursor = _events.isEmpty ? page.nextCursor : _events.last.rowId;
        _hasMore = page.hasMore || (silent && _events.length > page.events.length);
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    } finally {
      _refreshInProgress = false;
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _cursor == null) return;
    setState(() => _loadingMore = true);
    try {
      final page = await AgentService.instance.observabilityEventsForConversation(
        widget.conversationId,
        limit: 40,
        beforeRowId: _cursor,
        status: _statusFilter,
        type: _typeFilter,
        search: _searchController.text,
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
    final agentType = event.payload['agent_type']?.toString();
    final parts = <String>[
      event.type,
      if (agentType != null && agentType.isNotEmpty) 'agent: $agentType',
      if (taskId != null && taskId.isNotEmpty) 'task: $taskId',
      if (toolId != null && toolId.isNotEmpty) 'tool: $toolId',
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    final eventTypes = summary?.eventTypes.keys.toList() ?? <String>[];
    eventTypes.sort();
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
                      TextField(
                        controller: _searchController,
                        onChanged: _onSearchChanged,
                        style: const TextStyle(color: Colors.white),
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: 'ابحث في الأحداث والأدوات والمهام...',
                          hintStyle: const TextStyle(
                              color: Color(0xFF64748B), fontSize: 13),
                          prefixIcon: const Icon(Icons.search_rounded,
                              color: Color(0xFF94A3B8)),
                          suffixIcon: _searchController.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'مسح البحث',
                                  onPressed: () {
                                    _searchController.clear();
                                    _onSearchChanged('');
                                    setState(() {});
                                  },
                                  icon: const Icon(Icons.close_rounded,
                                      color: Color(0xFF94A3B8)),
                                ),
                          filled: true,
                          fillColor: const Color(0xFF181D29),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                                color: Color(0xFF293244)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                                color: Color(0xFF293244)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                                color: Color(0xFF5EEAD4)),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                        ),
                      ),
                      const SizedBox(height: 10),
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
                            value: _typeFilter,
                            dropdownColor: const Color(0xFF181D29),
                            underline: const SizedBox.shrink(),
                            style: const TextStyle(
                                color: Color(0xFFCBD5E1), fontSize: 11),
                            hint: const Text('نوع الحدث'),
                            items: <DropdownMenuItem<String?>>[
                              const DropdownMenuItem<String?>(
                                  value: null, child: Text('كل الأنواع')),
                              ...eventTypes.map((type) => DropdownMenuItem<String?>(
                                    value: type,
                                    child: Text(type.replaceAll('_', ' ')),
                                  )),
                            ],
                            onChanged: (value) {
                              setState(() {
                                _typeFilter = value;
                                _events.clear();
                              });
                              _refresh();
                            },
                          ),
                          const SizedBox(width: 6),
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
                              setState(() {
                                _statusFilter = value;
                                _events.clear();
                              });
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
                            child: Text('لا توجد أحداث لهذه الجلسة بعد. أرسل طلباً في المحادثة وسيظهر هنا تسلسل التخطيط والتنفيذ والأدوات والوكلاء الفرعيين.',
                                style: TextStyle(color: Color(0xFF94A3B8))),
                          ),
                        ),
                      ..._events.map((event) {
                        final color = _statusColor(event.status);
                        final explicitPercent = event.payload['progress_percent'];
                        final rawProgress = event.payload['progress'];
                        final progressPercent = explicitPercent is num
                            ? explicitPercent.toDouble().clamp(0.0, 100.0)
                            : rawProgress is num
                                ? (rawProgress <= 1.0
                                    ? rawProgress.toDouble() * 100.0
                                    : rawProgress.toDouble()).clamp(0.0, 100.0)
                                : null;
                        final rawDuration = event.payload['duration_ms'] ??
                            event.payload['latency_ms'];
                        final durationMs = rawDuration is num && rawDuration >= 0
                            ? rawDuration.round()
                            : null;
                        final metadata = <MapEntry<String, String>>[
                          MapEntry('نوع الوكيل', event.payload['agent_type']?.toString() ?? ''),
                          MapEntry('رمز العامل', event.payload['icon']?.toString() ?? ''),
                          MapEntry('وصف العامل', event.payload['motto']?.toString() ?? ''),
                          MapEntry('رقم العامل', (event.payload['worker_index'] ?? event.payload['index'])?.toString() ?? ''),
                          MapEntry('الأداة', event.payload['tool_name']?.toString() ?? ''),
                          MapEntry('معرّف استدعاء الأداة', event.payload['tool_call_id']?.toString() ?? ''),
                          MapEntry('المخرجات', (event.payload['output'] ?? event.payload['result'])?.toString() ?? ''),
                          MapEntry('الخطأ', event.payload['error']?.toString() ?? ''),
                        ].where((item) => item.value.trim().isNotEmpty).toList();
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
                                    if ((event.payload['details']?.toString() ?? '').isNotEmpty) ...[
                                      const SizedBox(height: 5),
                                      Text(
                                        event.payload['details'].toString(),
                                        style: const TextStyle(
                                          color: Color(0xFFCBD5E1),
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                    if (progressPercent != null) ...[
                                      const SizedBox(height: 7),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: LinearProgressIndicator(
                                              value: progressPercent / 100.0,
                                              minHeight: 4,
                                              backgroundColor: Colors.white12,
                                              color: color,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            '${progressPercent.round()}%',
                                            style: const TextStyle(
                                              color: Color(0xFFCBD5E1),
                                              fontSize: 10,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                    if (durationMs != null) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        durationMs >= 1000
                                            ? 'المدة: ${(durationMs / 1000).toStringAsFixed(2)} ث'
                                            : 'المدة: $durationMs مللي ثانية',
                                        style: const TextStyle(
                                          color: Color(0xFF94A3B8),
                                          fontSize: 10,
                                        ),
                                      ),
                                    ],
                                    if (metadata.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Theme(
                                        data: Theme.of(context).copyWith(
                                          dividerColor: Colors.transparent,
                                          splashColor: Colors.transparent,
                                          highlightColor: Colors.transparent,
                                        ),
                                        child: ExpansionTile(
                                          tilePadding: EdgeInsets.zero,
                                          childrenPadding: const EdgeInsets.only(bottom: 6),
                                          dense: true,
                                          collapsedIconColor: const Color(0xFF64748B),
                                          iconColor: const Color(0xFF5EEAD4),
                                          title: const Text('تفاصيل العامل والأداة',
                                            style: TextStyle(color: Color(0xFF5EEAD4), fontSize: 11)),
                                          children: metadata.map((item) => Padding(
                                            padding: const EdgeInsets.symmetric(vertical: 3),
                                            child: Row(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                SizedBox(width: 112, child: Text(item.key,
                                                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10))),
                                                Expanded(child: SelectableText(item.value,
                                                  style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 10))),
                                              ],
                                            ),
                                          )).toList(),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              if (event.status == 'running' &&
                                  (event.payload['tool_call_id']?.toString().isNotEmpty ?? false))
                                IconButton(
                                  tooltip: 'إيقاف استدعاء الأداة',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () async {
                                    final callId = event.payload['tool_call_id'].toString();
                                    final stopped = AgentService.instance.cancelToolCall(callId);
                                    if (stopped) await _refresh();
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(stopped
                                            ? 'أُرسل طلب إيقاف الأداة.'
                                            : 'لم يعد استدعاء الأداة نشطاً.'),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.stop_circle_outlined,
                                      color: Color(0xFFF87171), size: 20),
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
