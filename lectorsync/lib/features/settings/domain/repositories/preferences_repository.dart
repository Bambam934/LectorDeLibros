import '../entities/reading_preferences.dart';

abstract interface class PreferencesRepository {
  Future<ReadingPreferences> load();
  Future<void> save(ReadingPreferences preferences);
}
