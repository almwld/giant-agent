import 'package:flutter/material.dart';

enum AgentState { idle, listening, thinking, speaking, error }

class GlowingOrb extends StatefulWidget {
  const GlowingOrb({super.key, required this.state, this.size = 230});
  final AgentState state;
  final double size;

  @override
  State<GlowingOrb> createState() => _GlowingOrbState();
}

class _GlowingOrbState extends State<GlowingOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = switch (widget.state) {
      AgentState.error => const Color(0xFFEF4444),
      AgentState.thinking => const Color(0xFF818CF8),
      AgentState.speaking => const Color(0xFF22D3EE),
      AgentState.listening => const Color(0xFF14B8A6),
      AgentState.idle => const Color(0xFF0EA5E9),
    };
    return Semantics(
      label: 'Voice assistant ' + widget.state.name,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final pulse = 0.92 + (_controller.value * 0.12);
          return SizedBox(
            width: widget.size,
            height: widget.size,
            child: Transform.scale(
              scale: pulse,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: widget.size * .98,
                    height: widget.size * .98,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          accent.withOpacity(.05),
                          accent.withOpacity(.18),
                          accent.withOpacity(.02),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    width: widget.size * .78,
                    height: widget.size * .78,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        center: const Alignment(-.28, -.35),
                        colors: [
                          Colors.white.withOpacity(.72),
                          accent.withOpacity(.88),
                          const Color(0xFF101827),
                        ],
                        stops: const [0, .28, 1],
                      ),
                      border: Border.all(
                        color: Colors.white.withOpacity(.28),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: accent.withOpacity(.38 + _controller.value * .18),
                          blurRadius: 34 + _controller.value * 18,
                          spreadRadius: 2 + _controller.value * 5,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Icon(
                        widget.state == AgentState.listening
                            ? Icons.graphic_eq_rounded
                            : widget.state == AgentState.thinking
                                ? Icons.auto_awesome_rounded
                                : widget.state == AgentState.speaking
                                    ? Icons.volume_up_rounded
                                    : Icons.mic_rounded,
                        color: Colors.white.withOpacity(.94),
                        size: widget.size * .22,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
