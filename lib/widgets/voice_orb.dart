import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

/// Voice interaction states shared by the chat voice overlay.
enum AgentState {
  idle,
  listening,
  thinking,
  speaking,
  error,
}

/// Animated visual indicator for the voice assistant state.
class GlowingOrb extends StatefulWidget {
  const GlowingOrb({super.key, required this.state, this.size = 230});
  final AgentState state;
  final double size;

  @override
  State<GlowingOrb> createState() => _GlowingOrbState();
}

class _GlowingOrbState extends State<GlowingOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this);

  Duration get _period {
    switch (widget.state) {
      case AgentState.idle:
        return const Duration(seconds: 12);
      case AgentState.listening:
        return const Duration(seconds: 7);
      case AgentState.thinking:
        return const Duration(milliseconds: 4500);
      case AgentState.speaking:
        return const Duration(seconds: 3);
      case AgentState.error:
        return const Duration(seconds: 2);
    }
  }

  String get _semanticLabel {
    switch (widget.state) {
      case AgentState.idle:
        return 'المساعد الصوتي جاهز';
      case AgentState.listening:
        return 'المساعد يستمع';
      case AgentState.thinking:
        return 'المساعد يعالج طلبك';
      case AgentState.speaking:
        return 'المساعد يتحدث';
      case AgentState.error:
        return 'حالة خطأ في المساعد';
    }
  }

  void _syncToVoiceState() {
    _controller
      ..stop()
      ..repeat(period: _period, reverse: widget.state == AgentState.error);
  }

  @override
  void didUpdateWidget(covariant GlowingOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) _syncToVoiceState();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
        label: _semanticLabel,
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: Lottie.asset(
            'assets/animations/voice_orb.json',
            controller: _controller,
            fit: BoxFit.contain,
            repeat: true,
            animate: true,
            frameRate: FrameRate.max,
            onLoaded: (_) => _syncToVoiceState(),
            errorBuilder: (context, error, stackTrace) => const Center(
              child: Icon(
                Icons.graphic_eq_rounded,
                color: Colors.white70,
                size: 54,
              ),
            ),
          ),
        ),
      );
}
