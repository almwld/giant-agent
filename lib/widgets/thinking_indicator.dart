import 'package:flutter/material.dart';
import 'agent_activity_indicators.dart';

/// Consistent thinking state used by legacy and secondary chat surfaces.
class ThinkingIndicator extends StatelessWidget {
  final String message;

  const ThinkingIndicator({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF38BDF8).withOpacity(.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AgentPulseDot(size: 8),
          const SizedBox(width: 10),
          const AgentThinkingDots(),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              message,
              style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
