import 'package:flutter/material.dart';
class ProTheme {
 ProTheme._();
 static const bgDark=Color(0xFF0A0F0D), bgCard=Color(0xFF111815), neonGreen=Color(0xFF00FF88), neonGreenDim=Color(0xFF00CC6A), electricBlue=Color(0xFF00B4D8), dangerRed=Color(0xFFFF5577), textPrimary=Color(0xFFE0E8E3), textSecondary=Color(0xFF88998F);
 static const fontFamily='Roboto', monoFont='monospace';
 static const bgGradient=LinearGradient(begin:Alignment.topLeft,end:Alignment.bottomRight,colors:[Color(0xFF101B15),bgDark]);
 static const cardGradient=LinearGradient(begin:Alignment.topLeft,end:Alignment.bottomRight,colors:[Color(0xFF18251D),bgCard]);
 static List<BoxShadow> glowShadow({double opacity=.18})=>[BoxShadow(color:neonGreen.withOpacity(opacity),blurRadius:16,spreadRadius:1)];
}
