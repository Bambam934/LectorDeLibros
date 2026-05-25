import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Centralised haptic feedback helpers. The Flutter framework safely
/// no-ops on platforms that don't support haptics (desktop, web), so
/// these helpers can be called everywhere without platform checks.
abstract final class Haptics {
  /// Light tick — buttons, toggles, slider stops.
  static void light() {
    if (kIsWeb) return; // Skip on web (would do nothing anyway).
    HapticFeedback.lightImpact();
  }

  /// Medium tap — primary actions (TTS play, chapter nav).
  static void medium() {
    if (kIsWeb) return;
    HapticFeedback.mediumImpact();
  }

  /// Selection change — slider movement, picker selection.
  static void selection() {
    if (kIsWeb) return;
    HapticFeedback.selectionClick();
  }

  /// Heavy thump — destructive actions, errors.
  static void heavy() {
    if (kIsWeb) return;
    HapticFeedback.heavyImpact();
  }
}
