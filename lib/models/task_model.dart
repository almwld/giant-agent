enum TaskPriority { low, medium, high, urgent }

enum TaskStatus {
  pending,
  planning,
  inProgress,
  verifying,
  completed,
  failed,
  blocked,
  interrupted,
  cancelled,
}

enum TaskStepStatus {
  pending,
  inProgress,
  verifying,
  completed,
  failed,
  blocked,
  interrupted,
  cancelled,
}

class TaskStep {
  TaskStep({
    required this.id,
    required this.action,
    required this.type,
    this.dependencies = const [],
    this.status = TaskStepStatus.pending,
    this.attempts = 0,
    this.output,
    this.evidence,
    this.error,
    this.startedAt,
    this.finishedAt,
    this.durationMs,
  });

  final String id;
  final String action;
  final String type;
  final List<String> dependencies;
  TaskStepStatus status;
  int attempts;
  Map<String, dynamic>? output;
  String? evidence;
  String? error;
  DateTime? startedAt;
  DateTime? finishedAt;
  int? durationMs;

  Map<String, dynamic> toJson() => {
        'id': id,
        'action': action,
        'type': type,
        'dependencies': dependencies,
        'status': status.name,
        'attempts': attempts,
        'output': output,
        'evidence': evidence,
        'error': error,
        'startedAt': startedAt?.toIso8601String(),
        'finishedAt': finishedAt?.toIso8601String(),
        'durationMs': durationMs,
      };

  factory TaskStep.fromJson(Map<String, dynamic> json) => TaskStep(
        id: json['id']?.toString() ?? '',
        action: json['action']?.toString() ?? '',
        type: json['type']?.toString() ?? '',
        dependencies: _stringList(json['dependencies']),
        status: _enumValue(TaskStepStatus.values, json['status'], TaskStepStatus.pending),
        attempts: _intValue(json['attempts']),
        output: json['output'] is Map
            ? Map<String, dynamic>.from(json['output'] as Map)
            : null,
        evidence: json['evidence']?.toString(),
        error: json['error']?.toString(),
        startedAt: _dateValue(json['startedAt']),
        finishedAt: _dateValue(json['finishedAt']),
        durationMs: json['durationMs'] == null ? null : _intValue(json['durationMs']),
      );
}

class TaskModel {
  TaskModel({
    required this.id,
    required this.title,
    required this.description,
    required this.createdAt,
    this.priority = TaskPriority.medium,
    this.status = TaskStatus.pending,
    this.completedAt,
    List<TaskStep>? steps,
    this.tags = const [],
    this.error,
    this.verificationEvidence,
  }) : steps = steps ?? <TaskStep>[];

  final String id;
  final String title;
  final String description;
  final DateTime createdAt;
  TaskPriority priority;
  TaskStatus status;
  DateTime? completedAt;
  final List<TaskStep> steps;
  final List<String> tags;
  String? error;
  String? verificationEvidence;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'priority': priority.name,
        'status': status.name,
        'createdAt': createdAt.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
        'steps': steps.map((step) => step.toJson()).toList(),
        'tags': tags,
        'error': error,
        'verificationEvidence': verificationEvidence,
      };

  factory TaskModel.fromJson(Map<String, dynamic> json) => TaskModel(
        id: json['id']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        description: json['description']?.toString() ?? '',
        priority: _enumValue(TaskPriority.values, json['priority'], TaskPriority.medium),
        status: _enumValue(TaskStatus.values, json['status'], TaskStatus.pending),
        createdAt: _dateValue(json['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
        completedAt: _dateValue(json['completedAt']),
        steps: json['steps'] is List
            ? (json['steps'] as List)
                .whereType<Map>()
                .map((step) => TaskStep.fromJson(Map<String, dynamic>.from(step)))
                .toList()
            : <TaskStep>[],
        tags: _stringList(json['tags']),
        error: json['error']?.toString(),
        verificationEvidence: json['verificationEvidence']?.toString(),
      );
}

T _enumValue<T extends Enum>(List<T> values, Object? raw, T fallback) {
  final name = raw?.toString();
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}

List<String> _stringList(Object? raw) => raw is List
    ? raw.map((value) => value.toString()).toList()
    : <String>[];

int _intValue(Object? raw) => raw is int ? raw : int.tryParse(raw?.toString() ?? '') ?? 0;

DateTime? _dateValue(Object? raw) {
  if (raw is DateTime) return raw;
  if (raw == null) return null;
  return DateTime.tryParse(raw.toString());
}
