import 'package:flutter/material.dart';
import '../services/agent_memory_service.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  Map<String, int> _stats = const {};
  bool _loading = true;
  String? _error;
  DateTime? _lastUpdated;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final stats =
          await AgentMemoryService.instance.getUsageStatistics();
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _lastUpdated = DateTime.now();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Statistics'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Refresh statistics',
            onPressed: _loading ? null : _loadStats,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, size: 36),
                        const SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _loadStats,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadStats,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildStatCard(
                        'Total Messages',
                        '${_stats['total_messages'] ?? 0}',
                        Icons.chat_rounded,
                      ),
                      const SizedBox(height: 16),
                      _buildStatCard(
                        'Total Conversations',
                        '${_stats['total_conversations'] ?? 0}',
                        Icons.forum_rounded,
                      ),
                      const SizedBox(height: 16),
                      _buildStatCard(
                        "Today's Messages",
                        '${_stats['today_messages'] ?? 0}',
                        Icons.today_rounded,
                      ),
                      const SizedBox(height: 16),
                      _buildStatCard(
                        'Last Updated',
                        _lastUpdated?.toString().substring(0, 19) ?? 'Never',
                        Icons.update_rounded,
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF10A37F).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 30, color: const Color(0xFF10A37F)),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontSize: 14, color: Colors.grey)),
                  const SizedBox(height: 4),
                  Text(value,
                      style: const TextStyle(
                          fontSize: 24, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
