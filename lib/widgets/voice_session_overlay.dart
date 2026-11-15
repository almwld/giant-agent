import 'package:flutter/material.dart';

import '../services/voice_session_controller.dart';
import '../theme/giant_palette.dart';
import 'global_voice_orb_overlay_host.dart';
import 'voice_orb.dart';

/// App-owned voice UI. It is deliberately independent of ChatScreen State so
/// it remains mounted while the user navigates to AgentsOS routes.
class VoiceSessionOverlay extends StatefulWidget {
  const VoiceSessionOverlay({super.key});

  @override
  State<VoiceSessionOverlay> createState() => _VoiceSessionOverlayState();
}

class _VoiceSessionOverlayState extends State<VoiceSessionOverlay> {
  final VoiceSessionController _session = VoiceSessionController.instance;
  bool _compact = false;
  double _compactSize = 112;
  double _offsetY = 0;

  AgentState _orbState(VoiceSessionPhase phase) {
    switch (phase) {
      case VoiceSessionPhase.idle:
        return AgentState.idle;
      case VoiceSessionPhase.listening:
        return AgentState.listening;
      case VoiceSessionPhase.thinking:
        return AgentState.thinking;
      case VoiceSessionPhase.speaking:
        return AgentState.speaking;
      case VoiceSessionPhase.error:
        return AgentState.error;
    }
  }

  String _status(VoiceSessionPhase phase) {
    switch (phase) {
      case VoiceSessionPhase.idle:
        return 'جاهز للاستماع';
      case VoiceSessionPhase.listening:
        return 'أستمع إليك محلياً…';
      case VoiceSessionPhase.thinking:
        return 'أعالج طلبك داخل المحادثة…';
      case VoiceSessionPhase.speaking:
        return 'أجيبك صوتياً…';
      case VoiceSessionPhase.error:
        return 'تعذر إكمال الاتصال الصوتي';
    }
  }

  Future<void> _close() async {
    await _session.stopSession();
    GlobalVoiceOrbOverlayBridge.hide();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VoiceSessionSnapshot>(
      valueListenable: _session.state,
      builder: (context, state, _) {
        if (!state.active) return const SizedBox.shrink();
        final orbState = _orbState(state.phase);
        final status = _status(state.phase);
        if (_compact) {
          return Positioned(
            left: 12,
            right: 12,
            bottom: (106 + _offsetY)
                .clamp(78.0, MediaQuery.of(context).size.height - 180)
                .toDouble(),
            child: SafeArea(
              child: Material(
                color: const Color(0xF0181D29),
                borderRadius: BorderRadius.circular(24),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Row(children: [
                    GestureDetector(
                      onPanUpdate: (d) => setState(() => _offsetY =
                          (_offsetY + d.delta.dy).clamp(-180.0, 180.0).toDouble()),
                      onTap: () => setState(() => _compact = false),
                      child: GlowingOrb(state: orbState, size: _compactSize),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(status, style: const TextStyle(color: Colors.white, fontSize: 12)),
                        if (state.transcript.isNotEmpty)
                          Text(state.transcript, maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: GiantPalette.muted, fontSize: 10)),
                      ],
                    )),
                    IconButton(
                      tooltip: 'تصغير الدائرة',
                      onPressed: () => setState(() =>
                          _compactSize = (_compactSize - 18).clamp(56.0, 112.0).toDouble()),
                      icon: const Icon(Icons.remove_circle_outline_rounded,
                        color: Colors.white70, size: 18)),
                    IconButton(
                      tooltip: 'تكبير الدائرة',
                      onPressed: () => setState(() =>
                          _compactSize = (_compactSize + 18).clamp(56.0, 132.0).toDouble()),
                      icon: const Icon(Icons.add_circle_outline_rounded,
                        color: Colors.white70, size: 18)),
                    IconButton(
                      onPressed: () => setState(() => _compact = false),
                      icon: const Icon(Icons.open_in_full_rounded,
                        color: Colors.white70, size: 18)),
                    IconButton(
                      onPressed: _close,
                      icon: const Icon(Icons.close_rounded,
                        color: Colors.white70, size: 18)),
                  ]),
                ),
              ),
            ),
          );
        }
        return Positioned.fill(
          child: Material(
            color: const Color(0xE610131B),
            child: SafeArea(
              child: Stack(children: [
                Center(child: GestureDetector(
                  onPanUpdate: (d) {
                    if (d.delta.dy.abs() > 2) setState(() {
                      _compact = true;
                      _offsetY = (_offsetY + d.delta.dy)
                          .clamp(-180.0, 180.0).toDouble();
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      GlowingOrb(state: orbState, size: 270),
                      const SizedBox(height: 18),
                      Text(status, textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white,
                          fontSize: 16, fontWeight: FontWeight.w600)),
                      if (state.transcript.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(state.transcript, maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFFCBD5E1),
                            fontSize: 13, height: 1.5)),
                      ],
                      const SizedBox(height: 14),
                      if (state.phase == VoiceSessionPhase.speaking)
                        FilledButton.tonalIcon(
                          onPressed: _session.interruptAndListen,
                          icon: const Icon(Icons.hearing_rounded),
                          label: const Text('قاطعني — استمع الآن')),
                      if (state.phase == VoiceSessionPhase.listening &&
                          (state.isListening || state.transcript.isNotEmpty))
                        FilledButton.icon(
                          onPressed: _session.requestFinish,
                          icon: const Icon(Icons.send_rounded),
                          label: Text(state.isListening
                              ? 'انتهيت — أرسل كلامي'
                              : 'أرسل النص إلى المحادثة')),
                      const SizedBox(height: 8),
                      const Text('التعرف على الكلام يعمل على الجهاز',
                        style: TextStyle(color: GiantPalette.muted, fontSize: 11)),
                    ]),
                  ),
                )),
                PositionedDirectional(top: 12, end: 12, child: Row(children: [
                  IconButton.filledTonal(
                    tooltip: 'تصغير المساعد الصوتي',
                    onPressed: () => setState(() => _compact = true),
                    icon: const Icon(Icons.picture_in_picture_alt_rounded)),
                  IconButton.filledTonal(
                    tooltip: 'إيقاف المساعد الصوتي',
                    onPressed: _close,
                    icon: const Icon(Icons.close_rounded)),
                ])),
              ]),
            ),
          ),
        );
      },
    );
  }
}
