import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/network/api_client.dart';
import '../../core/storage/secure_storage.dart';
import '../../features/auth/data/repositories/remote_auth_repository.dart';
import '../../features/auth/domain/repositories/auth_repository.dart';
import '../../features/auth/presentation/cubit/auth_cubit.dart';
import '../../features/library/data/repositories/remote_library_repository.dart';
import '../../features/library/domain/repositories/library_repository.dart';
import '../../features/reader/data/repositories/audio_tts_repository.dart';
import '../../features/reader/data/repositories/device_tts_repository.dart';
import '../../features/reader/data/repositories/just_audio_player_repository.dart';
import '../../features/reader/data/repositories/remote_reader_repository.dart';
import '../../features/reader/data/repositories/tts/tts_capabilities.dart';
import '../../features/reader/data/repositories/tts_repository_proxy.dart';
import '../../features/reader/domain/repositories/audio_player_repository.dart';
import '../../features/reader/domain/repositories/reader_repository.dart';
import '../../features/reader/domain/repositories/tts_repository.dart';
import '../../features/settings/data/repositories/local_preferences_repository.dart';
import '../../features/settings/domain/repositories/preferences_repository.dart';

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

const _kNativeVoiceNameKey = 'tts_native_voice_name${kIsWeb ? '_web' : '_mobile'}';
const _kNativeVoiceLocaleKey = 'tts_native_voice_locale${kIsWeb ? '_web' : '_mobile'}';

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
  if (!sl.isRegistered<ApiClient>()) {
    sl.registerLazySingleton<ApiClient>(
      () => ApiClient(
        sl(),
        sl(),
        onSessionExpired: () {
          _sessionExpiredNotifier.value = !_sessionExpiredNotifier.value;
        },
      ),
    );
  }

  // Features - Auth
  if (!sl.isRegistered<AuthRepository>()) {
    sl.registerLazySingleton<AuthRepository>(
      () => RemoteAuthRepository(apiClient: sl(), secureStorage: sl()),
    );
  }

  if (!sl.isRegistered<AuthCubit>()) {
    sl.registerFactory<AuthCubit>(() => AuthCubit(sl()));
  }

  // Features - Library
  if (!sl.isRegistered<LibraryRepository>()) {
    sl.registerLazySingleton<LibraryRepository>(
      () => RemoteLibraryRepository(apiClient: sl()),
    );
  }

  // Features - Reader
  if (!sl.isRegistered<ReaderRepository>()) {
    sl.registerLazySingleton<ReaderRepository>(
      () => RemoteReaderRepository(apiClient: sl()),
    );
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
