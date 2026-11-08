import 'dart:math' as math;
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

/// Four cyan dots orbit one another in a rotating diamond while the agent thinks.
class AgentThinkingDots extends StatefulWidget {
  const AgentThinkingDots({super.key, this.dotSize = 5.5});
  final double dotSize;

  @override
  State<AgentThinkingDots> createState() => _AgentThinkingDotsState();
}

class _AgentThinkingDotsState extends State<AgentThinkingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1250),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 26,
        height: 26,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final rotation = _controller.value * 2 * math.pi;
            const orbitRadius = 8.0;
            return Stack(
              alignment: Alignment.center,
              children: List.generate(4, (index) {
                final angle = rotation + index * math.pi / 2;
                final emphasis = (1 + math.sin(angle + math.pi / 2)) / 2;
                return Transform.translate(
                  offset: Offset(
                    orbitRadius * math.cos(angle),
                    orbitRadius * math.sin(angle),
                  ),
                  child: Container(
                    width: widget.dotSize,
                    height: widget.dotSize,
                    decoration: BoxDecoration(
                      color: const Color(0xFF38BDF8)
                          .withOpacity(.58 + emphasis * .42),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF38BDF8)
                              .withOpacity(.12 + emphasis * .2),
                          blurRadius: 2 + emphasis * 3,
                        ),
                      ],
                    ),
                  ),
                );
              }),
            );
          },
        ),
      );
}


/// Shimmers only the newest streamed segment; previous generated text settles.
class AgentStreamingText extends StatefulWidget {
  const AgentStreamingText(
    this.text, {
    super.key,
    required this.shimmerFrom,
    required this.style,
    this.maxLines,
    this.selectable = false,
  });

  final String text;
  final int shimmerFrom;
  final TextStyle style;
  final int? maxLines;
  final bool selectable;

  @override
  State<AgentStreamingText> createState() => _AgentStreamingTextState();
}

class _AgentStreamingTextState extends State<AgentStreamingText>
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
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final split = widget.shimmerFrom.clamp(0, widget.text.length);
            final prefix = widget.text.substring(0, split);
            final newest = widget.text.substring(split);
            final position = -1.5 + _controller.value * 3;
            final shader = LinearGradient(
              begin: Alignment(position - .45, 0),
              end: Alignment(position + .45, 0),
              colors: const [
                Color(0xFF9CA3AF),
                Color(0xFFFFFFFF),
                Color(0xFF38BDF8),
                Color(0xFF9CA3AF),
              ],
              stops: const [0, .42, .58, 1],
            ).createShader(Rect.fromLTWH(
              0,
              0,
              constraints.maxWidth.isFinite ? constraints.maxWidth : 600,
              (widget.style.fontSize ?? 14) * 2.2,
            ));
            final spans = TextSpan(
              children: [
                if (prefix.isNotEmpty)
                  TextSpan(text: prefix, style: widget.style),
                if (newest.isNotEmpty)
                  TextSpan(
                    text: newest,
                    style: widget.style.copyWith(
                      foreground: Paint()..shader = shader,
                    ),
                  ),
              ],
            );
            return widget.selectable
                ? SelectableText.rich(spans, maxLines: widget.maxLines)
                : Text.rich(
                    spans,
                    maxLines: widget.maxLines,
                    overflow: widget.maxLines == null
                        ? TextOverflow.visible
                        : TextOverflow.ellipsis,
                  );
          },
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
