import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A portable, prompt-level skill definition. Skills are instructions and
/// routing hints; they never grant tools or bypass the runtime's permissions.
class AgentSkill {
  const AgentSkill({
    required this.id,
    required this.name,
    required this.description,
    required this.instructions,
    this.tags = const <String>[],
    this.builtIn = false,
  });

  final String id;
  final String name;
  final String description;
  final String instructions;
  final List<String> tags;
  final bool builtIn;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'description': description,
        'instructions': instructions,
        'tags': tags,
      };

  factory AgentSkill.fromJson(Map<String, dynamic> json) => AgentSkill(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        description: json['description']?.toString() ?? '',
        instructions: json['instructions']?.toString() ?? '',
        tags: (json['tags'] as List? ?? const <dynamic>[])
            .map((item) => item.toString())
            .toList(growable: false),
      );
}

/// Hermes-inspired skill discovery and activation, implemented as a lightweight
/// layer over the existing Giant Agent runtime. It does not spawn a second
/// model, tool registry, or execution environment.
class AgentSkillRegistry {
  AgentSkillRegistry._();
  static final AgentSkillRegistry instance = AgentSkillRegistry._();

  static const String _storageKey = 'giant_agent_skills_v1';
  static const int _maxCustomSkills = 64;
  static const int _maxInstructions = 6000;

  static const List<AgentSkill> _builtIns = <AgentSkill>[
    AgentSkill(
      id: 'software_delivery',
      name: 'Software delivery',
      description: 'Repository work, implementation, debugging and safe changes.',
      tags: <String>['code', 'coding', 'software', 'flutter', 'dart', 'repository', 'github', 'برمجة', 'كود', 'مستودع'],
      builtIn: true,
      instructions: '''
For software work, inspect the existing architecture before editing. Reuse established services and state owners; avoid duplicate runtimes, registries, or providers. Make the smallest coherent change, preserve public contracts, and keep user data and secrets out of logs. Never claim tests, builds, or runtime verification unless they were actually performed. Report changed paths and unresolved risks.
''',
    ),
    AgentSkill(
      id: 'research_evidence',
      name: 'Evidence-led research',
      description: 'Research, source evaluation and technical comparisons.',
      tags: <String>['research', 'sources', 'compare', 'evidence', 'بحث', 'مصادر', 'مقارنة'],
      builtIn: true,
      instructions: '''
Separate verified facts, inferences and unknowns. Prefer primary documentation and inspect version/date context. Compare alternatives against explicit requirements, identify licensing and operational constraints, and do not turn a plausible design into a claim of production readiness.
''',
    ),
    AgentSkill(
      id: 'planning_delegation',
      name: 'Planning and delegation',
      description: 'Break complex requests into dependency-aware deliverables.',
      tags: <String>['plan', 'planning', 'delegate', 'parallel', 'roadmap', 'خطة', 'تقسيم', 'تفويض'],
      builtIn: true,
      instructions: '''
Decompose the goal into independently verifiable deliverables. Declare dependencies, assign parallel work only when side effects do not conflict, and serialize shared workspace mutations. Keep one coordinator responsible for integration and final reconciliation. Preserve checkpoints before risky side effects.
''',
    ),
    AgentSkill(
      id: 'mobile_runtime',
      name: 'Mobile runtime design',
      description: 'Mobile UX, offline-first behavior and resource-aware inference.',
      tags: <String>['mobile', 'android', 'flutter', 'offline', 'local model', 'phone', 'هاتف', 'أندرويد', 'محلي'],
      builtIn: true,
      instructions: '''
Design for constrained memory, battery, network and lifecycle interruption. Keep long work visible and resumable, use foreground execution only when platform policy requires it, persist meaningful progress, and make local/cloud routing explicit. Avoid blocking the UI thread and avoid creating a second local model runtime.
''',
    ),
    AgentSkill(
      id: 'tool_safety',
      name: 'Tool and side-effect safety',
      description: 'MCP, terminal, approvals, cancellation and recovery.',
      tags: <String>['tool', 'mcp', 'terminal', 'command', 'approval', 'cancel', 'أداة', 'طرفية', 'إلغاء'],
      builtIn: true,
      instructions: '''
Treat tool calls as independently identified operations. Propagate cancellation to the actual in-flight request or process, enforce tool permissions at dispatch, require approval for consequential external actions, preserve structured tool output, and never automatically replay an operation whose side effect is uncertain after a crash.
''',
    ),
  ];

  Future<List<AgentSkill>> listSkills() async {
    final custom = await _loadCustom();
    return List<AgentSkill>.unmodifiable(<AgentSkill>[..._builtIns, ...custom]);
  }

  Future<void> upsertSkill(AgentSkill skill) async {
    final id = skill.id.trim();
    final name = skill.name.trim();
    final description = skill.description.trim();
    final instructions = skill.instructions.trim();
    if (!RegExp(r'^[a-zA-Z0-9_-]{2,48}$').hasMatch(id) ||
        name.isEmpty || name.length > 100 ||
        description.length > 500 ||
        instructions.isEmpty || instructions.length > _maxInstructions ||
        skill.tags.length > 24 ||
        skill.tags.any((tag) => tag.trim().isEmpty || tag.length > 48)) {
      throw ArgumentError('Skill metadata or instructions are invalid or exceed their limits.');
    }
    if (_builtIns.any((item) => item.id == id)) {
      throw StateError('Built-in skills cannot be overwritten.');
    }
    final custom = await _loadCustom();
    final updated = custom.where((item) => item.id != id).toList();
    if (updated.length >= _maxCustomSkills) {
      throw StateError('The custom skill limit has been reached.');
    }
    updated.add(AgentSkill(
      id: id,
      name: name,
      description: description,
      instructions: instructions,
      tags: skill.tags.map((tag) => tag.trim().toLowerCase()).toList(growable: false),
    ));
    await _saveCustom(updated);
  }

  Future<bool> removeSkill(String id) async {
    if (_builtIns.any((item) => item.id == id)) return false;
    final current = await _loadCustom();
    final updated = current.where((item) => item.id != id).toList();
    if (updated.length == current.length) return false;
    await _saveCustom(updated);
    return true;
  }

  /// Selects only skills relevant to this request and bounds their prompt cost.
  Future<String> buildPromptContext(String request, {int maxSkills = 3}) async {
    final normalized = request.toLowerCase();
    final all = await listSkills();
    final ranked = <({AgentSkill skill, int score})>[];
    for (final skill in all) {
      final terms = <String>{skill.id.replaceAll('_', ' '), ...skill.tags};
      final score = terms.where((term) =>
          term.trim().isNotEmpty && normalized.contains(term.toLowerCase())).length;
      if (score > 0) ranked.add((skill: skill, score: score));
    }
    ranked.sort((a, b) {
      final score = b.score.compareTo(a.score);
      if (score != 0) return score;
      return a.skill.id.compareTo(b.skill.id);
    });
    final selected = ranked.take(maxSkills.clamp(1, 5)).toList();
    if (selected.isEmpty) return '';
    final body = selected.map((item) =>
        '### ${item.skill.name}\n${item.skill.instructions.trim()}').join('\n\n');
    return '[Request-matched skills: guidance only; existing tool permissions and runtime policy remain authoritative]\n$body';
  }

  Future<List<AgentSkill>> _loadCustom() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return const <AgentSkill>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <AgentSkill>[];
      return decoded.whereType<Map>().map((item) =>
          AgentSkill.fromJson(Map<String, dynamic>.from(item)))
          .where((skill) => skill.id.isNotEmpty && skill.instructions.isNotEmpty)
          .toList(growable: false);
    } on FormatException {
      return const <AgentSkill>[];
    }
  }

  Future<void> _saveCustom(List<AgentSkill> skills) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(
      skills.map((skill) => skill.toJson()).toList(growable: false),
    ));
  }
}
