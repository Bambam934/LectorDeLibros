import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/reading_preferences.dart';
import '../../domain/repositories/preferences_repository.dart';

class LocalPreferencesRepository implements PreferencesRepository {
  static const _kFontFamily = 'reading.font_family';
  static const _kFontSize = 'reading.font_size';
  static const _kLineHeight = 'reading.line_height';
  static const _kLetterSpacing = 'reading.letter_spacing';
  static const _kMaxColumnWidth = 'reading.max_column_width';
  static const _kPalette = 'reading.palette';
  static const _kJustifyText = 'reading.justify_text';

  @override
  Future<ReadingPreferences> load() async {
    final prefs = await SharedPreferences.getInstance();

    final familyName = prefs.getString(_kFontFamily);
    final family = ReadingFontFamily.values.firstWhere(
      (e) => e.name == familyName,
      orElse: () => ReadingFontFamily.serif,
    );

    final paletteName = prefs.getString(_kPalette);
    final palette = ReadingPalette.values.firstWhere(
      (e) => e.name == paletteName,
      orElse: () => ReadingPalette.followApp,
    );

    return ReadingPreferences(
      fontFamily: family,
      fontSize: prefs.getDouble(_kFontSize) ?? 18.0,
      lineHeight: prefs.getDouble(_kLineHeight) ?? 1.7,
      letterSpacing: prefs.getDouble(_kLetterSpacing) ?? 0.0,
      maxColumnWidth: (prefs.getDouble(_kMaxColumnWidth) ?? 720.0) < 0
          ? double.infinity
          : (prefs.getDouble(_kMaxColumnWidth) ?? 720.0),
      palette: palette,
      justifyText: prefs.getBool(_kJustifyText) ?? true,
    );
  }

  @override
  Future<void> save(ReadingPreferences p) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kFontFamily, p.fontFamily.name);
    await prefs.setDouble(_kFontSize, p.fontSize);
    await prefs.setDouble(_kLineHeight, p.lineHeight);
    await prefs.setDouble(_kLetterSpacing, p.letterSpacing);
    await prefs.setDouble(_kMaxColumnWidth,
        p.maxColumnWidth.isFinite ? p.maxColumnWidth : -1.0);
    await prefs.setString(_kPalette, p.palette.name);
    await prefs.setBool(_kJustifyText, p.justifyText);
  }
}
