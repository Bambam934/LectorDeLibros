import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Extended theme mode that adds time-based auto + warm night reading.
enum AppThemeMode {
  /// Follow device system setting.
  system,

  /// Always light.
  light,

  /// Always dark (cool charcoal).
  dark,

  /// Warm dark (amber/sepia-tinted, reduces blue light at night).
  warm,

  /// Auto-switch based on time of day (dark 20:00–07:00).
  scheduled,
}

/// State exposed to the app: contains both the Material ThemeMode (for
/// the framework) and the app-level mode (for which theme variant to
/// pass to MaterialApp).
class ThemeState extends Equatable {
  const ThemeState({required this.themeMode, required this.appMode});

  final ThemeMode themeMode;
  final AppThemeMode appMode;

  bool get isWarm => appMode == AppThemeMode.warm;

  ThemeState copyWith({ThemeMode? themeMode, AppThemeMode? appMode}) {
    return ThemeState(
      themeMode: themeMode ?? this.themeMode,
      appMode: appMode ?? this.appMode,
    );
  }

  @override
  List<Object> get props => [themeMode, appMode];
}

/// Persists the user's preferred theme mode and emits the effective
/// [ThemeState] for MaterialApp.
class ThemeCubit extends Cubit<ThemeState> {
  ThemeCubit()
      : super(const ThemeState(
          themeMode: ThemeMode.system,
          appMode: AppThemeMode.system,
        )) {
    _load();
  }

  static const _key = 'theme_mode';

  Timer? _scheduleTimer;

  AppThemeMode get appMode => state.appMode;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_key);
    switch (value) {
      case 'light':
        emit(const ThemeState(
            themeMode: ThemeMode.light, appMode: AppThemeMode.light));
      case 'dark':
        emit(const ThemeState(
            themeMode: ThemeMode.dark, appMode: AppThemeMode.dark));
      case 'warm':
        // Warm uses ThemeMode.dark to trigger MaterialApp.darkTheme,
        // but app.dart swaps in AppTheme.warm based on appMode.
        emit(const ThemeState(
            themeMode: ThemeMode.dark, appMode: AppThemeMode.warm));
      case 'scheduled':
        emit(const ThemeState(
            themeMode: ThemeMode.system, appMode: AppThemeMode.scheduled));
        _startSchedule();
      default:
        emit(const ThemeState(
            themeMode: ThemeMode.system, appMode: AppThemeMode.system));
    }
  }

  Future<void> setAppMode(AppThemeMode mode) async {
    _scheduleTimer?.cancel();
    _scheduleTimer = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);

    switch (mode) {
      case AppThemeMode.system:
        emit(const ThemeState(
            themeMode: ThemeMode.system, appMode: AppThemeMode.system));
      case AppThemeMode.light:
        emit(const ThemeState(
            themeMode: ThemeMode.light, appMode: AppThemeMode.light));
      case AppThemeMode.dark:
        emit(const ThemeState(
            themeMode: ThemeMode.dark, appMode: AppThemeMode.dark));
      case AppThemeMode.warm:
        emit(const ThemeState(
            themeMode: ThemeMode.dark, appMode: AppThemeMode.warm));
      case AppThemeMode.scheduled:
        emit(state.copyWith(appMode: AppThemeMode.scheduled));
        _startSchedule();
    }
  }

  /// Legacy setter for backward compatibility.
  Future<void> setMode(ThemeMode mode) async {
    final appMode = switch (mode) {
      ThemeMode.system => AppThemeMode.system,
      ThemeMode.light => AppThemeMode.light,
      ThemeMode.dark => AppThemeMode.dark,
    };
    await setAppMode(appMode);
  }

  /// Cycles system → light → dark → warm → scheduled → system.
  Future<void> cycle() async {
    final next = switch (state.appMode) {
      AppThemeMode.system => AppThemeMode.light,
      AppThemeMode.light => AppThemeMode.dark,
      AppThemeMode.dark => AppThemeMode.warm,
      AppThemeMode.warm => AppThemeMode.scheduled,
      AppThemeMode.scheduled => AppThemeMode.system,
    };
    await setAppMode(next);
  }

  /// Dark between 20:00 and 07:00.
  void _startSchedule() {
    _emitForCurrentTime();
    // Re-check every minute.
    _scheduleTimer?.cancel();
    _scheduleTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _emitForCurrentTime(),
    );
  }

  void _emitForCurrentTime() {
    final hour = DateTime.now().hour;
    final isDark = hour >= 20 || hour < 7;
    emit(state.copyWith(
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
    ));
  }

  @override
  Future<void> close() {
    _scheduleTimer?.cancel();
    return super.close();
  }
}
