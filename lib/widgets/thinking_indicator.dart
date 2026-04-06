import 'package:flutter/material.dart';

class ThinkingIndicator extends StatefulWidget {
  final String message;

  const ThinkingIndicator({super.key, required this.message});

  @override
  State<ThinkingIndicator> createState() => _ThinkingIndicatorState();
}

class _ThinkingIndicatorState extends State<ThinkingIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade800,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.deepPurple.shade300, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Row(
                children: [
                  _buildDot(0),
                  const SizedBox(width: 4),
                  _buildDot(1),
                  const SizedBox(width: 4),
                  _buildDot(2),
                ],
              );
            },
          ),
          const SizedBox(width: 12),
          Text(
            widget.message,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildDot(int index) {
    final value = (_controller.value * 3 + index) % 3;
    final opacity = value < 1 ? value : 2 - value;
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        color: Colors.deepPurple.withOpacity(opacity.clamp(0.3, 1.0)),
        shape: BoxShape.circle,
      ),
    );
  }
}
