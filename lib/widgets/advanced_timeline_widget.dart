import 'package:flutter/material.dart';
import '../core/timeline_engine.dart';

typedef TimelineCancelCallback = Future<void> Function(String toolCallId);

class AdvancedTimelineWidget extends StatefulWidget {
  const AdvancedTimelineWidget({
    super.key,
    required this.events,
    this.onCancelTool,
    this.compact = false,
    this.title = 'Execution timeline',
  });

  final List<AgentTimelineEvent> events;
  final TimelineCancelCallback? onCancelTool;
  final bool compact;
  final String title;

  @override
  State<AdvancedTimelineWidget> createState() => _AdvancedTimelineWidgetState();
}

class _AdvancedTimelineWidgetState extends State<AdvancedTimelineWidget>
    with TickerProviderStateMixin {
  final TextEditingController _search = TextEditingController();
  TimelineStatus? _statusFilter;
  TimelineEventType? _typeFilter;
  String? _expandedId;

  static const _background = Color(0xFF111113);
  static const _card = Color(0xFF18181B);
  static const _accent = Color(0xFF2563EB);
  static const _muted = Color(0xFF9CA3AF);

  List<AgentTimelineEvent> get _filtered {
    final query = _search.text.trim().toLowerCase();
    return widget.events.where((event) {
      if (_statusFilter != null && event.status != _statusFilter) return false;
      if (_typeFilter != null && event.type != _typeFilter) return false;
      if (query.isEmpty) return true;
      return <String>[
        event.title, event.description ?? '', event.toolName ?? '',
        event.agentId ?? '', event.error ?? '',
      ].join(' ').toLowerCase().contains(query);
    }).toList(growable: false);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final events = _filtered;
    final completed = widget.events.where((e) => e.status == TimelineStatus.completed).length;
    final failed = widget.events.where((e) => e.status == TimelineStatus.failed).length;
    final active = widget.events.where((e) => e.isActive).length;

    return Container(
      decoration: BoxDecoration(
        color: _background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      padding: EdgeInsets.all(widget.compact ? 10 : 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.account_tree_outlined, color: _accent, size: 19),
            const SizedBox(width: 8),
            Expanded(child: Text(widget.title,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
            _countChip('LIVE', active, const Color(0xFF22C55E)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _stat('Events', widget.events.length, Colors.white70)),
            Expanded(child: _stat('Completed', completed, const Color(0xFF22C55E))),
            Expanded(child: _stat('Failed', failed, const Color(0xFFEF4444))),
            Expanded(child: _stat('Active', active, const Color(0xFF60A5FA))),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Search events, tools, agents…',
              hintStyle: const TextStyle(color: _muted, fontSize: 12),
              prefixIcon: const Icon(Icons.search, color: _muted, size: 18),
              suffixIcon: _search.text.isEmpty ? null : IconButton(
                onPressed: () { _search.clear(); setState(() {}); },
                icon: const Icon(Icons.close, color: _muted, size: 17),
              ),
              filled: true, fillColor: _card,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            _filterChip('All statuses', _statusFilter == null, () => setState(() => _statusFilter = null)),
            ...TimelineStatus.values.map((status) => _filterChip(
              _statusLabel(status), _statusFilter == status,
              () => setState(() => _statusFilter = status))),
          ]),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            _filterChip('All types', _typeFilter == null, () => setState(() => _typeFilter = null)),
            ...TimelineEventType.values.map((type) => _filterChip(
              _typeLabel(type), _typeFilter == type,
              () => setState(() => _typeFilter = type))),
          ]),
          const SizedBox(height: 10),
          if (events.isEmpty)
            const Padding(
              padding: EdgeInsets.all(18),
              child: Center(child: Text('No timeline events match this filter.',
                style: TextStyle(color: _muted, fontSize: 12))),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: events.length,
              separatorBuilder: (_, __) => const SizedBox(height: 7),
              itemBuilder: (context, index) => _eventCard(events[index]),
            ),
        ],
      ),
    );
  }

  Widget _eventCard(AgentTimelineEvent event) {
    final expanded = _expandedId == event.id;
    final color = _statusColor(event.status);
    final canCancel = event.isActive && event.toolCallId != null &&
        widget.onCancelTool != null;
    return Container(
      decoration: BoxDecoration(
        color: _card, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(.22)),
      ),
      child: Column(children: [
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _expandedId = expanded ? null : event.id),
          child: Padding(
            padding: const EdgeInsets.all(11),
            child: Row(children: [
              Container(
                width: 34, height: 34,
                decoration: BoxDecoration(color: color.withOpacity(.13), shape: BoxShape.circle),
                child: Icon(_eventIcon(event.type), color: color, size: 17),
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(event.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 12,
                    fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text([
                  _statusLabel(event.status),
                  if (event.toolName != null) event.toolName!,
                  _timeLabel(event.createdAt),
                ].join(' • '), style: const TextStyle(color: _muted, fontSize: 10)),
              ])),
              if (canCancel)
                IconButton(
                  tooltip: 'Cancel tool',
                  visualDensity: VisualDensity.compact,
                  onPressed: () async {
                    try { await widget.onCancelTool!(event.toolCallId!); }
                    catch (error) {
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Cancellation failed: $error')));
                    }
                  },
                  icon: const Icon(Icons.stop_circle_outlined, color: Color(0xFFEF4444)),
                )
              else
                Icon(Icons.expand_more, color: _muted, size: 19),
            ]),
          ),
        ),
        if (event.progress != null && event.isActive)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Row(children: [
              Expanded(child: ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: LinearProgressIndicator(
                  value: event.progress!.clamp(0, 1).toDouble(),
                  minHeight: 5, backgroundColor: Colors.white10, color: color,
                ),
              )),
              const SizedBox(width: 8),
              Text('${(event.progress! * 100).round()}%',
                style: TextStyle(color: color, fontSize: 10)),
            ]),
          ),
        if (expanded) _details(event),
      ]),
    );
  }

  Widget _details(AgentTimelineEvent event) => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (event.description?.isNotEmpty == true) _detail('Description', event.description!),
      if (event.error?.isNotEmpty == true)
        _detail('Error', event.error!, valueColor: const Color(0xFFF87171)),
      if (event.agentId != null) _detail('Agent ID', event.agentId!),
      if (event.parentAgentId != null) _detail('Parent agent', event.parentAgentId!),
      if (event.toolCallId != null) _detail('Tool call ID', event.toolCallId!),
      if (event.completedAt != null)
        _detail('Duration', event.completedAt!.difference(event.createdAt).toString().split('.').first),
      if (event.metadata.isNotEmpty) ...[
        const SizedBox(height: 6),
        const Text('Metadata', style: TextStyle(color: Colors.white70,
          fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        SelectableText(event.metadata.entries.map((e) => '${e.key}: ${e.value}').join('\n'),
          style: const TextStyle(color: _muted, fontSize: 10)),
      ],
    ]),
  );

  Widget _detail(String label, String value, {Color valueColor = _muted}) =>
    Padding(padding: const EdgeInsets.only(top: 5), child: Row(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 95, child: Text(label,
          style: const TextStyle(color: Colors.white54, fontSize: 10))),
        Expanded(child: SelectableText(value,
          style: TextStyle(color: valueColor, fontSize: 10))),
      ],
    ));

  Widget _stat(String label, int value, Color color) => Column(children: [
    Text('$value', style: TextStyle(color: color, fontSize: 17, fontWeight: FontWeight.bold)),
    Text(label, style: const TextStyle(color: _muted, fontSize: 9)),
  ]);

  Widget _countChip(String label, int value, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(color: color.withOpacity(.12),
      borderRadius: BorderRadius.circular(20)),
    child: Text('$label $value', style: TextStyle(color: color, fontSize: 9,
      fontWeight: FontWeight.bold)),
  );

  Widget _filterChip(String label, bool selected, VoidCallback onTap) => ChoiceChip(
    label: Text(label, style: TextStyle(fontSize: 9,
      color: selected ? Colors.white : _muted)),
    selected: selected, onSelected: (_) => onTap(),
    backgroundColor: _card, selectedColor: _accent.withOpacity(.7),
    side: BorderSide(color: selected ? _accent : Colors.white12),
    padding: EdgeInsets.zero, visualDensity: VisualDensity.compact,
  );

  String _statusLabel(TimelineStatus s) => switch (s) {
    TimelineStatus.pending => 'Pending',
    TimelineStatus.waiting => 'Waiting',
    TimelineStatus.running => 'Running',
    TimelineStatus.completed => 'Completed',
    TimelineStatus.failed => 'Failed',
    TimelineStatus.cancelled => 'Cancelled',
  };
  String _typeLabel(TimelineEventType t) => t.name.replaceAllMapped(
    RegExp(r'([A-Z])'), (m) => ' ${m[1]}').trim();
  Color _statusColor(TimelineStatus s) => switch (s) {
    TimelineStatus.pending || TimelineStatus.waiting => const Color(0xFFFBBF24),
    TimelineStatus.running => const Color(0xFF60A5FA),
    TimelineStatus.completed => const Color(0xFF22C55E),
    TimelineStatus.failed => const Color(0xFFEF4444),
    TimelineStatus.cancelled => const Color(0xFFA1A1AA),
  };
  IconData _eventIcon(TimelineEventType t) => switch (t) {
    TimelineEventType.taskStarted => Icons.play_circle_outline,
    TimelineEventType.taskCompleted => Icons.task_alt,
    TimelineEventType.taskFailed || TimelineEventType.taskCancelled => Icons.error_outline,
    TimelineEventType.agentCreated => Icons.person_add_alt,
    TimelineEventType.agentStarted => Icons.smart_toy_outlined,
    TimelineEventType.agentProgress => Icons.insights,
    TimelineEventType.agentCompleted => Icons.verified_outlined,
    TimelineEventType.agentFailed => Icons.person_off_outlined,
    TimelineEventType.toolStarted => Icons.build_outlined,
    TimelineEventType.toolProgress => Icons.trending_up,
    TimelineEventType.toolCompleted => Icons.check_circle_outline,
    TimelineEventType.toolFailed || TimelineEventType.toolCancelled => Icons.warning_amber,
    TimelineEventType.message => Icons.chat_bubble_outline,
    TimelineEventType.info => Icons.info_outline,
    TimelineEventType.warning => Icons.warning_amber,
    TimelineEventType.error => Icons.error_outline,
  };
  String _timeLabel(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}:${value.second.toString().padLeft(2, '0')}';
}
