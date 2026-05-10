import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/reading_preferences.dart';
import '../../domain/repositories/preferences_repository.dart';

class PreferencesCubit extends Cubit<ReadingPreferences> {
  PreferencesCubit({required PreferencesRepository repository})
    : _repository = repository,
      super(const ReadingPreferences()) {
    _hydrate();
  }

  final PreferencesRepository _repository;

  Future<void> _hydrate() async {
    final loaded = await _repository.load();
    emit(loaded);
  }

  void _update(ReadingPreferences next) {
    emit(next);
    _repository.save(next);
  }

  void setFontFamily(ReadingFontFamily family) =>
      _update(state.copyWith(fontFamily: family));

  void setFontSize(double size) =>
      _update(state.copyWith(fontSize: size.clamp(14.0, 32.0)));

  void setLineHeight(double height) =>
      _update(state.copyWith(lineHeight: height.clamp(1.3, 2.4)));

  void setLetterSpacing(double spacing) =>
      _update(state.copyWith(letterSpacing: spacing.clamp(0.0, 1.5)));

  void setMaxColumnWidth(double width) =>
      _update(state.copyWith(maxColumnWidth: width));

  void setPalette(ReadingPalette palette) =>
      _update(state.copyWith(palette: palette));

  void setJustifyText(bool justify) =>
      _update(state.copyWith(justifyText: justify));

  void resetToDefaults() => _update(const ReadingPreferences());
}
