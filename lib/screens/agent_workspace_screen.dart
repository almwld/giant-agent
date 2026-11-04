import 'package:flutter/material.dart';

/// Local, read-only workspace for artifacts emitted by the agent runtime.
/// It previews only files explicitly included in agent events; it is not a
/// remote desktop or a shell and does not execute arbitrary commands.
class AgentWorkspaceScreen extends StatefulWidget {
  final List<Map<String, dynamic>> steps;
  const AgentWorkspaceScreen({super.key, required this.steps});

  @override
  State<AgentWorkspaceScreen> createState() => _AgentWorkspaceScreenState();
}

class _AgentWorkspaceScreenState extends State<AgentWorkspaceScreen> {
  int _selected = 0;

  List<Map<String, dynamic>> get _files => widget.steps.where((step) {
    final type = step['type']?.toString();
    return (type == 'file_created' || type == 'file_read' || type == 'file' || type == 'code') &&
        (step['content'] != null || step['file_name'] != null);
  }).toList(growable: false);

  @override
  Widget build(BuildContext context) {
    final files = _files;
    final selected = files.isEmpty ? null : files[_selected.clamp(0, files.length - 1).toInt()];
    return Scaffold(
      backgroundColor: const Color(0xFF0F1720),
      appBar: AppBar(
        backgroundColor: const Color(0xFF17212B),
        foregroundColor: Colors.white,
        title: const Text('Agent Workspace'),
        actions: [
          if (selected?['content'] != null)
            IconButton(
              tooltip: 'نسخ المحتوى',
              icon: const Icon(Icons.copy),
              onPressed: () => _copy(context, selected!['content'].toString()),
            ),
        ],
      ),
      body: Row(
        children: [
          SizedBox(
            width: 148,
            child: DecoratedBox(
              decoration: const BoxDecoration(color: Color(0xFF151F29)),
              child: files.isEmpty
                  ? const Center(child: Text('لا توجد ملفات بعد', style: TextStyle(color: Colors.white54, fontSize: 12)))
                  : ListView.builder(
                      itemCount: files.length,
                      itemBuilder: (context, index) {
                        final file = files[index];
                        final name = file['file_name']?.toString() ?? file['title']?.toString() ?? 'untitled';
                        return ListTile(
                          dense: true,
                          selected: index == _selected,
                          selectedTileColor: Colors.teal.withOpacity(.18),
                          leading: const Icon(Icons.insert_drive_file_outlined, color: Colors.tealAccent, size: 17),
                          title: Text(name.split('/').last, maxLines: 2, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white70, fontSize: 11)),
                          onTap: () => setState(() => _selected = index),
                        );
                      },
                    ),
            ),
          ),
          const VerticalDivider(width: 1, color: Colors.white12),
          Expanded(
            child: selected == null
                ? const Center(child: Icon(Icons.code, color: Colors.white24, size: 54))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                        color: const Color(0xFF17212B),
                        child: Text(selected['file_name']?.toString() ?? selected['title']?.toString() ?? 'Artifact',
                            style: const TextStyle(color: Colors.tealAccent, fontSize: 12)),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(14),
                          child: SelectableText(
                            selected['content']?.toString() ?? 'لم يرفق الحدث محتوى الملف.',
                            style: const TextStyle(color: Color(0xFFE2E8F0), fontFamily: 'monospace', fontSize: 12, height: 1.5),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _copy(BuildContext context, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نسخ المحتوى')));
    }
  }
}
