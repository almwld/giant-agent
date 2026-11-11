/// A truthful, serializable event emitted by the agent orchestration layer.
/// Event IDs identify transitions; step IDs correlate transitions belonging to
/// one logical operation. Events never contain private chain-of-thought.
class AgentTimelineEvent {
  const AgentTimelineEvent({
    required this.id,
    required this.requestId,
    required this.type,
    required this.title,
    required this.status,
    required this.timestamp,
    this.stepId,
    this.toolCallId,
    this.attemptId,
    this.sequence,
    this.details,
    this.result,
    this.taskId,
    this.agentType,
    this.taskPrompt,
    this.dependsOn = const <String>[],
    this.metadata = const <String, Object?>{},
  });

  final String id;
  final String requestId;
  final String type;
  final String title;
  final String status;
  final DateTime timestamp;
  final String? stepId;
  final String? toolCallId;
  final String? attemptId;
  final int? sequence;
  final String? details;
  final String? result;
  final String? taskId;
  final String? agentType;
  final String? taskPrompt;
  final List<String> dependsOn;
  final Map<String, Object?> metadata;

  Map<String, dynamic> toMap() => <String, dynamic>{
        ...metadata,
        'id': id,
        'request_id': requestId,
        'attempt_id': attemptId != null && attemptId!.isNotEmpty ? attemptId : requestId,
        'type': type,
        'title': title,
        'status': status,
        'timestamp': timestamp.toUtc().toIso8601String(),
        if (stepId != null && stepId!.isNotEmpty) 'step_id': stepId,
        if (toolCallId != null && toolCallId!.isNotEmpty) 'tool_call_id': toolCallId,
        if (sequence != null) 'sequence': sequence,
        if (details != null && details!.isNotEmpty) 'details': details,
        if (result != null && result!.isNotEmpty) 'result': result,
        if (taskId != null && taskId!.isNotEmpty) 'task_id': taskId,
        if (agentType != null && agentType!.isNotEmpty) 'agent_type': agentType,
        if (taskPrompt != null && taskPrompt!.isNotEmpty) 'task_prompt': taskPrompt,
        if (dependsOn.isNotEmpty) 'depends_on': dependsOn,
      };

  factory AgentTimelineEvent.fromMap(Map<String, dynamic> map) {
    final rawTimestamp = map['timestamp'];
    final timestamp = rawTimestamp is DateTime
        ? rawTimestamp
        : rawTimestamp is num
            ? DateTime.fromMillisecondsSinceEpoch(rawTimestamp.toInt(), isUtc: true)
            : DateTime.tryParse(rawTimestamp?.toString() ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final rawSequence = map['sequence'];
    return AgentTimelineEvent(
      id: map['id']?.toString() ?? '',
      requestId: (map['request_id'] ?? map['requestId'])?.toString() ?? '',
      attemptId: (map['attempt_id'] ?? map['request_id'] ?? map['requestId'])?.toString(),
      stepId: (map['step_id'] ?? map['stepId'])?.toString(),
      toolCallId: (map['tool_call_id'] ?? map['toolCallId'])?.toString(),
      sequence: rawSequence is num ? rawSequence.toInt() : int.tryParse(rawSequence?.toString() ?? ''),
      type: map['type']?.toString() ?? 'unknown',
      title: map['title']?.toString() ?? '',
      status: map['status']?.toString() ?? 'pending',
      timestamp: timestamp,
      details: map['details']?.toString(),
      result: map['result']?.toString(),
      taskId: map['task_id']?.toString(),
      agentType: map['agent_type']?.toString(),
      taskPrompt: map['task_prompt']?.toString(),
      dependsOn: (map['depends_on'] as List?)?.map((item) => item.toString()).toList(growable: false) ?? const <String>[],
      metadata: Map<String, Object?>.from(map)..removeWhere((key, _) => const <String>{
        'id', 'request_id', 'requestId', 'attempt_id', 'step_id', 'stepId',
        'tool_call_id', 'toolCallId', 'sequence', 'type', 'title', 'status',
        'timestamp', 'details', 'result', 'task_id', 'agent_type', 'task_prompt',
        'depends_on',
      }.contains(key)),
    );
  }
}
