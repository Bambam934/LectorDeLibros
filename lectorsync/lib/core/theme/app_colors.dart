import 'package:flutter/material.dart';

/// Brand palette for LectorSync.
///
/// Inspired by candlelight reading + audio waves: warm amber for the brand,
/// deep indigo for audio accent, sepia/cream surfaces for paper feel.
abstract final class AppColors {
  // ── Brand ──
  static const Color brandAmber = Color(0xFFB45309); // amber-700, copper warmth
  static const Color brandAmberSoft = Color(0xFFF59E0B); // amber-500, dark mode
  static const Color brandIndigo = Color(0xFF4F46E5); // indigo-600
  static const Color brandIndigoSoft = Color(0xFF818CF8); // indigo-400, dark mode
  static const Color brandTeal = Color(0xFF0E7490); // cyan-700, audio accent

  // ── Light surfaces (paper / cream) ──
  static const Color cream = Color(0xFFFBF7F0);
  static const Color paperWhite = Color(0xFFFFFFFF);
  static const Color creamSurface = Color(0xFFF5EFE3);
  static const Color creamBorder = Color(0xFFE8DDC9);
  static const Color inkBrown = Color(0xFF1F1611);
  static const Color inkBrownSoft = Color(0xFF5C4B37);

  // ── Dark surfaces (midnight ink) ──
  static const Color midnight = Color(0xFF0E1116);
  static const Color charcoal = Color(0xFF171B22);
  static const Color charcoalElevated = Color(0xFF1F2530);
  static const Color charcoalBorder = Color(0xFF2A3140);
  static const Color warmCream = Color(0xFFF5F1E8);
  static const Color warmCreamSoft = Color(0xFFB8B0A0);

  // ── Reader-specific palettes ──
  static const Color sepiaBackground = Color(0xFFF4ECD8);
  static const Color sepiaText = Color(0xFF5C4B37);
  static const Color solarizedBackground = Color(0xFFFDF6E3);
  static const Color solarizedText = Color(0xFF586E75);
  static const Color forestBackground = Color(0xFF1F2D1F);
  static const Color forestText = Color(0xFFD4C8A1);

  // ── Semantic ──
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFEF4444);
}
