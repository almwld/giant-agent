import 'package:flutter/material.dart';

class ChatBubble extends StatelessWidget {
  final bool isUser;
  final String message;
  final DateTime time;
  final String? intent;
  final double? confidence;

  const ChatBubble({
    super.key,
    required this.isUser,
    required this.message,
    required this.time,
    this.intent,
    this.confidence,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        child: Column(
          crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Material(
              elevation: 2,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isUser ? 16 : 4),
                bottomRight: Radius.circular(isUser ? 4 : 16),
              ),
              color: isUser ? Colors.deepPurple : Colors.grey.shade800,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      message,
                      style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
                    ),
                    if (intent != null) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.bolt, size: 10, color: Colors.amber.shade300),
                            const SizedBox(width: 4),
                            Text(
                              intent!,
                              style: const TextStyle(fontSize: 9, color: Colors.white70),
                            ),
                            if (confidence != null) ...[
                              const SizedBox(width: 4),
                              Container(
                                width: 4,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: Colors.white54,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${(confidence! * 100).toInt()}%',
                                style: const TextStyle(fontSize: 9, color: Colors.white70),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 8, right: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isUser ? Icons.person : Icons.bolt,
                    size: 10,
                    color: Colors.grey.shade600,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                    style: TextStyle(fontSize: 9, color: Colors.grey.shade600),
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
