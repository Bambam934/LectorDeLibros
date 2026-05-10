import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

/// Per-paragraph palette and typography options for the reader screen.
enum ReadingPalette {
  followApp,   // uses Theme.of(context) colors
  paper,       // bright cream + dark brown
  sepia,       // tan + brown
  solarized,   // beige + olive grey
  midnight,    // deep ink + warm cream
  forest,      // dark green + cream
}

enum ReadingFontFamily {
  serif,    // Georgia-like
  sansSerif,// system sans
  mono,     // monospace, useful for poetry/code
}

class ReadingPreferences extends Equatable {
  const ReadingPreferences({
    this.fontFamily = ReadingFontFamily.serif,
    this.fontSize = 18.0,
    this.lineHeight = 1.65,
    this.letterSpacing = 0.0,
    this.maxColumnWidth = 720.0,
    this.palette = ReadingPalette.followApp,
    this.justifyText = true,
  });

  final ReadingFontFamily fontFamily;
  final double fontSize;       // 14 – 32
  final double lineHeight;     // 1.3 – 2.2
  final double letterSpacing;  // 0 – 1.5
  final double maxColumnWidth; // 480, 600, 720, double.infinity
  final ReadingPalette palette;
  final bool justifyText;

  ReadingPreferences copyWith({
    ReadingFontFamily? fontFamily,
    double? fontSize,
    double? lineHeight,
    double? letterSpacing,
    double? maxColumnWidth,
    ReadingPalette? palette,
    bool? justifyText,
  }) {
    return ReadingPreferences(
      fontFamily: fontFamily ?? this.fontFamily,
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      letterSpacing: letterSpacing ?? this.letterSpacing,
      maxColumnWidth: maxColumnWidth ?? this.maxColumnWidth,
      palette: palette ?? this.palette,
      justifyText: justifyText ?? this.justifyText,
    );
  }

  String get fontFamilyName {
    switch (fontFamily) {
      case ReadingFontFamily.serif:
        return 'serif';
      case ReadingFontFamily.sansSerif:
        return 'sans-serif';
      case ReadingFontFamily.mono:
        return 'monospace';
    }
  }

  TextAlign get textAlign =>
      justifyText ? TextAlign.justify : TextAlign.left;

  @override
  List<Object?> get props => [
    fontFamily,
    fontSize,
    lineHeight,
    letterSpacing,
    maxColumnWidth,
    palette,
    justifyText,
  ];
}

/// Resolves the (background, foreground) pair for a [ReadingPalette],
/// taking the app theme into account when [ReadingPalette.followApp].
class ReadingPaletteColors {
  const ReadingPaletteColors({
    required this.background,
    required this.foreground,
    required this.accent,
  });

  final Color background;
  final Color foreground;
  final Color accent;

  static ReadingPaletteColors resolve(
    ReadingPalette palette,
    ColorScheme scheme,
  ) {
    switch (palette) {
      case ReadingPalette.followApp:
        return ReadingPaletteColors(
          background: scheme.surface,
          foreground: scheme.onSurface,
          accent: scheme.primary,
        );
      case ReadingPalette.paper:
        return const ReadingPaletteColors(
          background: Color(0xFFFBF7F0),
          foreground: Color(0xFF1F1611),
          accent: Color(0xFFB45309),
        );
      case ReadingPalette.sepia:
        return const ReadingPaletteColors(
          background: Color(0xFFF4ECD8),
          foreground: Color(0xFF5C4B37),
          accent: Color(0xFF8B5A2B),
        );
      case ReadingPalette.solarized:
        return const ReadingPaletteColors(
          background: Color(0xFFFDF6E3),
          foreground: Color(0xFF586E75),
          accent: Color(0xFF268BD2),
        );
      case ReadingPalette.midnight:
        return const ReadingPaletteColors(
          background: Color(0xFF0E1116),
          foreground: Color(0xFFF5F1E8),
          accent: Color(0xFFF59E0B),
        );
      case ReadingPalette.forest:
        return const ReadingPaletteColors(
          background: Color(0xFF1F2D1F),
          foreground: Color(0xFFD4C8A1),
          accent: Color(0xFFE8B547),
        );
    }
  }
}
