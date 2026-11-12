import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/giant_palette.dart';

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
                color: GiantPalette.primaryLight,
                boxShadow: [
                  BoxShadow(
                    color: GiantPalette.primaryLight.withOpacity(.16 + value * .28),
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

/// Four teal dots continuously trade places through a rotating, breathing orbit.
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
    duration: const Duration(milliseconds: 1900),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 28,
        height: 28,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final phase = _controller.value * 2 * math.pi;
            return Stack(
              alignment: Alignment.center,
              children: List.generate(4, (index) {
                final baseAngle = index * math.pi / 2;
                // Each dot speeds inward and outward at a different moment,
                // so they exchange places instead of behaving like a rigid
                // four-point diamond.
                final angle = phase + baseAngle +
                    .34 * math.sin(phase * 2 - baseAngle);
                final radius = 7.2 + 2.1 * math.sin(phase * 2 + baseAngle);
                final emphasis =
                    (1 + math.sin(phase * 2 - baseAngle + math.pi / 2)) / 2;
                final scale = .72 + emphasis * .48;
                return Transform.translate(
                  offset: Offset(
                    radius * math.cos(angle),
                    radius * math.sin(angle),
                  ),
                  child: Transform.scale(
                    scale: scale,
                    child: Container(
                      width: widget.dotSize,
                      height: widget.dotSize,
                      decoration: BoxDecoration(
                        color: GiantPalette.primaryLight
                            .withOpacity(.52 + emphasis * .48),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: GiantPalette.primaryLight
                                .withOpacity(.10 + emphasis * .24),
                            blurRadius: 2 + emphasis * 4,
                            spreadRadius: emphasis * .35,
                          ),
                        ],
                      ),
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
            final split = widget.shimmerFrom.clamp(0, widget.text.length).toInt();
            final prefix = widget.text.substring(0, split);
            final newest = widget.text.substring(split);
            final position = -1.5 + _controller.value * 3;
            final shader = LinearGradient(
              begin: Alignment(position - .45, 0),
              end: Alignment(position + .45, 0),
              colors: const [
                GiantPalette.muted,
                GiantPalette.text,
                GiantPalette.primaryLight,
                GiantPalette.muted,
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
