/// A truthful, serializable event emitted by the agent orchestration layer.
/// It contains user-safe execution metadata, never private chain-of-thought.
class AgentTimelineEvent {
  const AgentTimelineEvent({
    required this.id,
    required this.requestId,
    required this.type,
    required this.title,
    required this.status,
    required this.timestamp,
    this.details,
  });

  final String id;
  final String requestId;
  final String type;
  final String title;
  final String status;
  final DateTime timestamp;
  final String? details;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        'request_id': requestId,
        'type': type,
        'title': title,
        'status': status,
        'timestamp': timestamp.toIso8601String(),
        if (details != null && details!.isNotEmpty) 'details': details,
      };
}
