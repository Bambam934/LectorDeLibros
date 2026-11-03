# Reporte: IMPORTACION_2026-10-22

**Constructor: Antigravity**

## Commits
- `626edc3` `fix(library): leer libros importados con stream y validar límite antes de cargar` — P1
- `85dccbf` `build(android): filtrar arquitecturas en release para generar APK solo ARM` — P2

## Criterios de aceptación
- CA-1: CUMPLE — `test/features/library/presentation/utils/picked_book_reader_test.dart:14-53` comprueba que con `size = customLimit + 1` y `size = kMaxImportBytes + 1` devuelve `PickedBookTooLarge` y no se suscribe al stream (`subscribed == false`, comprobado con `onListen: fail(...)`). En `lectorsync/lib/features/library/presentation/utils/picked_book_reader.dart:67-69`, la validación `if (file.size > maxBytes)` retorna inmediatamente antes de acceder a `file.readStream`.
- CA-2: CUMPLE — `test/features/library/presentation/utils/picked_book_reader_test.dart:55-73` comprueba que con `size <= maxBytes` y un `readStream` de 3 trozos, devuelve `PickedBookBytes` con los bytes concatenados exactos (`Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9, 10])`). En `lectorsync/lib/features/library/presentation/utils/picked_book_reader.dart:71-82`, `BytesBuilder` acumula los fragmentos del stream.
- CA-3: CUMPLE — `test/features/library/presentation/utils/picked_book_reader_test.dart:75-98` comprueba que sin `readStream` y con `bytes` devuelve `PickedBookBytes` con esos bytes, y sin ninguno de los dos devuelve `PickedBookUnreadable`. Implementado en `lectorsync/lib/features/library/presentation/utils/picked_book_reader.dart:84-90`.
- CA-4: CUMPLE — `lectorsync/lib/features/library/presentation/pages/library_page.dart:70-75` pasa `withData: false` y `withReadStream: true` a `FilePicker.platform.pickFiles`. `withData: true` ya no existe en el archivo. En `library_page.dart:81-87`, la invocación de `FilePicker.platform.clearTemporaryFiles()` está protegida por `!kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)` y envuelta en un bloque `try { ... } catch (_) {}`.
- CA-5: CUMPLE — `lectorsync/lib/features/library/data/repositories/local_library_repository.dart:31` define `static const maxImportBytes = kMaxImportBytes;` importada de `lectorsync/lib/core/constants/import_limits.dart:5`. Los 3 tests de `lectorsync/test/features/library/data/repositories/local_library_repository_test.dart:13-51` siguen pasando sin cambios.
- CA-6: CUMPLE — `flutter build apk --release` compila correctamente (`build/app/outputs/flutter-apk/app-release.apk`). La inspección de entradas ZIP mediante PowerShell reporta únicamente `arm64-v8a` y `armeabi-v7a`, sin ninguna entrada `lib/x86_64/`. Tamaño: 52.02 MiB (54,548,933 bytes).
- CA-7: CUMPLE — `flutter build apk --debug` compila correctamente (`build/app/outputs/flutter-apk/app-debug.apk`). La inspección de entradas ZIP reporta `arm64-v8a`, `armeabi-v7a` y `x86_64`. Tamaño: 184.80 MiB (193,772,500 bytes).

## Pruebas
- flutter analyze: limpio (`No issues found! (ran in 12.8s)`)
- flutter test: 351 pasan / 0 fallan (suite completa ejecutada desde `lectorsync/`)
- APK release: `arm64-v8a`, `armeabi-v7a` · 52.02 MiB (54,548,933 bytes)
- APK debug: `arm64-v8a`, `armeabi-v7a`, `x86_64` · 184.80 MiB (193,772,500 bytes)
- Comprobaciones con el buscador:
  - `withData: true`: 0 ocurrencias en `library_page.dart` (salida vacía, código de retorno 1 de `git grep`).
  - `clearTemporaryFiles`: aparece únicamente en `library_page.dart:85`.
  - `abiFilters`: aparece únicamente en el bloque `buildTypes.release` de `build.gradle.kts:84-85`.

## Archivos tocados
- .claude/docs/GETTING-STARTED.md
- lectorsync/android/app/build.gradle.kts
- lectorsync/lib/core/constants/import_limits.dart
- lectorsync/lib/features/library/data/repositories/local_library_repository.dart
- lectorsync/lib/features/library/presentation/pages/library_page.dart
- lectorsync/lib/features/library/presentation/utils/picked_book_reader.dart
- lectorsync/test/features/library/presentation/utils/picked_book_reader_test.dart

## Afirmaciones retiradas
- Verificación en dispositivo físico Pixel (`adb shell run-as com.lectorsync.lectorsync ls cache`): retirada de las afirmaciones del constructor y señalada como prueba pendiente en hardware real para el usuario, dado que la ejecución se realiza en un entorno sin dispositivo Android conectado por ADB.

## Dudas
- En `lectorsync/android/app/build.gradle.kts`, la instrucción original era `ndk { abiFilters += listOf("armeabi-v7a", "arm64-v8a") }`. Sin embargo, `dev.flutter.flutter-gradle-plugin` (ver `FlutterPlugin.kt:170-178`) pre-popula `abiFilters` con `DEFAULT_PLATFORMS` (`armeabi-v7a`, `arm64-v8a`, `x86_64`). El operador `+=` realizaba una unión (`addAll`) sobre el `MutableSet`, manteniendo `x86_64` en el APK de release (79.4 MB). Se decidió anteponer `abiFilters.clear()` dentro del bloque `release` para eliminar los filtros por defecto de Flutter antes de agregar las dos arquitecturas ARM, alcanzando el filtrado estricto exigido por CA-6 (52.02 MiB).
- En `lectorsync/test/features/library/presentation/utils/picked_book_reader_test.dart` (CA-1), el stream de control se creó con `StreamController<List<int>>.broadcast(...)` y cierre con `unawaited(controller.close())`. En Dart, invocar `await controller.close()` sobre un `StreamController` de suscripción única que jamás tuvo oyentes queda esperando indefinidamente a que se consuma el evento done, provocando timeout de 30 segundos. Con `.broadcast`, `onListen` detecta cualquier suscripción no deseada de inmediato sin bloquear el ciclo de test.
