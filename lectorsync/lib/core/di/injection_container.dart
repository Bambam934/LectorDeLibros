import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/network/api_client.dart';
import '../../core/storage/secure_storage.dart';
import '../../core/sync/client_id_service.dart';
import '../../core/sync/sync_stream_client.dart';
import '../../features/reader/data/repositories/ambient_sound_repository.dart';
import '../../features/reader/data/repositories/bookmark_repository.dart';
import '../../features/reader/data/repositories/chapter_cache_repository.dart';
import '../../features/reader/data/repositories/highlight_repository.dart';
import '../../features/reader/data/repositories/reading_stats_repository.dart';
import '../../features/reader/data/repositories/voice_preset_repository.dart';
import '../../features/auth/data/repositories/local_auth_repository.dart';
import '../../features/auth/data/repositories/remote_auth_repository.dart';
import '../../features/auth/domain/repositories/auth_repository.dart';
import '../../features/auth/presentation/cubit/auth_cubit.dart';
import '../../features/library/data/repositories/book_shelf_repository.dart';
import '../../features/library/data/repositories/local_library_repository.dart';
import '../../features/library/data/repositories/remote_library_repository.dart';
import '../../features/library/domain/repositories/library_repository.dart';
import '../../features/reader/data/repositories/audio_tts_repository.dart';
import '../../features/reader/data/repositories/device_tts_repository.dart';
import '../../features/reader/data/repositories/just_audio_player_repository.dart';
import '../../features/reader/data/repositories/local_reader_repository.dart';
import '../../features/reader/data/repositories/remote_reader_repository.dart';
import '../../features/reader/data/repositories/tts/tts_capabilities.dart';
import '../../features/reader/data/repositories/tts_repository_proxy.dart';
import '../../features/reader/domain/repositories/audio_player_repository.dart';
import '../../features/reader/domain/repositories/reader_repository.dart';
import '../../features/reader/domain/repositories/tts_repository.dart';
import '../../features/settings/data/repositories/local_preferences_repository.dart';
import '../../features/settings/domain/repositories/preferences_repository.dart';

/// Flag de modo offline.
///
/// Cuando es `true` (por defecto mientras no haya backend desplegado),
/// la app usa repositorios locales (LocalAuth / LocalLibrary / LocalReader)
/// y NO depende del servidor para login, biblioteca ni lectura.
///
/// Para activar modo conectado, compilar con:
///   `flutter build apk --dart-define=OFFLINE_MODE=false --dart-define=API_BASE_URL=https://tu-server.com`
const _kOfflineMode = bool.fromEnvironment('OFFLINE_MODE', defaultValue: true);

final _sessionExpiredNotifier = ValueNotifier<bool>(false);

ValueNotifier<bool> get sessionExpiredNotifier => _sessionExpiredNotifier;

enum TtsMode { device, external }

final GetIt sl = GetIt.instance;

const _kTtsModeKey = 'tts_mode';

Future<TtsMode> getTtsMode() async {
  final prefs = await SharedPreferences.getInstance();
  final value = prefs.getString(_kTtsModeKey);
  if (value == 'external') return TtsMode.external;
  return TtsMode.device;
}

Future<void> setTtsMode(TtsMode mode) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_kTtsModeKey, mode.name);
}

const _kVoiceIdKey = 'elevenlabs_voice_id';

Future<String> getSelectedVoiceId() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_kVoiceIdKey) ?? const String.fromEnvironment('ELEVENLABS_VOICE_ID', defaultValue: '');
}

Future<void> setSelectedVoiceId(String voiceId) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_kVoiceIdKey, voiceId);
}

const _kTtsSpeechRateKey = 'tts_speech_rate';

Future<double> getTtsSpeechRate() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getDouble(_kTtsSpeechRateKey) ?? 0.6;
}

Future<void> setTtsSpeechRate(double rate) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setDouble(_kTtsSpeechRateKey, rate.clamp(0.0, 1.0));
}

String get _platformVoiceSuffix {
  if (kIsWeb) return '_web';
  switch (defaultTargetPlatform) {
    case TargetPlatform.windows:
    case TargetPlatform.macOS:
    case TargetPlatform.linux:
      return '_desktop';
    default:
      return '_mobile';
  }
}

final _kNativeVoiceNameKey = 'tts_native_voice_name$_platformVoiceSuffix';
final _kNativeVoiceLocaleKey = 'tts_native_voice_locale$_platformVoiceSuffix';

Future<Map<String, String>?> getNativeVoice() async {
  final prefs = await SharedPreferences.getInstance();
  final name = prefs.getString(_kNativeVoiceNameKey);
  final locale = prefs.getString(_kNativeVoiceLocaleKey);
  if (name == null || locale == null) return null;
  return {'name': name, 'locale': locale};
}

Future<void> setNativeVoice(Map<String, String> voice) async {
  final prefs = await SharedPreferences.getInstance();
  final name = voice['name'];
  final locale = voice['locale'];
  if (name == null || locale == null) return;
  await prefs.setString(_kNativeVoiceNameKey, name);
  await prefs.setString(_kNativeVoiceLocaleKey, locale);
}

Future<void> configureDependencies() async {
  // Core Plugins
  if (!sl.isRegistered<Dio>()) {
    sl.registerLazySingleton<Dio>(Dio.new);
  }
  if (!sl.isRegistered<FlutterSecureStorage>()) {
    sl.registerLazySingleton<FlutterSecureStorage>(
      () => FlutterSecureStorage(
        aOptions: const AndroidOptions(),
        iOptions: const IOSOptions(accessibility: KeychainAccessibility.first_unlock),
        webOptions: kIsWeb
            ? const WebOptions(
                dbName: 'LectorSyncSecureStorage',
                publicKey: 'LectorSyncWebStorageKey2026',
              )
            : const WebOptions(),
      ),
    );
  }

  // Core Storage & Networking
  if (!sl.isRegistered<SecureStorage>()) {
    sl.registerLazySingleton<SecureStorage>(() => SecureStorage(sl()));
  }
  // Realtime sync wiring. Registered BEFORE ApiClient so the latter
  // can pull in ClientIdService for its X-Client-Id header
  // interceptor. Both are lazy singletons; the cold-start cost is a
  // single SharedPreferences read on first mutation.
  if (!sl.isRegistered<ClientIdService>()) {
    sl.registerLazySingleton<ClientIdService>(ClientIdService.new);
    // Warm the cache so the very first mutation already carries the
    // header (otherwise the first request goes out unlabelled and
    // every device — including us — would treat its echo as fresh).
    unawaited(sl<ClientIdService>().getId());
  }
  if (!sl.isRegistered<ApiClient>()) {
    sl.registerLazySingleton<ApiClient>(
      () => ApiClient(
        sl(),
        sl(),
        onSessionExpired: () {
          _sessionExpiredNotifier.value = !_sessionExpiredNotifier.value;
        },
        clientIdService: sl<ClientIdService>(),
      ),
    );
  }
  if (!sl.isRegistered<SyncStreamClient>()) {
    sl.registerLazySingleton<SyncStreamClient>(
      () => createSyncStreamClient(
        baseUrlGetter: () => sl<ApiClient>().dio.options.baseUrl,
        accessTokenGetter: () => sl<SecureStorage>().getAccessToken(),
      ),
    );
  }

  // Features - Auth
  // En modo offline aceptamos cualquier credencial no vacía (LocalAuthRepository).
  // Cuando el backend esté desplegado, compilar con --dart-define=OFFLINE_MODE=false
  // para volver al flujo de tokens JWT.
  if (!sl.isRegistered<AuthRepository>()) {
    sl.registerLazySingleton<AuthRepository>(
      () => _kOfflineMode
          ? LocalAuthRepository()
          : RemoteAuthRepository(apiClient: sl(), secureStorage: sl()),
    );
  }

  if (!sl.isRegistered<AuthCubit>()) {
    sl.registerFactory<AuthCubit>(() => AuthCubit(sl()));
  }

  // Features - Library
  // Modo offline: LocalLibraryRepository persiste libros importados en el
  // sandbox de la app (path_provider) + catálogo en SharedPreferences.
  if (!sl.isRegistered<LibraryRepository>()) {
    sl.registerLazySingleton<LibraryRepository>(
      () => _kOfflineMode
          ? LocalLibraryRepository()
          : RemoteLibraryRepository(apiClient: sl()),
    );
  }

  // Features - Reader
  // Modo offline: LocalReaderRepository parsea PDF/TXT/MD desde el archivo
  // local y cachea los capítulos. Requiere que LibraryRepository sea Local
  // para poder resolver el path del archivo.
  if (!sl.isRegistered<ReaderRepository>()) {
    sl.registerLazySingleton<ReaderRepository>(
      () => _kOfflineMode
          ? LocalReaderRepository(
              library: sl<LibraryRepository>() as LocalLibraryRepository,
            )
          : RemoteReaderRepository(apiClient: sl()),
    );
  }

  if (!sl.isRegistered<BookmarkRepository>()) {
    sl.registerLazySingleton<BookmarkRepository>(BookmarkRepository.new);
  }

  if (!sl.isRegistered<ReadingStatsRepository>()) {
    sl.registerLazySingleton<ReadingStatsRepository>(ReadingStatsRepository.new);
  }

  if (!sl.isRegistered<ChapterCacheRepository>()) {
    sl.registerLazySingleton<ChapterCacheRepository>(ChapterCacheRepository.new);
  }

  if (!sl.isRegistered<VoicePresetRepository>()) {
    sl.registerLazySingleton<VoicePresetRepository>(VoicePresetRepository.new);
  }

  if (!sl.isRegistered<HighlightRepository>()) {
    sl.registerLazySingleton<HighlightRepository>(HighlightRepository.new);
  }

  if (!sl.isRegistered<BookShelfRepository>()) {
    sl.registerLazySingleton<BookShelfRepository>(BookShelfRepository.new);
  }

  if (!sl.isRegistered<AmbientSoundRepository>()) {
    final ambient = AmbientSoundRepository();
    sl.registerLazySingleton<AmbientSoundRepository>(() => ambient);
    // Restore last sound preference (does not auto-start playback
    // unless the user had it enabled when they last quit).
    unawaited(ambient.restorePreferences());
  }

  if (!sl.isRegistered<AudioPlayerRepository>()) {
    sl.registerLazySingleton<AudioPlayerRepository>(
      () => JustAudioPlayerRepository(),
    );
  }

  if (!sl.isRegistered<DeviceTtsRepository>()) {
    sl.registerLazySingleton<DeviceTtsRepository>(
      DeviceTtsRepository.new,
    );
  }

  if (!sl.isRegistered<TtsCapabilities>()) {
    sl.registerLazySingleton<TtsCapabilities>(
      () => sl<DeviceTtsRepository>().capabilities,
    );
  }

  if (!sl.isRegistered<AudioTtsRepository>()) {
    sl.registerLazySingleton<AudioTtsRepository>(
      () => AudioTtsRepository(
        audioPlayer: sl<AudioPlayerRepository>(),
        readerRepository: sl<ReaderRepository>(),
        baseUrlGetter: () => sl<ApiClient>().dio.options.baseUrl,
      ),
    );
  }

if (!sl.isRegistered<TtsRepositoryProxy>()) {
  final mode = await getTtsMode();
  final voiceId = await getSelectedVoiceId();
  final speechRate = await getTtsSpeechRate();
  final nativeVoice = await getNativeVoice();
  sl<DeviceTtsRepository>().speechRate = speechRate;
  if (nativeVoice != null) {
    // Apply asynchronously; init() will run on first speak() if needed.
    unawaited(sl<DeviceTtsRepository>().setVoice(nativeVoice));
  }
  sl.registerLazySingleton<TtsRepositoryProxy>(
    () => TtsRepositoryProxy(
      device: sl<DeviceTtsRepository>(),
      audio: sl<AudioTtsRepository>(),
      initialMode: mode,
    ),
  );
  sl<AudioTtsRepository>().setVoiceId(voiceId);
}
  if (!sl.isRegistered<TtsRepository>()) {
    sl.registerLazySingleton<TtsRepository>(() => sl<TtsRepositoryProxy>());
  }

  // Features - Settings (reading preferences)
  if (!sl.isRegistered<PreferencesRepository>()) {
    sl.registerLazySingleton<PreferencesRepository>(
      () => LocalPreferencesRepository(),
    );
  }
}
