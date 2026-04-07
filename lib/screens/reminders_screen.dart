import 'package:flutter/material.dart';
import '../services/reminder_service.dart';
import '../services/notification_service.dart';

class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  final ReminderService _reminderService = ReminderService();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  List<Map<String, dynamic>> _reminders = [];
  
  @override
  void initState() {
    super.initState();
    _init();
  }
  
  Future<void> _init() async {
    await _reminderService.init();
    await _loadReminders();
  }
  
  Future<void> _loadReminders() async {
    final reminders = await _reminderService.getReminders();
    setState(() {
      _reminders = reminders;
    });
  }
  
  Future<void> _addReminder() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    
    if (time != null) {
      final date = await showDatePicker(
        context: context,
        initialDate: DateTime.now(),
        firstDate: DateTime.now(),
        lastDate: DateTime.now().add(const Duration(days: 365)),
      );
      
      if (date != null) {
        final reminderTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
        await _reminderService.addReminder(
          _titleController.text,
          _descController.text,
          reminderTime,
        );
        
        await NotificationService().scheduleNotification(
          reminderTime,
          _titleController.text,
          _descController.text,
        );
        
        _titleController.clear();
        _descController.clear();
        await _loadReminders();
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reminder added successfully')),
        );
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reminders'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Add Reminder Form
          Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _descController,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _addReminder,
                  icon: const Icon(Icons.add_alarm),
                  label: const Text('Add Reminder'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10A37F),
                    minimumSize: const Size(double.infinity, 48),
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          // Reminders List
          Expanded(
            child: _reminders.isEmpty
                ? const Center(child: Text('No reminders yet'))
                : ListView.builder(
                    itemCount: _reminders.length,
                    itemBuilder: (context, index) {
                      final reminder = _reminders[index];
                      final time = DateTime.fromMillisecondsSinceEpoch(reminder['reminder_time']);
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: reminder['is_completed'] == 1
                              ? Colors.green
                              : const Color(0xFF10A37F),
                          child: Icon(
                            reminder['is_completed'] == 1 ? Icons.check : Icons.alarm,
                            color: Colors.white,
                          ),
                        ),
                        title: Text(reminder['title']),
                        subtitle: Text(reminder['description']),
                        trailing: Text(
                          '${time.day}/${time.month} ${time.hour}:${time.minute.toString().padLeft(2, '0')}',
                        ),
                        onTap: () async {
                          await _reminderService.completeReminder(reminder['id']);
                          await _loadReminders();
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
