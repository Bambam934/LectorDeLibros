import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Global Material 3 theme for LectorSync.
///
/// Two seeded schemes (warm cream / midnight ink), polished input + button
/// shapes, opinionated typography. The reader's per-paragraph palette is
/// configured separately via `ReadingPreferences`.
abstract final class AppTheme {
  static const _radiusS = 8.0;
  static const _radiusM = 12.0;
  static const _radiusL = 16.0;

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.brandAmber,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppColors.brandAmber,
      secondary: AppColors.brandIndigo,
      tertiary: AppColors.brandTeal,
      surface: AppColors.cream,
      surfaceContainerHighest: AppColors.creamSurface,
      outlineVariant: AppColors.creamBorder,
      onSurface: AppColors.inkBrown,
      onSurfaceVariant: AppColors.inkBrownSoft,
    );
    return _baseTheme(scheme).copyWith(
      scaffoldBackgroundColor: AppColors.cream,
    );
  }

  static ThemeData get dark {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.brandAmberSoft,
      brightness: Brightness.dark,
    ).copyWith(
      primary: AppColors.brandAmberSoft,
      secondary: AppColors.brandIndigoSoft,
      tertiary: const Color(0xFF22D3EE),
      surface: AppColors.charcoal,
      surfaceContainerHighest: AppColors.charcoalElevated,
      outlineVariant: AppColors.charcoalBorder,
      onSurface: AppColors.warmCream,
      onSurfaceVariant: AppColors.warmCreamSoft,
    );
    return _baseTheme(scheme).copyWith(
      scaffoldBackgroundColor: AppColors.midnight,
    );
  }

  static ThemeData _baseTheme(ColorScheme scheme) {
    final isDark = scheme.brightness == Brightness.dark;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      splashFactory: InkSparkle.splashFactory,

      // ── Typography ──
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontWeight: FontWeight.w700,
          letterSpacing: -1.2,
          height: 1.1,
        ),
        displayMedium: TextStyle(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.8,
          height: 1.15,
        ),
        headlineLarge: TextStyle(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
          height: 1.2,
        ),
        headlineMedium: TextStyle(
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
        ),
        headlineSmall: TextStyle(fontWeight: FontWeight.w600),
        titleLarge: TextStyle(fontWeight: FontWeight.w600, letterSpacing: -0.2),
        titleMedium: TextStyle(fontWeight: FontWeight.w600),
        labelLarge: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.4),
      ).apply(
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
      ),

      // ── App bar ──
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
      ),

      // ── Cards ──
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerHighest,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radiusL),
          side: BorderSide(color: scheme.outlineVariant, width: 0.5),
        ),
        clipBehavior: Clip.antiAlias,
      ),

      // ── Inputs ──
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radiusM),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radiusM),
          borderSide: BorderSide(color: scheme.outlineVariant, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radiusM),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radiusM),
          borderSide: BorderSide(color: scheme.error, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radiusM),
          borderSide: BorderSide(color: scheme.error, width: 1.5),
        ),
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
        prefixIconColor: scheme.onSurfaceVariant,
      ),

      // ── Buttons ──
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_radiusM),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_radiusM),
          ),
          side: BorderSide(color: scheme.outlineVariant, width: 1.2),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_radiusS),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_radiusS),
          ),
        ),
      ),

      // ── Bottom sheet ──
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: isDark ? 0 : 12,
        modalElevation: isDark ? 0 : 12,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        showDragHandle: true,
        dragHandleColor: scheme.outlineVariant,
      ),

      // ── Dialog ──
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radiusL),
        ),
      ),

      // ── Snack bar ──
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radiusM),
        ),
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface),
      ),

      // ── Divider ──
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 0.5,
        space: 0,
      ),

      // ── Chip ──
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHighest,
        selectedColor: scheme.primaryContainer,
        side: BorderSide(color: scheme.outlineVariant, width: 0.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radiusS),
        ),
        labelStyle: TextStyle(
          color: scheme.onSurface,
          fontWeight: FontWeight.w500,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),

      // ── Slider ──
      sliderTheme: SliderThemeData(
        activeTrackColor: scheme.primary,
        inactiveTrackColor: scheme.surfaceContainerHighest,
        thumbColor: scheme.primary,
        overlayColor: scheme.primary.withAlpha(30),
        trackHeight: 4,
      ),

      // ── Progress ──
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearMinHeight: 3,
      ),

      // ── List tile ──
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radiusM),
        ),
        selectedColor: scheme.primary,
        selectedTileColor: scheme.primaryContainer.withAlpha(50),
      ),
    );
  }
}
