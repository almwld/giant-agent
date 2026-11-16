import 'package:flutter/material.dart';
import 'giant_palette.dart';

/// Compatibility facade for existing AgentsOS widgets.
/// All six control surfaces share the exact palette used by ChatScreen.
class ProTheme {
  ProTheme._();

  static const bgDark = GiantPalette.background;
  static const bgCard = GiantPalette.surface;
  static const neonGreen = GiantPalette.primary;
  static const neonGreenDim = GiantPalette.primaryLight;
  static const electricBlue = Color(0xFF1A73E8);
  static const dangerRed = GiantPalette.danger;
  static const textPrimary = GiantPalette.text;
  static const textSecondary = GiantPalette.muted;
  static const fontFamily = 'Roboto';
  static const monoFont = 'monospace';

  static const bgGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [GiantPalette.background, GiantPalette.background],
  );

  static const cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [GiantPalette.surface, GiantPalette.surface],
  );

  static List<BoxShadow> glowShadow({double opacity = .18}) => const [];
}
