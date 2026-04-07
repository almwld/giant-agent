import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  Map<String, dynamic> _stats = {};
  
  @override
  void initState() {
    super.initState();
    _loadStats();
  }
  
  Future<void> _loadStats() async {
    final dir = await getApplicationDocumentsDirectory();
    final db = await openDatabase('${dir.path}/giant_agent.db');
    
    final messageCount = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM messages')
    ) ?? 0;
    
    final userCount = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(DISTINCT user_id) FROM messages')
    ) ?? 0;
    
    final todayCount = Sqflite.firstIntValue(
      await db.rawQuery('''
        SELECT COUNT(*) FROM messages 
        WHERE date(timestamp/1000, 'unixepoch') = date('now')
      ''')
    ) ?? 0;
    
    setState(() {
      _stats = {
        'total_messages': messageCount,
        'total_users': userCount,
        'today_messages': todayCount,
        'last_updated': DateTime.now(),
      };
    });
    
    await db.close();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Statistics'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildStatCard('Total Messages', '${_stats['total_messages'] ?? 0}', Icons.chat),
            const SizedBox(height: 16),
            _buildStatCard('Total Users', '${_stats['total_users'] ?? 0}', Icons.people),
            const SizedBox(height: 16),
            _buildStatCard('Today\'s Messages', '${_stats['today_messages'] ?? 0}', Icons.today),
            const SizedBox(height: 16),
            _buildStatCard('Last Updated', 
                '${(_stats['last_updated'] as DateTime?)?.toString().substring(0, 19) ?? 'Never'}', 
                Icons.update),
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
                  Text(
                    title,
                    style: const TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
