import 'package:flutter/material.dart';

class ConversationTile extends StatelessWidget {
  final String title;
  final String preview;
  final DateTime lastMessageTime;
  final int messageCount;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  
  const ConversationTile({
    super.key,
    required this.title,
    required this.preview,
    required this.lastMessageTime,
    required this.messageCount,
    required this.onTap,
    required this.onDelete,
  });
  
  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(title),
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => onDelete(),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: const Color(0xFF10A37F).withOpacity(0.1),
          child: const Icon(Icons.chat, color: Color(0xFF10A37F)),
        ),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          preview,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${lastMessageTime.hour}:${lastMessageTime.minute.toString().padLeft(2, '0')}',
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
            const SizedBox(height: 4),
            if (messageCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF10A37F),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$messageCount',
                  style: const TextStyle(fontSize: 10, color: Colors.white),
                ),
              ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}
