import 'package:flutter/material.dart';

/// Shared, low-cost activity indicators for the agent UI.
class AgentPulseDot extends StatefulWidget {
  const AgentPulseDot({super.key, this.size = 9});
  final double size;

  @override
  State<AgentPulseDot> createState() => _AgentPulseDotState();
}

class _AgentPulseDotState extends State<AgentPulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final value = Curves.easeInOut.transform(_controller.value);
          return Transform.scale(
            scale: .72 + value * .48,
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF38BDF8),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF38BDF8).withOpacity(.16 + value * .28),
                    blurRadius: 4 + value * 5,
                    spreadRadius: value,
                  ),
                ],
              ),
            ),
          );
        },
      );
}

/// Three blue dots pulse in sequence while the model is thinking.
class AgentThinkingDots extends StatefulWidget {
  const AgentThinkingDots({super.key, this.dotSize = 6});
  final double dotSize;

  @override
  State<AgentThinkingDots> createState() => _AgentThinkingDotsState();
}

class _AgentThinkingDotsState extends State<AgentThinkingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1050),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 34,
        height: 18,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) => Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(3, (index) {
              final phase = (_controller.value - index * .18) % 1.0;
              final wave =
                  (1 - (phase - .32).abs() / .32).clamp(0.0, 1.0).toDouble();
              return Transform.scale(
                scale: .65 + wave * .55,
                child: Container(
                  width: widget.dotSize,
                  height: widget.dotSize,
                  decoration: BoxDecoration(
                    color: const Color(0xFF38BDF8)
                        .withOpacity(.42 + wave * .58),
                    shape: BoxShape.circle,
                  ),
                ),
              );
            }),
          ),
        ),
      );

}

/// Moving highlight for text that is still being produced.
class AgentShimmerText extends StatefulWidget {
  const AgentShimmerText(
    this.text, {
    super.key,
    required this.style,
    this.maxLines,
    this.selectable = false,
  });

  final String text;
  final TextStyle style;
  final int? maxLines;
  final bool selectable;

  @override
  State<AgentShimmerText> createState() => _AgentShimmerTextState();
}

class _AgentShimmerTextState extends State<AgentShimmerText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1650),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final position = -1.5 + _controller.value * 3;
          return ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (bounds) => LinearGradient(
              begin: Alignment(position - .45, 0),
              end: Alignment(position + .45, 0),
              colors: const [
                Color(0xFF9CA3AF),
                Color(0xFFFFFFFF),
                Color(0xFF38BDF8),
                Color(0xFF9CA3AF),
              ],
              stops: const [0, .42, .58, 1],
            ).createShader(bounds),
            child: widget.selectable
                ? SelectableText(widget.text, style: widget.style)
                : Text(
                    widget.text,
                    maxLines: widget.maxLines,
                    overflow: widget.maxLines == null
                        ? TextOverflow.visible
                        : TextOverflow.ellipsis,
                    style: widget.style,
                  ),
          );
        },
      );
}
