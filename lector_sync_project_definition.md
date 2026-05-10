# LectorSync — Definición completa del proyecto
> Aplicación de lectura sincronizada: texto + audio + experiencia sensorial  
> Plataformas: iOS · Android · macOS · Windows · Linux  
> Stack principal: Flutter 3+ · Dart · Node.js · PostgreSQL

---

## Tabla de contenidos

1. [Visión y propuesta de valor](#1-visión-y-propuesta-de-valor)
2. [Principios de diseño de software](#2-principios-de-diseño-de-software)
3. [Arquitectura general del sistema](#3-arquitectura-general-del-sistema)
4. [Estructura del proyecto Flutter](#4-estructura-del-proyecto-flutter)
5. [Capas de la arquitectura limpia](#5-capas-de-la-arquitectura-limpia)
6. [Módulos funcionales](#6-módulos-funcionales)
7. [Motor de sincronización (core engine)](#7-motor-de-sincronización-core-engine)
8. [Gestión de estado](#8-gestión-de-estado)
9. [Navegación](#9-navegación)
10. [Arquitectura del backend](#10-arquitectura-del-backend)
11. [Esquema de base de datos](#11-esquema-de-base-de-datos)
12. [Contratos de API (OpenAPI)](#12-contratos-de-api-openapi)
13. [Plataformas específicas](#13-plataformas-específicas)
14. [Experiencia sensorial](#14-experiencia-sensorial)
15. [Estrategia de testing](#15-estrategia-de-testing)
16. [Pipeline CI/CD](#16-pipeline-cicd)
17. [Seguridad](#17-seguridad)
18. [Observabilidad y monitoreo](#18-observabilidad-y-monitoreo)
19. [Roadmap de desarrollo](#19-roadmap-de-desarrollo)
20. [Convenciones y estándares](#20-convenciones-y-estándares)
21. [Decisiones de arquitectura (ADRs)](#21-decisiones-de-arquitectura-adrs)
22. [Checklist de inicio del proyecto](#22-checklist-de-inicio-del-proyecto)

---

## 1. Visión y propuesta de valor

### 1.1 Concepto central

LectorSync es una aplicación nativa multiplataforma que sincroniza la lectura visual de un libro digital con una narración de alta calidad en tiempo real. Cada palabra se resalta en el momento exacto en que la voz la pronuncia, creando una experiencia bimodal (vista + oído) que evoca la sensación física de leer un libro impreso.

### 1.2 Diferenciadores clave

| Diferenciador | Descripción |
|---|---|
| Sincronización palabra por palabra | Sub-100ms de latencia entre audio y resaltado visual |
| Ambientación sensorial | Sonido de página, textura visual de papel, vibración háptica |
| Voz por personaje | NLP detecta diálogos; cada personaje tiene su propia voz |
| Ritmo adaptativo | El audio se adapta al ritmo natural del lector |
| Modo sin pantalla | Continúa como audiolibro con controles de auriculares |
| Cero dependencia web | App nativa: sin WebView, sin Electron, sin navegador |

### 1.3 Usuarios objetivo

- **Lector ocasional**: quiere hacer dos cosas a la vez (leer + escuchar)
- **Estudiante de idiomas**: mejora comprensión auditiva leyendo en idioma extranjero
- **Persona con dislexia**: el audio ayuda a seguir el flujo del texto
- **Audiófilo del libro**: valora la calidad de la voz narrada
- **Club de lectura**: lee el mismo libro sincronizadamente con otros

---

## 2. Principios de diseño de software

Siguiendo los principios del `architect-reviewer`, todo el código del proyecto debe cumplir:

### 2.1 SOLID aplicado a Flutter

```
S — Single Responsibility
    Cada widget tiene UNA responsabilidad.
    BookPageWidget solo renderiza páginas. No maneja audio. No maneja estado global.

O — Open/Closed
    El SyncEngine es extensible para nuevos proveedores de TTS
    sin modificar el motor central. Se agregan adaptadores nuevos.

L — Liskov Substitution
    ElevenLabsAdapter y AzureTTSAdapter son intercambiables
    porque ambos implementan TTSProvider.

I — Interface Segregation
    TTSProvider no expone métodos que no todos los adaptadores usan.
    Interfaces pequeñas y focalizadas.

D — Dependency Inversion
    Los BLoCs dependen de abstracciones (repositorios),
    no de implementaciones concretas (HTTP, SQLite).
```

### 2.2 Reglas de dependencia (Clean Architecture)

```
┌─────────────────────────────────────────────┐
│  Presentation (Widgets, BLoCs, Pages)        │
│  ↓ depende de ↓                              │
│  Domain (Entities, UseCases, Repositories)  │
│  ↓ depende de ↓                              │
│  Data (DataSources, Models, Adapters)        │
└─────────────────────────────────────────────┘

REGLA: Las flechas de dependencia apuntan HACIA ADENTRO.
Domain NUNCA importa de Data ni de Presentation.
```

### 2.3 Convenciones de arquitectura

- Todo UseCase tiene una sola responsabilidad y un único método `call()`
- Los repositorios son interfaces en domain, implementaciones en data
- Los errores se propagan como `Either<Failure, T>` (usando `fpdart`)
- No se usa `BuildContext` fuera de la capa de presentación
- Los widgets son `const` siempre que sea posible

---

## 3. Arquitectura general del sistema

```
┌──────────────────────────────────────────────────────────────────┐
│                        CLIENTE (Flutter)                          │
│                                                                    │
│  ┌─────────────┐  ┌─────────────┐  ┌──────────────────────────┐ │
│  │  UI Layer   │  │  BLoC Layer │  │  Domain / Use Cases      │ │
│  │  (Widgets)  │◄─│  (State)    │◄─│  SyncEngine              │ │
│  └─────────────┘  └─────────────┘  │  EPUBParser              │ │
│                                     │  TTSOrchestrator         │ │
│  ┌──────────────────────────────┐   └──────────────────────────┘ │
│  │  Data Layer                  │              │                  │
│  │  - Isar (local DB)           │              ▼                  │
│  │  - SecureStorage             │   ┌──────────────────────┐     │
│  │  - FileSystem                │   │  TTS Adapters        │     │
│  │  - API Client (Dio)          │   │  - ElevenLabs        │     │
│  └──────────────────────────────┘   │  - Azure Neural TTS  │     │
│                                      │  - Flutter TTS (offline)│  │
└──────────────────────────────────────└──────────────────────┘────┘
                        │
                        │ HTTPS / REST
                        ▼
┌──────────────────────────────────────────────────────────────────┐
│                       BACKEND (Node.js)                           │
│                                                                    │
│  ┌──────────────┐  ┌──────────────┐  ┌────────────────────────┐ │
│  │  API Gateway │  │  Auth Service│  │  Book Processor        │ │
│  │  (Express)   │  │  (JWT/OAuth) │  │  EPUB parser + NLP     │ │
│  └──────────────┘  └──────────────┘  └────────────────────────┘ │
│                                                                    │
│  ┌──────────────┐  ┌──────────────┐  ┌────────────────────────┐ │
│  │  PostgreSQL  │  │  Redis Cache │  │  S3 / Object Storage   │ │
│  │  (usuarios,  │  │  (sesiones,  │  │  (audio cacheado,      │ │
│  │   progreso)  │  │   timestamps)│  │   libros, portadas)    │ │
│  └──────────────┘  └──────────────┘  └────────────────────────┘ │
└──────────────────────────────────────────────────────────────────┘
```

---

## 4. Estructura del proyecto Flutter

```
lectorsync/
├── lib/
│   ├── main.dart                    # Entry point — solo inicialización
│   ├── app.dart                     # MaterialApp / CupertinoApp wrapper
│   ├── bootstrap.dart               # DI, configuración inicial
│   │
│   ├── core/                        # Código compartido entre features
│   │   ├── constants/
│   │   │   ├── app_constants.dart
│   │   │   ├── route_constants.dart
│   │   │   └── asset_constants.dart
│   │   ├── errors/
│   │   │   ├── failures.dart        # Jerarquía de Failure
│   │   │   └── exceptions.dart
│   │   ├── usecases/
│   │   │   └── usecase.dart         # Interfaz base UseCase<T, P>
│   │   ├── network/
│   │   │   ├── api_client.dart      # Dio configurado con interceptors
│   │   │   └── network_info.dart
│   │   ├── storage/
│   │   │   ├── local_storage.dart   # Isar wrapper
│   │   │   └── secure_storage.dart  # FlutterSecureStorage wrapper
│   │   ├── platform/
│   │   │   ├── platform_detector.dart
│   │   │   ├── haptic_service.dart
│   │   │   └── file_picker_service.dart
│   │   ├── theme/
│   │   │   ├── app_theme.dart
│   │   │   ├── app_colors.dart
│   │   │   ├── app_typography.dart
│   │   │   └── reading_themes.dart  # Sepia, dark, lámpara, etc.
│   │   └── di/
│   │       ├── injection_container.dart  # get_it setup
│   │       └── modules/
│   │           ├── core_module.dart
│   │           ├── auth_module.dart
│   │           ├── library_module.dart
│   │           └── reader_module.dart
│   │
│   ├── features/
│   │   │
│   │   ├── auth/                    # Autenticación
│   │   │   ├── domain/
│   │   │   │   ├── entities/
│   │   │   │   │   └── user.dart
│   │   │   │   ├── repositories/
│   │   │   │   │   └── auth_repository.dart
│   │   │   │   └── usecases/
│   │   │   │       ├── login_usecase.dart
│   │   │   │       ├── logout_usecase.dart
│   │   │   │       └── refresh_token_usecase.dart
│   │   │   ├── data/
│   │   │   │   ├── models/
│   │   │   │   │   └── user_model.dart
│   │   │   │   ├── datasources/
│   │   │   │   │   ├── auth_remote_datasource.dart
│   │   │   │   │   └── auth_local_datasource.dart
│   │   │   │   └── repositories/
│   │   │   │       └── auth_repository_impl.dart
│   │   │   └── presentation/
│   │   │       ├── bloc/
│   │   │       │   ├── auth_bloc.dart
│   │   │       │   ├── auth_event.dart
│   │   │       │   └── auth_state.dart
│   │   │       ├── pages/
│   │   │       │   ├── login_page.dart
│   │   │       │   └── register_page.dart
│   │   │       └── widgets/
│   │   │           └── auth_form_widget.dart
│   │   │
│   │   ├── library/                 # Biblioteca de libros del usuario
│   │   │   ├── domain/
│   │   │   │   ├── entities/
│   │   │   │   │   ├── book.dart
│   │   │   │   │   └── reading_progress.dart
│   │   │   │   ├── repositories/
│   │   │   │   │   └── library_repository.dart
│   │   │   │   └── usecases/
│   │   │   │       ├── get_library_usecase.dart
│   │   │   │       ├── import_book_usecase.dart
│   │   │   │       ├── delete_book_usecase.dart
│   │   │   │       └── get_reading_progress_usecase.dart
│   │   │   ├── data/
│   │   │   │   ├── models/
│   │   │   │   │   ├── book_model.dart
│   │   │   │   │   └── reading_progress_model.dart
│   │   │   │   ├── datasources/
│   │   │   │   │   ├── library_local_datasource.dart
│   │   │   │   │   ├── library_remote_datasource.dart
│   │   │   │   │   └── epub_parser_datasource.dart
│   │   │   │   └── repositories/
│   │   │   │       └── library_repository_impl.dart
│   │   │   └── presentation/
│   │   │       ├── bloc/
│   │   │       │   └── library_bloc.dart
│   │   │       ├── pages/
│   │   │       │   └── library_page.dart
│   │   │       └── widgets/
│   │   │           ├── book_card_widget.dart
│   │   │           ├── book_grid_widget.dart
│   │   │           └── import_book_button.dart
│   │   │
│   │   ├── reader/                  # El corazón de la aplicación
│   │   │   ├── domain/
│   │   │   │   ├── entities/
│   │   │   │   │   ├── book_chapter.dart
│   │   │   │   │   ├── word_timestamp.dart       # {word, start, end, index}
│   │   │   │   │   ├── sync_state.dart
│   │   │   │   │   └── reading_settings.dart
│   │   │   │   ├── repositories/
│   │   │   │   │   ├── reader_repository.dart
│   │   │   │   │   └── tts_repository.dart
│   │   │   │   └── usecases/
│   │   │   │       ├── load_chapter_usecase.dart
│   │   │   │       ├── generate_audio_usecase.dart
│   │   │   │       ├── sync_playback_usecase.dart
│   │   │   │       ├── save_progress_usecase.dart
│   │   │   │       └── detect_dialogues_usecase.dart
│   │   │   ├── data/
│   │   │   │   ├── models/
│   │   │   │   │   ├── word_timestamp_model.dart
│   │   │   │   │   └── chapter_model.dart
│   │   │   │   ├── datasources/
│   │   │   │   │   ├── tts_elevenlabs_datasource.dart
│   │   │   │   │   ├── tts_azure_datasource.dart
│   │   │   │   │   ├── tts_local_datasource.dart  # flutter_tts offline
│   │   │   │   │   └── audio_cache_datasource.dart
│   │   │   │   └── repositories/
│   │   │   │       ├── reader_repository_impl.dart
│   │   │   │       └── tts_repository_impl.dart
│   │   │   └── presentation/
│   │   │       ├── bloc/
│   │   │       │   ├── reader_bloc.dart
│   │   │       │   ├── reader_event.dart
│   │   │       │   ├── reader_state.dart
│   │   │       │   ├── audio_bloc.dart
│   │   │       │   └── sync_bloc.dart
│   │   │       ├── pages/
│   │   │       │   └── reader_page.dart
│   │   │       └── widgets/
│   │   │           ├── book_text_widget.dart       # Renderiza texto con resaltado
│   │   │           ├── word_span_widget.dart       # Span individual resaltable
│   │   │           ├── page_turn_animation.dart    # Animación volteo de página
│   │   │           ├── audio_controls_widget.dart
│   │   │           ├── reading_settings_panel.dart
│   │   │           └── chapter_navigator_widget.dart
│   │   │
│   │   ├── tts_engine/              # Motor TTS como feature independiente
│   │   │   ├── domain/
│   │   │   │   ├── entities/
│   │   │   │   │   ├── tts_config.dart
│   │   │   │   │   └── audio_chunk.dart
│   │   │   │   ├── repositories/
│   │   │   │   │   └── tts_provider.dart     # Interfaz base del proveedor TTS
│   │   │   │   └── usecases/
│   │   │   │       └── synthesize_with_timestamps_usecase.dart
│   │   │   └── data/
│   │   │       ├── adapters/
│   │   │       │   ├── elevenlabs_adapter.dart
│   │   │       │   ├── azure_tts_adapter.dart
│   │   │       │   └── device_tts_adapter.dart
│   │   │       └── mappers/
│   │   │           └── alignment_to_word_map.dart  # char[] → word[]
│   │   │
│   │   ├── settings/                # Configuración de la app
│   │   │   └── ...
│   │   │
│   │   └── notes/                   # Anotaciones y subrayados
│   │       └── ...
│   │
│   └── shared/                      # Widgets reutilizables globales
│       ├── widgets/
│       │   ├── loading_widget.dart
│       │   ├── error_widget.dart
│       │   ├── empty_state_widget.dart
│       │   └── adaptive_scaffold.dart  # Desktop vs Mobile layout
│       └── extensions/
│           ├── context_extensions.dart
│           ├── string_extensions.dart
│           └── list_extensions.dart
│
├── test/
│   ├── unit/
│   ├── widget/
│   ├── integration/
│   └── golden/
│
├── assets/
│   ├── fonts/
│   ├── sounds/
│   │   ├── page_turn.mp3
│   │   ├── book_open.mp3
│   │   └── ambient_library.mp3
│   ├── images/
│   └── animations/       # Lottie files
│
├── android/
├── ios/
├── macos/
├── windows/
├── linux/
│
├── pubspec.yaml
├── analysis_options.yaml
├── build.yaml            # Code generation config
└── Makefile              # Comandos de desarrollo
```

---

## 5. Capas de la arquitectura limpia

### 5.1 Domain Layer (núcleo, sin dependencias externas)

```dart
// lib/core/usecases/usecase.dart
import 'package:fpdart/fpdart.dart';
import '../errors/failures.dart';

abstract class UseCase<Type, Params> {
  Future<Either<Failure, Type>> call(Params params);
}

class NoParams {
  const NoParams();
}

// lib/features/reader/domain/entities/word_timestamp.dart
class WordTimestamp {
  final int index;         // posición en el texto
  final String word;       // la palabra
  final double startMs;    // milliseconds
  final double endMs;
  final int charOffset;    // posición de char en el texto original

  const WordTimestamp({
    required this.index,
    required this.word,
    required this.startMs,
    required this.endMs,
    required this.charOffset,
  });
}

// lib/features/reader/domain/repositories/tts_provider.dart
abstract class TTSProvider {
  Future<Either<Failure, AudioWithTimestamps>> synthesize({
    required String text,
    required TTSConfig config,
  });
  
  bool get supportsOffline;
  bool get supportsWordTimestamps;
}

// lib/features/reader/domain/entities/sync_state.dart
class SyncState {
  final int currentWordIndex;
  final double audioPositionMs;
  final bool isPlaying;
  final double playbackRate;
  final SyncError? error;

  const SyncState({...});
}
```

### 5.2 Data Layer

```dart
// lib/features/tts_engine/data/adapters/elevenlabs_adapter.dart
class ElevenLabsAdapter implements TTSProvider {
  final Dio _dio;
  final String _apiKey;

  @override
  bool get supportsOffline => false;
  
  @override
  bool get supportsWordTimestamps => true;

  @override
  Future<Either<Failure, AudioWithTimestamps>> synthesize({
    required String text,
    required TTSConfig config,
  }) async {
    try {
      final response = await _dio.post(
        '/v1/text-to-speech/${config.voiceId}/with-timestamps',
        data: {
          'text': text,
          'model_id': 'eleven_multilingual_v2',
          'voice_settings': {
            'stability': config.stability,
            'similarity_boost': config.similarityBoost,
          },
        },
      );
      
      final alignment = response.data['alignment'] as Map<String, dynamic>;
      final wordMap = AlignmentToWordMap.convert(alignment);
      final audioBytes = base64Decode(response.data['audio_base64']);
      
      return Right(AudioWithTimestamps(
        audioBytes: audioBytes,
        wordTimestamps: wordMap,
      ));
    } on DioException catch (e) {
      return Left(TTSFailure(message: e.message ?? 'TTS error'));
    }
  }
}

// lib/features/tts_engine/data/mappers/alignment_to_word_map.dart
class AlignmentToWordMap {
  /// Convierte el formato de ElevenLabs (por carácter) a WordTimestamp por palabra.
  /// ElevenLabs devuelve: characters[], character_start_times_seconds[], character_end_times_seconds[]
  static List<WordTimestamp> convert(Map<String, dynamic> alignment) {
    final chars = List<String>.from(alignment['characters']);
    final starts = List<double>.from(alignment['character_start_times_seconds']);
    final ends = List<double>.from(alignment['character_end_times_seconds']);
    
    final words = <WordTimestamp>[];
    var wordBuffer = '';
    var wordStart = 0.0;
    var wordCharOffset = 0;
    var wordIndex = 0;

    for (int i = 0; i < chars.length; i++) {
      final char = chars[i];
      
      if (char == ' ' || char == '\n' || i == chars.length - 1) {
        if (char != ' ' && char != '\n') wordBuffer += char;
        
        if (wordBuffer.isNotEmpty) {
          words.add(WordTimestamp(
            index: wordIndex++,
            word: wordBuffer,
            startMs: wordStart * 1000,
            endMs: ends[i] * 1000,
            charOffset: wordCharOffset,
          ));
          wordBuffer = '';
        }
        wordCharOffset = i + 1;
      } else {
        if (wordBuffer.isEmpty) {
          wordStart = starts[i];
          wordCharOffset = i;
        }
        wordBuffer += char;
      }
    }
    
    return words;
  }
}
```

### 5.3 Presentation Layer — BLoC

```dart
// lib/features/reader/presentation/bloc/sync_bloc.dart
class SyncBloc extends Bloc<SyncEvent, SyncState> {
  final AudioPlayer _audioPlayer;
  StreamSubscription<Duration>? _positionSub;
  List<WordTimestamp> _wordMap = [];

  SyncBloc({required AudioPlayer audioPlayer})
      : _audioPlayer = audioPlayer,
        super(SyncState.initial()) {
    on<SyncStarted>(_onStarted);
    on<SyncPaused>(_onPaused);
    on<SyncPositionUpdated>(_onPositionUpdated);
    on<SyncSpeedChanged>(_onSpeedChanged);
    on<SyncWordMapLoaded>(_onWordMapLoaded);
  }

  Future<void> _onStarted(SyncStarted event, Emitter<SyncState> emit) async {
    _positionSub = _audioPlayer.positionStream.listen((pos) {
      add(SyncPositionUpdated(positionMs: pos.inMilliseconds.toDouble()));
    });
    await _audioPlayer.play();
    emit(state.copyWith(isPlaying: true));
  }

  void _onPositionUpdated(SyncPositionUpdated event, Emitter<SyncState> emit) {
    final idx = _findWordAt(event.positionMs);
    if (idx != state.currentWordIndex) {
      emit(state.copyWith(
        currentWordIndex: idx,
        audioPositionMs: event.positionMs,
      ));
    }
  }

  /// Búsqueda binaria O(log n) — crítica para 60fps
  int _findWordAt(double ms) {
    if (_wordMap.isEmpty) return -1;
    int lo = 0, hi = _wordMap.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final w = _wordMap[mid];
      if (ms < w.startMs) {
        hi = mid - 1;
      } else if (ms > w.endMs) {
        lo = mid + 1;
      } else {
        return mid;
      }
    }
    return lo - 1;
  }

  @override
  Future<void> close() {
    _positionSub?.cancel();
    return super.close();
  }
}
```

---

## 6. Módulos funcionales

### 6.1 Descripción de cada feature

| Feature | Responsabilidad | Dependencias externas |
|---|---|---|
| `auth` | Login, registro, sesión, tokens | Backend API |
| `library` | Catálogo de libros del usuario, progreso | Backend API, Isar DB, FilePicker |
| `reader` | Renderizado de texto, resaltado, controles | SyncBloc, AudioBloc |
| `tts_engine` | Síntesis de voz, timestamps, cache de audio | ElevenLabs/Azure/DeviceTTS |
| `epub_parser` | Parseo de EPUB/PDF, extracción de capítulos | epub_kit, pdf_render |
| `settings` | Preferencias de usuario, temas de lectura | Isar DB |
| `notes` | Subrayados, anotaciones, notas de voz | Isar DB, Backend API |
| `offline` | Gestión de descargas, sincronización | WorkManager, ConnectivityPlus |

### 6.2 Diagrama de dependencias entre features

```
auth ──────────────────────────────────┐
                                        ▼
library ──► epub_parser ──► reader ──► tts_engine
              │                │
              ▼                ▼
           offline           notes
              │                │
              └────────────────┘
                       ▼
                   settings
```

Regla: ninguna flecha apunta hacia `auth` ni hacia `settings` desde otros features (excepto para contexto de usuario). Los features no se llaman entre sí directamente — se comunican a través del domain layer.

---

## 7. Motor de sincronización (core engine)

Este es el componente más crítico del producto. Debe tener cero tolerancia a regresiones.

### 7.1 Flujo completo de sincronización

```
1. Usuario abre capítulo
        │
        ▼
2. EPUBParser extrae texto limpio del capítulo
   - Quita HTML tags
   - Normaliza espacios y saltos de línea
   - Identifica párrafos y diálogos
        │
        ▼
3. DialogueDetector (NLP simple) identifica bloques de diálogo
   y asigna voces: narrador, personaje_1, personaje_2...
        │
        ▼
4. TTSOrchestrator divide el texto en chunks de ~500 palabras
   (límite por llamada a API de ElevenLabs)
        │
        ▼
5. Para cada chunk:
   ElevenLabsAdapter.synthesize(text, voiceConfig)
   → devuelve AudioBytes + List<WordTimestamp>
        │
        ▼
6. AudioCacheDatasource guarda audio en directorio temporal
   TimestampCacheDatasource guarda wordMap en Isar
        │
        ▼
7. SyncBloc recibe:
   - Lista de WordTimestamp completa del capítulo
   - Path del archivo de audio
        │
        ▼
8. just_audio.AudioPlayer carga el archivo
   Stream positionStream → SyncBloc
        │
        ▼
9. Por cada tick del positionStream:
   findWordAt(currentTimeMs) → búsqueda binaria
   Si wordIndex cambió → emitir SyncState(currentWordIndex: idx)
        │
        ▼
10. BookTextWidget escucha SyncBloc
    WordSpanWidget(index: i).isHighlighted = (i == state.currentWordIndex)
    → Flutter re-renderiza solo el span que cambió (RepaintBoundary)
        │
        ▼
11. Si el usuario cambia playbackRate:
    audioPlayer.setSpeed(rate)
    audioPlayer.currentTime ya refleja la velocidad automáticamente
    → wordMap NO cambia, el cálculo es instantáneo
```

### 7.2 WordSpanWidget con RepaintBoundary

```dart
// lib/features/reader/presentation/widgets/word_span_widget.dart
class WordSpanWidget extends StatelessWidget {
  final int wordIndex;
  final String text;
  final bool isHighlighted;
  final bool isDone;
  final VoidCallback? onTap;

  const WordSpanWidget({
    super.key,
    required this.wordIndex,
    required this.text,
    required this.isHighlighted,
    required this.isDone,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // RepaintBoundary evita que el re-render de UNA palabra
    // cause re-render de toda la página
    return RepaintBoundary(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 60),
          decoration: isHighlighted
              ? BoxDecoration(
                  color: context.readingTheme.highlightColor,
                  borderRadius: BorderRadius.circular(3),
                )
              : null,
          child: Text(
            '$text ',
            style: TextStyle(
              color: isDone
                  ? context.readingTheme.doneWordColor
                  : context.readingTheme.textColor,
              fontFamily: context.readingSettings.fontFamily,
              fontSize: context.readingSettings.fontSize,
              height: context.readingSettings.lineHeight,
            ),
          ),
        ),
      ),
    );
  }
}
```

### 7.3 Pre-procesamiento por chunks

```dart
// lib/features/reader/domain/usecases/generate_audio_usecase.dart
class GenerateAudioUseCase extends UseCase<ChapterAudio, GenerateAudioParams> {
  static const int _chunkSize = 500; // palabras por chunk
  static const int _parallelChunks = 3; // chunks en paralelo

  @override
  Future<Either<Failure, ChapterAudio>> call(GenerateAudioParams params) async {
    final chunks = _splitIntoChunks(params.chapterText, _chunkSize);
    final results = <AudioChunk>[];

    // Procesa chunks en paralelo con límite de concurrencia
    for (int i = 0; i < chunks.length; i += _parallelChunks) {
      final batch = chunks.skip(i).take(_parallelChunks);
      final batchResults = await Future.wait(
        batch.map((chunk) => _ttsRepository.synthesize(
          text: chunk.text,
          config: _selectVoiceConfig(chunk, params.voiceSettings),
        )),
      );
      
      // Si algún chunk falla, fallback a TTS local
      for (final result in batchResults) {
        result.fold(
          (failure) => results.add(await _fallbackToLocalTTS(chunks[i])),
          (audio) => results.add(audio),
        );
      }
    }

    return Right(ChapterAudio.fromChunks(results));
  }
}
```

---

## 8. Gestión de estado

### 8.1 Decisión: flutter_bloc (BLoC pattern)

**Razón**: El producto requiere estados complejos, streams de audio en tiempo real, y separación estricta entre lógica y UI. BLoC es la opción más testeable y predecible para este caso.

**Alternativa considerada**: Riverpod 2.0 — descartada para este proyecto porque el `SyncBloc` necesita gestionar un `Stream` de posición de audio con control fino, algo que BLoC maneja de manera más explícita.

### 8.2 BLoCs principales

| BLoC | Responsabilidad | Estados clave |
|---|---|---|
| `AuthBloc` | Sesión de usuario | Unauthenticated, Authenticated, Loading |
| `LibraryBloc` | Catálogo de libros | Initial, Loading, Loaded, Error |
| `ReaderBloc` | Estado general del lector | Loading, Ready, Error |
| `SyncBloc` | Sincronización audio↔texto | Playing, Paused, Finished |
| `AudioBloc` | Control del reproductor | Loading, Buffering, Playing, Paused |
| `SettingsBloc` | Preferencias de lectura | ReadingSettings (tema, fuente, velocidad) |

### 8.3 Comunicación entre BLoCs

Los BLoCs no se llaman directamente entre sí. Se comunican a través de streams suscritos en el `bootstrap.dart`:

```dart
// lib/bootstrap.dart
void _wireBlocs() {
  // Cuando SyncBloc llega al final del capítulo → LibraryBloc guarda progreso
  syncBloc.stream
    .where((s) => s is SyncFinished)
    .listen((_) => libraryBloc.add(SaveProgressEvent(...))); 
  
  // Cuando ReaderBloc carga un capítulo → AudioBloc prepara el audio
  readerBloc.stream
    .whereType<ReaderChapterLoaded>()
    .listen((s) => audioBloc.add(AudioPrepareEvent(chapter: s.chapter)));
}
```

---

## 9. Navegación

### 9.1 Decisión: go_router

```dart
// lib/core/router/app_router.dart
final appRouter = GoRouter(
  initialLocation: '/library',
  redirect: (context, state) {
    final isAuthenticated = context.read<AuthBloc>().state is Authenticated;
    final isAuthRoute = state.location.startsWith('/auth');
    
    if (!isAuthenticated && !isAuthRoute) return '/auth/login';
    if (isAuthenticated && isAuthRoute) return '/library';
    return null;
  },
  routes: [
    GoRoute(path: '/auth/login',    builder: (_, __) => const LoginPage()),
    GoRoute(path: '/auth/register', builder: (_, __) => const RegisterPage()),
    GoRoute(path: '/library',       builder: (_, __) => const LibraryPage()),
    GoRoute(
      path: '/reader/:bookId',
      builder: (context, state) => ReaderPage(
        bookId: state.pathParameters['bookId']!,
        chapterId: state.uri.queryParameters['chapter'],
      ),
    ),
    GoRoute(path: '/settings',      builder: (_, __) => const SettingsPage()),
  ],
);
```

### 9.2 Layout adaptativo (desktop vs mobile)

```dart
// lib/shared/widgets/adaptive_scaffold.dart
class AdaptiveScaffold extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 960;
    
    if (isDesktop) {
      return Row(children: [
        NavigationRail(destinations: _destinations),
        Expanded(child: child),
      ]);
    }
    
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(destinations: _destinations),
    );
  }
}
```

---

## 10. Arquitectura del backend

Siguiendo los lineamientos del agente `backend-architect`.

### 10.1 Servicios

```
backend/
├── api-gateway/          # Express.js — enrutamiento, auth middleware
├── services/
│   ├── auth-service/     # JWT, refresh tokens, OAuth
│   ├── library-service/  # CRUD de libros y progreso
│   ├── tts-service/      # Orquestación de TTS, caché de audio
│   └── nlp-service/      # Detección de diálogos, análisis de texto
└── workers/
    └── book-processor/   # Procesamiento asíncrono de EPUBs subidos
```

### 10.2 Stack del backend

| Componente | Tecnología | Razón |
|---|---|---|
| Runtime | Node.js 20 LTS | Ecosystem maduro, async excelente |
| Framework | Fastify | Más rápido que Express, schemas built-in |
| ORM | Drizzle ORM | Type-safe, lightweight, SQL-first |
| Base de datos | PostgreSQL 16 | ACID, full-text search, JSON support |
| Cache | Redis 7 | Timestamps de audio, sesiones |
| Object Storage | AWS S3 / MinIO | Audio generado, EPUBs, portadas |
| Queue | BullMQ (Redis) | Procesamiento asíncrono de libros |
| NLP | Python + FastAPI | spaCy para detección de diálogos |

### 10.3 Middleware stack en API Gateway

```
Request
    │
    ▼
[Rate Limiter]        ← 100 req/min por IP, 1000 req/min por usuario
    │
    ▼
[CORS]                ← whitelist de orígenes (app mobile no aplica)
    │
    ▼
[Request Logger]      ← correlation-id, trace-id
    │
    ▼
[JWT Validator]       ← verifica token, extrae user_id
    │
    ▼
[Authorization]       ← verifica que el recurso pertenece al usuario
    │
    ▼
[Handler]             ← lógica del endpoint
    │
    ▼
[Response Schema]     ← valida y serializa la respuesta
    │
    ▼
Response
```

---

## 11. Esquema de base de datos

```sql
-- Usuarios
CREATE TABLE users (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email        VARCHAR(255) UNIQUE NOT NULL,
  name         VARCHAR(255) NOT NULL,
  avatar_url   TEXT,
  plan         VARCHAR(20) NOT NULL DEFAULT 'free', -- free, premium
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Libros (metadata)
CREATE TABLE books (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title         VARCHAR(500) NOT NULL,
  author        VARCHAR(500),
  language      VARCHAR(10) NOT NULL DEFAULT 'es',
  cover_url     TEXT,
  file_key      TEXT NOT NULL,      -- clave en S3
  file_format   VARCHAR(10) NOT NULL, -- epub, pdf
  total_words   INTEGER,
  total_chapters INTEGER,
  status        VARCHAR(20) NOT NULL DEFAULT 'processing', -- processing, ready, error
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  INDEX idx_books_user_id (user_id)
);

-- Capítulos
CREATE TABLE chapters (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  book_id      UUID NOT NULL REFERENCES books(id) ON DELETE CASCADE,
  title        VARCHAR(500),
  order_index  INTEGER NOT NULL,
  word_count   INTEGER NOT NULL,
  text_content TEXT,               -- texto limpio extraído
  INDEX idx_chapters_book_id (book_id),
  UNIQUE (book_id, order_index)
);

-- Audio generado (cache)
CREATE TABLE chapter_audio (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  chapter_id      UUID NOT NULL REFERENCES chapters(id) ON DELETE CASCADE,
  voice_id        VARCHAR(100) NOT NULL,  -- voz de ElevenLabs / Azure
  tts_provider    VARCHAR(50) NOT NULL,   -- elevenlabs, azure, local
  audio_key       TEXT NOT NULL,          -- clave en S3
  duration_ms     INTEGER NOT NULL,
  word_timestamps JSONB NOT NULL,         -- List<WordTimestamp> serializada
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (chapter_id, voice_id, tts_provider)
);

-- Progreso de lectura
CREATE TABLE reading_progress (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  book_id           UUID NOT NULL REFERENCES books(id) ON DELETE CASCADE,
  chapter_id        UUID REFERENCES chapters(id),
  word_index        INTEGER NOT NULL DEFAULT 0,
  audio_position_ms INTEGER NOT NULL DEFAULT 0,
  percentage        DECIMAL(5,2) NOT NULL DEFAULT 0,
  last_read_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, book_id)
);

-- Configuración de voces por usuario
CREATE TABLE user_voice_settings (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  language    VARCHAR(10) NOT NULL,
  voice_id    VARCHAR(100) NOT NULL,  -- narrator voice
  provider    VARCHAR(50) NOT NULL,
  speed       DECIMAL(3,2) NOT NULL DEFAULT 1.0,
  stability   DECIMAL(3,2) NOT NULL DEFAULT 0.5,
  UNIQUE (user_id, language)
);

-- Anotaciones
CREATE TABLE annotations (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  book_id      UUID NOT NULL REFERENCES books(id) ON DELETE CASCADE,
  chapter_id   UUID NOT NULL REFERENCES chapters(id) ON DELETE CASCADE,
  word_start   INTEGER NOT NULL,
  word_end     INTEGER NOT NULL,
  content      TEXT,              -- nota de texto
  audio_key    TEXT,              -- nota de voz en S3
  color        VARCHAR(20),       -- color del subrayado
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

---

## 12. Contratos de API (OpenAPI)

### 12.1 Endpoints principales

```yaml
openapi: 3.1.0
info:
  title: LectorSync API
  version: 1.0.0

paths:
  /api/v1/auth/login:
    post:
      summary: Login de usuario
      requestBody:
        content:
          application/json:
            schema:
              type: object
              required: [email, password]
              properties:
                email: { type: string, format: email }
                password: { type: string, minLength: 8 }
      responses:
        '200':
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/AuthTokens'
        '401':
          $ref: '#/components/responses/Unauthorized'

  /api/v1/library:
    get:
      summary: Obtener biblioteca del usuario
      security: [bearerAuth: []]
      responses:
        '200':
          content:
            application/json:
              schema:
                type: array
                items:
                  $ref: '#/components/schemas/Book'

  /api/v1/library/import:
    post:
      summary: Importar un libro (EPUB/PDF)
      security: [bearerAuth: []]
      requestBody:
        content:
          multipart/form-data:
            schema:
              type: object
              properties:
                file:
                  type: string
                  format: binary
                language:
                  type: string
                  default: es
      responses:
        '202':
          description: Libro encolado para procesamiento
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Book'

  /api/v1/books/{bookId}/chapters/{chapterId}/audio:
    post:
      summary: Generar audio de un capítulo
      description: |
        Si el audio ya existe en caché (mismo capítulo + voz + proveedor),
        devuelve la URL del audio cacheado directamente. 
        Si no existe, genera el audio (puede tardar 5-30 segundos).
      security: [bearerAuth: []]
      requestBody:
        content:
          application/json:
            schema:
              type: object
              properties:
                voice_id:    { type: string }
                provider:    { type: string, enum: [elevenlabs, azure, local] }
      responses:
        '200':
          description: Audio disponible (cacheado)
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/ChapterAudio'
        '202':
          description: Audio en generación, polling o SSE

  /api/v1/books/{bookId}/progress:
    put:
      summary: Guardar progreso de lectura
      security: [bearerAuth: []]
      requestBody:
        content:
          application/json:
            schema:
              type: object
              required: [chapter_id, word_index, audio_position_ms]
              properties:
                chapter_id:       { type: string, format: uuid }
                word_index:       { type: integer, minimum: 0 }
                audio_position_ms:{ type: integer, minimum: 0 }
      responses:
        '204': { description: Progreso guardado }

components:
  securitySchemes:
    bearerAuth:
      type: http
      scheme: bearer
      bearerFormat: JWT

  schemas:
    AuthTokens:
      type: object
      properties:
        access_token:  { type: string }
        refresh_token: { type: string }
        expires_in:    { type: integer }

    Book:
      type: object
      properties:
        id:             { type: string, format: uuid }
        title:          { type: string }
        author:         { type: string }
        cover_url:      { type: string }
        total_chapters: { type: integer }
        status:         { type: string, enum: [processing, ready, error] }
        progress:
          $ref: '#/components/schemas/ReadingProgress'

    ChapterAudio:
      type: object
      properties:
        audio_url:       { type: string }
        duration_ms:     { type: integer }
        word_timestamps: 
          type: array
          items:
            $ref: '#/components/schemas/WordTimestamp'

    WordTimestamp:
      type: object
      properties:
        index:      { type: integer }
        word:       { type: string }
        start_ms:   { type: number }
        end_ms:     { type: number }
        char_offset:{ type: integer }

    ReadingProgress:
      type: object
      properties:
        chapter_id:       { type: string, format: uuid }
        word_index:       { type: integer }
        audio_position_ms:{ type: integer }
        percentage:       { type: number }
```

---

## 13. Plataformas específicas

### 13.1 Mobile (iOS y Android)

```dart
// lib/core/platform/haptic_service.dart
class HapticService {
  static Future<void> pageChanged() async {
    if (Platform.isIOS || Platform.isAndroid) {
      await HapticFeedback.lightImpact();
    }
  }

  static Future<void> chapterCompleted() async {
    if (Platform.isIOS || Platform.isAndroid) {
      await HapticFeedback.mediumImpact();
    }
  }

  static Future<void> wordHighlight() async {
    // Solo en dispositivos de gama alta para no afectar rendimiento
    if (Platform.isIOS && _isHighEndDevice()) {
      await HapticFeedback.selectionClick();
    }
  }
}
```

**Características exclusivas mobile:**
- Controles de audio en pantalla de bloqueo (LockScreen controls)
- Background audio con `just_audio` + `audio_service`
- Controles de auriculares (siguiente/anterior capítulo)
- Share sheet nativo para compartir citas
- Widgets de iOS/Android con progreso de lectura

### 13.2 Desktop (macOS, Windows, Linux)

**Características exclusivas desktop:**
- Menú nativo de la barra de menús (macOS)
- Drag & drop de archivos EPUB/PDF directamente a la app
- Atajos de teclado (`Space`: play/pause, `←/→`: palabra anterior/siguiente)
- Ventana dividida: texto izquierda, notas derecha
- Acceso a biblioteca local del sistema de archivos

```dart
// lib/core/platform/keyboard_shortcuts.dart
class KeyboardShortcuts {
  static final shortcuts = <ShortcutActivator, Intent>{
    const SingleActivator(LogicalKeyboardKey.space): const PlayPauseIntent(),
    const SingleActivator(LogicalKeyboardKey.arrowRight): const NextWordIntent(),
    const SingleActivator(LogicalKeyboardKey.arrowLeft): const PrevWordIntent(),
    const SingleActivator(LogicalKeyboardKey.arrowUp, meta: true): const SpeedUpIntent(),
    const SingleActivator(LogicalKeyboardKey.arrowDown, meta: true): const SpeedDownIntent(),
    const SingleActivator(LogicalKeyboardKey.keyN, meta: true): const NewAnnotationIntent(),
  };
}
```

### 13.3 Diferencias de UI por plataforma

| Elemento UI | Mobile | Desktop |
|---|---|---|
| Navegación principal | Bottom NavigationBar | NavigationRail lateral |
| Controles de audio | Panel deslizable desde abajo | Panel fijo en sidebar |
| Abrir libro | FilePicker + Biblioteca | Drag & Drop + Menú Archivo |
| Font size por defecto | 17px | 15px |
| Animación de página | Volteo 3D | Deslizamiento suave |

---

## 14. Experiencia sensorial

### 14.1 Sistema de temas de lectura

```dart
// lib/core/theme/reading_themes.dart
abstract class ReadingTheme {
  Color get backgroundColor;
  Color get textColor;
  Color get highlightColor;
  Color get doneWordColor;
  String get paperTexture;        // asset path
  Color get ambientLightColor;
}

class SepiaTheme implements ReadingTheme {
  @override Color get backgroundColor => const Color(0xFFF8F0E3);
  @override Color get textColor => const Color(0xFF4A3728);
  @override Color get highlightColor => const Color(0xFFE8B86D).withOpacity(0.6);
  @override Color get doneWordColor => const Color(0xFF9E8A78);
  @override String get paperTexture => 'assets/textures/paper_sepia.png';
  @override Color get ambientLightColor => const Color(0xFFFFD700).withOpacity(0.05);
}

class NightTheme implements ReadingTheme {
  @override Color get backgroundColor => const Color(0xFF1A1A1A);
  @override Color get textColor => const Color(0xFFE8E0D0);
  @override Color get highlightColor => const Color(0xFF4A7FA5).withOpacity(0.5);
  // ...
}

class LampTheme implements ReadingTheme {
  // Simula luz cálida de lámpara de escritorio
  // Fondo levemente amarillento con viñetado en las esquinas
}
```

### 14.2 Sonidos ambientes

```dart
// lib/core/platform/sound_service.dart
class SoundService {
  static final Map<SoundEvent, String> _assets = {
    SoundEvent.pageTurn:      'assets/sounds/page_turn.mp3',
    SoundEvent.bookOpen:      'assets/sounds/book_open.mp3',
    SoundEvent.chapterChange: 'assets/sounds/chapter_bell.mp3',
    SoundEvent.annotationAdd: 'assets/sounds/pencil_mark.mp3',
  };

  // Volume muy bajo (0.15) — sutil, nunca intrusivo
  static Future<void> play(SoundEvent event) async {
    final settings = GetIt.I<SettingsBloc>().state.soundEnabled;
    if (!settings) return;
    await _pool.play(_assets[event]!, volume: 0.15);
  }
}
```

### 14.3 Animación de volteo de página

```dart
// lib/features/reader/presentation/widgets/page_turn_animation.dart
class PageTurnAnimation extends StatefulWidget { ... }

class _PageTurnAnimationState extends State<PageTurnAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _rotation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _rotation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  // Transform 3D para simular volteo de página real
  Widget _buildPage(Widget child, double rotation) {
    final isForward = rotation < 0.5;
    return Transform(
      alignment: Alignment.centerRight,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.001) // perspectiva
        ..rotateY(isForward ? rotation * pi : (rotation - 1) * pi),
      child: child,
    );
  }
}
```

---

## 15. Estrategia de testing

Siguiendo la pirámide del agente `test-engineer`:

### 15.1 Pirámide de tests

```
         /\
        /E2E\          10% — Flujos completos del usuario
       /──────\
      /Widget  \       20% — Tests de widgets individuales
     /──────────\
    /Unit tests  \     70% — Domain, UseCases, BLoCs, Mappers
   ────────────────
```

### 15.2 Cobertura mínima requerida

| Capa | Cobertura mínima |
|---|---|
| Domain (entities, usecases) | 95% |
| SyncEngine (findWordAt, buildWordMap) | 100% |
| BLoCs | 90% |
| Repositories | 80% |
| Widgets | 75% |
| E2E flows | Flujos críticos del usuario |

### 15.3 Tests del motor de sincronización

```dart
// test/unit/features/tts_engine/alignment_to_word_map_test.dart
void main() {
  group('AlignmentToWordMap', () {
    test('convierte alignment de ElevenLabs correctamente', () {
      final alignment = {
        'characters': ['H','o','l','a',' ','m','u','n','d','o'],
        'character_start_times_seconds': [0.0,0.05,0.1,0.15,0.2,0.25,0.3,0.35,0.4,0.45],
        'character_end_times_seconds':   [0.05,0.1,0.15,0.2,0.25,0.3,0.35,0.4,0.45,0.5],
      };

      final result = AlignmentToWordMap.convert(alignment);

      expect(result.length, equals(2));
      expect(result[0].word, equals('Hola'));
      expect(result[0].startMs, closeTo(0.0, 0.001));
      expect(result[0].endMs, closeTo(200.0, 0.001));
      expect(result[1].word, equals('mundo'));
      expect(result[1].startMs, closeTo(250.0, 0.001));
    });

    test('maneja signos de puntuación correctamente', () { ... });
    test('maneja texto vacío sin crash', () { ... });
    test('maneja texto con saltos de línea', () { ... });
  });

  group('SyncBloc.findWordAt', () {
    test('retorna -1 cuando wordMap está vacío', () { ... });
    test('retorna el índice correcto en el centro del rango', () { ... });
    test('retorna lo-1 en pausa entre palabras', () { ... });
    test('rendimiento: 10,000 palabras en <1ms', () {
      final bloc = SyncBloc(audioPlayer: MockAudioPlayer());
      final bigMap = List.generate(10000, (i) => WordTimestamp(
        index: i, word: 'word$i',
        startMs: i * 300.0, endMs: (i * 300.0) + 250.0,
        charOffset: i * 6,
      ));
      bloc.add(SyncWordMapLoaded(wordMap: bigMap));

      final stopwatch = Stopwatch()..start();
      for (int i = 0; i < 1000; i++) {
        bloc.findWordAt(i * 3000.0); // búsqueda en distintas posiciones
      }
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(1));
    });
  });
}
```

### 15.4 Golden Tests (regresión visual)

```dart
// test/golden/reader_page_test.dart
void main() {
  testGoldens('ReaderPage - tema sepia - iPhone 14', (tester) async {
    await tester.pumpWidgetBuilder(
      const ReaderPage(bookId: 'test-book', chapterId: 'ch-1'),
      surfaceSize: const Size(390, 844),
    );
    await screenMatchesGolden(tester, 'reader_sepia_iphone14');
  });

  testGoldens('ReaderPage - resaltado activo en palabra 42', (tester) async {
    // Verifica que el resaltado visual no ha cambiado de posición
  });
}
```

---

## 16. Pipeline CI/CD

Basado en el agente `devops-engineer`.

### 16.1 Flujo de branches

```
feature/* ──► develop ──► staging ──► main (production)
                │               │
                └── PR checks   └── staging tests + approval
```

### 16.2 GitHub Actions

```yaml
# .github/workflows/flutter_ci.yml
name: Flutter CI/CD

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main, develop]

jobs:
  analyze:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with: { flutter-version: '3.24.0', channel: 'stable' }
      - run: flutter pub get
      - run: flutter analyze --fatal-infos
      - run: dart format --set-exit-if-changed .

  unit_tests:
    needs: analyze
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with: { flutter-version: '3.24.0' }
      - run: flutter pub get
      - run: flutter test --coverage test/unit/
      - name: Coverage gate (95% sync engine, 80% global)
        run: |
          dart pub global activate coverage
          dart pub global run coverage:format_coverage \
            --lcov --in=coverage --out=coverage/lcov.info
          # Falla si coverage < 80%
          lcov --summary coverage/lcov.info

  widget_tests:
    needs: analyze
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with: { flutter-version: '3.24.0' }
      - run: flutter test test/widget/
      - run: flutter test test/golden/ --update-goldens=false

  integration_tests:
    needs: [unit_tests, widget_tests]
    runs-on: macos-latest   # macOS para iOS simulator
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with: { flutter-version: '3.24.0' }
      - name: Start iOS Simulator
        run: xcrun simctl boot "iPhone 15"
      - run: flutter test integration_test/ -d "iPhone 15"

  build_android:
    if: github.ref == 'refs/heads/develop' || github.ref == 'refs/heads/main'
    needs: integration_tests
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with: { flutter-version: '3.24.0' }
      - run: flutter build apk --release --split-per-abi
      - uses: actions/upload-artifact@v4
        with:
          name: android-release
          path: build/app/outputs/apk/release/

  build_ios:
    if: github.ref == 'refs/heads/develop' || github.ref == 'refs/heads/main'
    needs: integration_tests
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with: { flutter-version: '3.24.0' }
      - run: flutter build ios --release --no-codesign

  build_desktop:
    if: github.ref == 'refs/heads/main'
    needs: integration_tests
    strategy:
      matrix:
        os: [macos-latest, windows-latest, ubuntu-latest]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with: { flutter-version: '3.24.0' }
      - run: |
          flutter config --enable-macos-desktop
          flutter config --enable-windows-desktop
          flutter config --enable-linux-desktop
          flutter build ${{ runner.os == 'macOS' && 'macos' || runner.os == 'Windows' && 'windows' || 'linux' }} --release
```

### 16.3 Ambientes

| Ambiente | URL API | Base de datos | TTS Provider |
|---|---|---|---|
| development | http://localhost:3000 | PostgreSQL local | DeviceTTS (gratuito) |
| staging | https://api-staging.lectorsync.app | PostgreSQL staging | Azure TTS (test key) |
| production | https://api.lectorsync.app | PostgreSQL prod (RDS) | ElevenLabs (prod key) |

```dart
// lib/core/constants/app_constants.dart
class AppConstants {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:3000',
  );
  
  static const String ttsProvider = String.fromEnvironment(
    'TTS_PROVIDER',
    defaultValue: 'local',
  );
  
  // Build con: flutter build apk --dart-define=API_BASE_URL=https://api.lectorsync.app
}
```

---

## 17. Seguridad

Siguiendo las recomendaciones del agente `security-auditor`.

### 17.1 Autenticación y tokens

```
- JWT access token: expira en 15 minutos
- Refresh token: expira en 30 días, almacenado en FlutterSecureStorage
- Tokens NO se almacenan en SharedPreferences (no cifrado)
- Renovación automática transparente al usuario
- Revocación de refresh tokens en logout
```

### 17.2 Almacenamiento local seguro

```dart
// lib/core/storage/secure_storage.dart
class SecureStorage {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,  // AES-256 en Android
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );

  // Solo estos datos van en SecureStorage:
  // - access_token
  // - refresh_token
  // - user_id

  // El resto (progreso, configuración) va en Isar (cifrado)
}
```

### 17.3 Seguridad de las API keys

```
NUNCA incluir API keys en el código fuente.
NUNCA incluir API keys en el cliente Flutter.

Las llamadas a ElevenLabs/Azure se hacen SOLO desde el backend.
El cliente Flutter llama al backend propio, que a su vez llama a TTS APIs.
Así las API keys de proveedores nunca se exponen al cliente.
```

### 17.4 Validaciones

```
Backend:
- Todos los inputs validados con Zod antes de llegar al handler
- Archivos EPUB/PDF validados: tipo MIME, tamaño máximo (50MB), contenido
- Rate limiting diferenciado: 100 req/min anónimo, 1000 req/min autenticado
- La generación de audio tiene su propio rate limit: 10 capítulos/hora/usuario

Cliente Flutter:
- No confiar en ningún dato que venga del servidor sin validar el schema
- Verificar integridad de audio descargado (checksum SHA-256)
```

---

## 18. Observabilidad y monitoreo

### 18.1 Métricas del motor de sincronización

```dart
// lib/core/observability/sync_metrics.dart
class SyncMetrics {
  static void recordSyncLatency(double ms) {
    // Métrica crítica: latencia entre audio y resaltado visual
    // Target: < 50ms p99
    Analytics.track('sync.latency_ms', value: ms);
    if (ms > 100) {
      Logger.warning('sync_latency_exceeded', data: {'latency_ms': ms});
    }
  }

  static void recordTTSGenerationTime(int chapterWords, int durationMs) {
    final wordsPerSecond = chapterWords / (durationMs / 1000);
    Analytics.track('tts.generation_speed', value: wordsPerSecond);
  }
}
```

### 18.2 Métricas de producto a monitorear

| Métrica | Target | Alerta |
|---|---|---|
| Sync latency p99 | < 50ms | > 100ms |
| TTS cache hit rate | > 80% | < 60% |
| Audio generation time | < 10s por capítulo | > 30s |
| App crash rate | < 0.1% | > 0.5% |
| Session duration | > 20 min | < 5 min |
| Chapter completion rate | > 60% | < 30% |

### 18.3 Error reporting

```dart
// lib/main.dart
void main() async {
  FlutterError.onError = (details) {
    FirebaseCrashlytics.instance.recordFlutterFatalError(details);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  runApp(const LectorSyncApp());
}
```

---

## 19. Roadmap de desarrollo

### Fase 1 — MVP funcional (Semanas 1–8)

**Objetivo**: Un capítulo, una voz, resaltado por párrafo. Validar que la experiencia engancha.

| Semana | Entregable |
|---|---|
| 1–2 | Setup del proyecto: estructura de carpetas, DI, routing, tema base |
| 3–4 | Feature `library`: importar EPUB, mostrar libro en pantalla |
| 5–6 | Feature `reader`: renderizar texto, controles básicos de audio |
| 7–8 | Feature `tts_engine`: integrar DeviceTTS (offline), resaltado por párrafo |

**Criterio de salida**: Abrir un EPUB y escucharlo mientras se resalta el párrafo actual.

### Fase 2 — Sincronización real (Semanas 9–16)

**Objetivo**: Resaltado palabra por palabra con ElevenLabs. Ambientación sensorial.

| Semana | Entregable |
|---|---|
| 9–10 | ElevenLabsAdapter + AlignmentToWordMap + SyncBloc completo |
| 11–12 | WordSpanWidget con RepaintBoundary, performance a 60fps |
| 13–14 | Sonidos de página, temas de lectura (sepia, night, lamp), hápticos |
| 15–16 | Backend: API de auth + library + audio generation + caché en Redis/S3 |

**Criterio de salida**: Resaltado sub-100ms, experiencia sensorial completa.

### Fase 3 — App nativa completa (Semanas 17–24)

**Objetivo**: Desktop apps, voces por personaje, modo sin pantalla, notas.

| Semana | Entregable |
|---|---|
| 17–18 | macOS + Windows desktop: layout adaptativo, shortcuts, drag & drop |
| 19–20 | NLP: DetectDialogues, voces por personaje con Azure/ElevenLabs |
| 21–22 | Background audio (audio_service), lock screen controls |
| 23–24 | Feature `notes`: subrayados, notas de voz, sincronización con backend |

### Fase 4 — Producto completo (Semanas 25–32)

**Objetivo**: IA, social, y escala.

- Resumen IA por capítulo (Claude API)
- Club de lectura: progreso compartido
- Soporte PDF con pdf_render
- Distribución: App Store, Play Store, Desktop releases
- Analytics, A/B testing, métricas de retención

---

## 20. Convenciones y estándares

### 20.1 Código Dart/Flutter

```yaml
# analysis_options.yaml
include: package:very_good_analysis/analysis_options.yaml

analyzer:
  errors:
    missing_required_param: error
    missing_return: error
  exclude:
    - lib/**.g.dart
    - lib/**.freezed.dart

linter:
  rules:
    prefer_const_constructors: true
    prefer_const_widgets: true
    avoid_print: true
    always_use_package_imports: true
```

### 20.2 Naming conventions

| Elemento | Convención | Ejemplo |
|---|---|---|
| Clases | PascalCase | `SyncBloc`, `WordTimestamp` |
| Archivos | snake_case | `sync_bloc.dart`, `word_timestamp.dart` |
| Variables/métodos | camelCase | `findWordAt()`, `currentWordIndex` |
| Constantes | camelCase | `const maxChunkSize = 500` |
| Privados | `_` prefix | `_wordMap`, `_findWordAt()` |
| BLoC events | Verbo + Noun | `SyncStarted`, `SyncPaused` |
| BLoC states | Noun + Adjective | `SyncPlaying`, `SyncPaused` |

### 20.3 Commit messages (Conventional Commits)

```
feat(reader): add word-by-word highlight with BLoC
fix(sync): handle empty wordMap without crash
perf(sync): replace linear search with binary search
test(tts): add golden tests for ElevenLabs alignment mapper
docs(arch): add ADR for state management decision
chore(deps): upgrade flutter to 3.24.0
```

### 20.4 Pull Request checklist

```markdown
## PR Checklist

### Código
- [ ] Sigue la arquitectura limpia (domain no depende de data)
- [ ] Widgets son `const` donde es posible
- [ ] No hay `BuildContext` fuera de la presentación
- [ ] No hay API keys hardcodeadas

### Tests
- [ ] Unit tests para toda lógica nueva en domain/data
- [ ] Widget test para widgets nuevos
- [ ] Coverage no baja del mínimo definido

### Documentación
- [ ] Métodos públicos tienen dartdoc
- [ ] Si es decisión de arquitectura → ADR actualizado

### Revisión del architect-reviewer
- [ ] SOLID principles respetados
- [ ] Dependencias apuntan hacia adentro (Clean Architecture)
- [ ] Sin dependencias circulares entre features
```

---

## 21. Decisiones de arquitectura (ADRs)

### ADR-001: Flutter sobre React Native + Electron

**Decisión**: Usar Flutter para todas las plataformas.

**Razón**: Flutter dibuja cada píxel con su propio motor (Impeller). No depende de WebView. Garantiza 60fps en la animación de resaltado de palabras y volteo de página. Permite un solo equipo y un solo codebase para iOS, Android, macOS, Windows y Linux (~95% código compartido).

**Consecuencias**: El equipo debe aprender Dart. No reutiliza código web existente.

---

### ADR-002: BLoC sobre Riverpod para el SyncEngine

**Decisión**: Usar `flutter_bloc` para todos los BLoCs, especialmente `SyncBloc`.

**Razón**: `SyncBloc` gestiona un `Stream<Duration>` del reproductor de audio. BLoC tiene soporte nativo para `StreamSubscription` en handlers de eventos. La trazabilidad de eventos es crítica para debugging del motor de sincronización.

**Consecuencias**: Más boilerplate que Riverpod. Mayor testabilidad y explicitidad.

---

### ADR-003: ElevenLabs como proveedor TTS primario con fallback

**Decisión**: ElevenLabs en producción, Azure Neural TTS como backup, DeviceTTS (flutter_tts) como fallback offline.

**Razón**: ElevenLabs devuelve timestamps por carácter (indispensable). Azure es alternativa de calidad con SSML. DeviceTTS garantiza experiencia básica sin internet.

**Consecuencias**: Costo variable según uso. Latencia de 1–5 segundos en primera generación de capítulo.

---

### ADR-004: Isar como base de datos local

**Decisión**: Usar Isar en lugar de SQLite/Drift para el almacenamiento local.

**Razón**: Isar es type-safe, sin código de mapeo manual, con soporte nativo en todas las plataformas Flutter incluyendo desktop. Las queries son asíncronas y no bloquean el UI thread.

**Consecuencias**: Menor conocimiento de la comunidad vs SQLite. Migración de schema requiere más cuidado.

---

## 22. Checklist de inicio del proyecto

### Semana 0 — Setup inicial

```bash
# 1. Crear el proyecto Flutter
flutter create lectorsync \
  --org com.lectorsync \
  --platforms ios,android,macos,windows,linux

# 2. Habilitar desktop
flutter config --enable-macos-desktop
flutter config --enable-windows-desktop
flutter config --enable-linux-desktop

# 3. Estructura base de directorios
mkdir -p lib/{core/{constants,errors,network,storage,platform,theme,di},features/{auth,library,reader,tts_engine,settings,notes}/{{domain/{entities,repositories,usecases},data/{models,datasources,repositories},presentation/{bloc,pages,widgets}}},shared/{widgets,extensions}}

# 4. Dependencias iniciales (pubspec.yaml)
flutter pub add \
  flutter_bloc \
  go_router \
  get_it \
  fpdart \
  dio \
  isar isar_flutter_libs \
  flutter_secure_storage \
  just_audio audio_service \
  epub_kit \
  file_picker \
  lottie \
  freezed_annotation json_annotation

flutter pub add --dev \
  build_runner \
  freezed \
  json_serializable \
  isar_generator \
  bloc_test \
  mocktail \
  golden_toolkit \
  very_good_analysis
```

### Cuentas y servicios a crear antes de empezar

- [ ] Cuenta en ElevenLabs (plan Starter mínimo para timestamps)
- [ ] Cuenta en Azure Cognitive Services (TTS neural)
- [ ] Repositorio en GitHub con branch protection en `main` y `develop`
- [ ] Proyecto en Firebase (Crashlytics + Analytics)
- [ ] AWS account o equivalente para S3 + RDS (staging)
- [ ] App Store Connect account (para TestFlight desde semana 8)
- [ ] Google Play Console account

### Variables de entorno a configurar

```bash
# Backend (.env)
DATABASE_URL=postgresql://...
REDIS_URL=redis://...
JWT_SECRET=...
ELEVENLABS_API_KEY=...
AZURE_TTS_KEY=...
AZURE_TTS_REGION=...
S3_BUCKET=...
S3_REGION=...
AWS_ACCESS_KEY_ID=...
AWS_SECRET_ACCESS_KEY=...

# Flutter (por ambiente, NO en código)
# Usar --dart-define en build o flutter_dotenv en desarrollo
API_BASE_URL=http://localhost:3000
TTS_PROVIDER=local
ENVIRONMENT=development
```

---

*Documento generado con el apoyo de los agentes: flutter-expert, backend-architect, architect-reviewer, devops-engineer, test-engineer, security-auditor.*  
*Versión: 1.0 — Fecha: Marzo 2026*
