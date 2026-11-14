import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Holds the active chat-owned orb widget above the root Navigator. Keeping
/// this host at MaterialApp.builder lets the orb remain visible while the user
/// moves between the chat and any AgentsOS screen.
class GlobalVoiceOrbOverlayBridge {
  GlobalVoiceOrbOverlayBridge._();

  static final ValueNotifier<Widget?> _overlay = ValueNotifier<Widget?>(null);

  static void show(Widget overlay) => _overlay.value = overlay;

  static void hide() => _overlay.value = null;

  static ValueListenable<Widget?> get listenable => _overlay;
}

class GlobalVoiceOrbOverlayHost extends StatelessWidget {
  const GlobalVoiceOrbOverlayHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Widget?>(
      valueListenable: GlobalVoiceOrbOverlayBridge.listenable,
      builder: (context, overlay, _) => Stack(
        fit: StackFit.expand,
        children: [
          child,
          if (overlay != null) overlay,
        ],
      ),
    );
  }
}
