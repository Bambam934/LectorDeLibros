# Encargo: importación sin cargar de más y APK de release solo ARM (2026-10-22)

Encargo de diseño (Claude) para un constructor (Antigravity). Lote A aprobado por el usuario el 2026-10-22 («vamos con el lote A»). Base: `desarrollo`.

## Contexto verificado

- **Importación hoy.** `lectorsync/lib/features/library/presentation/pages/library_page.dart:67-94` (`_importBook`) llama a `FilePicker.platform.pickFiles(..., withData: true)`. Eso carga el archivo entero en memoria antes de que nadie mire su tamaño. El tope de 50 MB se aplica después, en `LocalLibraryRepository.importBook`: `local_library_repository.dart:30` (`maxImportBytes`) y `:61`. Si `picked.bytes` es null, muestra la SnackBar «No se pudo leer el archivo seleccionado.» (`library_page.dart:78-86`).
- **file_picker instalado: 8.1.7** (`lectorsync/pubspec.lock`). En esa versión:
  - `withData` vale `true` en web y `false` en el resto (`file_picker-8.1.7/lib/src/file_picker.dart:52`);
  - `withReadStream: true` da `PlatformFile.readStream` (`Stream<List<int>>?`, `platform_file.dart:59`) en todas las plataformas, web incluida (`_internal/file_picker_web.dart:111`);
  - `PlatformFile.size` (`platform_file.dart:63`) está disponible sin leer el contenido;
  - `clearTemporaryFiles()` solo está implementado en Android/iOS (`file_picker_io.dart:53`); en el resto lanza `UnimplementedError` (`file_picker.dart:107-108`).
- **Copia en caché.** En Android, file_picker copia el archivo elegido a la caché de la app y no la borra; `clearTemporaryFiles()` la borra (supuesto basado en la documentación del paquete; confirmar en el Pixel).
- **Capas.** `library_page.dart` (presentación) no debe importar el `data` de la propia feature para leer el tope. Ya existe `lectorsync/lib/core/constants/` (solo `route_constants.dart`).
- **Tests.** Se escriben con `flutter_test`, como `test/features/library/data/repositories/local_library_repository_test.dart`. `PlatformFile` se puede construir a mano con `name`, `size` y `readStream`.
- **APK de release.** No hay script de build. El comando documentado es `flutter build apk --release` (`.claude/docs/GETTING-STARTED.md:57`), que genera un APK universal con `lib/x86_64/`, unos 27 MiB que solo usan los emuladores. `lectorsync/android/app/build.gradle.kts:74-82` (`buildTypes.release`) no filtra ABIs. No se usa `--split-per-abi`: multiplica el `versionCode` y provoca `INSTALL_FAILED_VERSION_DOWNGRADE`.

## Puntos

- **P1. Importar sin cargar de más.**
  - Una constante `kMaxImportBytes = 50 * 1024 * 1024` en `lib/core/constants/import_limits.dart`, con un comentario que cite V-12 y `backend/src/app.ts`. `LocalLibraryRepository.maxImportBytes` pasa a valer `kMaxImportBytes`.
  - Una función pura y testeable `readPickedBook(PlatformFile file, {int maxBytes = kMaxImportBytes})` en `lib/features/library/presentation/utils/picked_book_reader.dart`. Devuelve un resultado con tres casos: bytes leídos, demasiado grande o ilegible.
    - Si `file.size > maxBytes`, devuelve «demasiado grande» **sin suscribirse** a `readStream`.
    - Si hay `readStream`, junta sus trozos en un `Uint8List`.
    - Si no hay `readStream` pero sí `bytes`, usa `bytes`.
    - Si no hay ninguno, devuelve «ilegible».
  - `_importBook` pide el archivo con `withData: false, withReadStream: true` y usa `readPickedBook`.
    - Si es demasiado grande: SnackBar «El archivo pesa más de 50 MB, el máximo para importar.» y no despacha nada.
    - Si es ilegible: la SnackBar actual.
    - Tras leer, solo en Android/iOS (`!kIsWeb` y `defaultTargetPlatform` android o iOS), llama a `FilePicker.platform.clearTemporaryFiles()` dentro de un `try/catch` que ignore los errores. Así se borra la copia de la caché en todos los casos, también cuando se rechaza.
- **P2. Release solo ARM.**
  - En `buildTypes.release` de `build.gradle.kts`: `ndk { abiFilters += listOf("armeabi-v7a", "arm64-v8a") }`, con un comentario que explique el porqué (x86_64 solo sirve en emuladores, unos 27 MiB).
  - Debug no cambia.
  - En `GETTING-STARTED.md:57`, el comentario del comando dice que el APK de release es solo ARM.

## Restricciones

- **C1.** Solo los archivos de la lista «sí».
- **C2.** No se cambian la interfaz `LibraryRepository.importBook(filename, bytes)`, el `LibraryBookImported`, el `RemoteLibraryRepository` ni el bloc. Pasar a streams de punta a punta queda fuera de este lote (YAGNI). Los libros de 50 MB o menos siguen llegando al repositorio como bytes.
- **C3.** Nada de `dart:io` en los archivos nuevos ni en `library_page.dart`. Usar `kIsWeb` y `defaultTargetPlatform` de `package:flutter/foundation.dart`.
- **C4.** No subir file_picker de versión, que está fijado a propósito. No añadir dependencias.
- **C5.** En `build.gradle.kts` no se tocan la firma, `targetSdk` ni `compileSdk`, ni sus comentarios. No se abren ni se leen `key.properties` ni `*.jks`. Construir el APK los usa de forma implícita, y eso está permitido.
- **C6.** Comentarios y mensajes en español; identificadores en inglés.

## Criterios de aceptación

- **CA-1.** `readPickedBook` con `size = maxBytes + 1` devuelve «demasiado grande» y no se suscribe al stream. Se comprueba con un stream que falla el test si alguien lo escucha.
- **CA-2.** Con `size <= maxBytes` y un `readStream` de 3 trozos, devuelve los bytes concatenados exactos.
- **CA-3.** Sin `readStream` y con `bytes`, devuelve esos bytes. Sin ninguno de los dos, devuelve «ilegible».
- **CA-4.** `library_page.dart` usa `withData: false` y `withReadStream: true`, y deja de usar `withData: true`. `clearTemporaryFiles` aparece solo detrás de la guarda de Android/iOS y dentro de `try`.
- **CA-5.** `LocalLibraryRepository.maxImportBytes == kMaxImportBytes`, y los tests de `local_library_repository_test.dart` siguen pasando sin cambios.
- **CA-6.** `flutter build apk --release` termina bien y el APK (`build/app/outputs/flutter-apk/app-release.apk`, que es un zip) **no** tiene entradas `lib/x86_64/`, pero sí `lib/arm64-v8a/` y `lib/armeabi-v7a/`. El reporte da el tamaño del APK.
- **CA-7.** `flutter build apk --debug` sigue terminando bien. El reporte dice qué ABIs trae, sin exigir ninguna.

## Pruebas

Desde `lectorsync/`:
- `flutter analyze`: sin avisos.
- `flutter test`: todo verde, con el test nuevo `test/features/library/presentation/utils/picked_book_reader_test.dart`, que cubre CA-1 a CA-3.
- `flutter build apk --release` y `flutter build apk --debug`, más la lista de entradas del APK. En PowerShell:
  ```powershell
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  [IO.Compression.ZipFile]::OpenRead('build/app/outputs/flutter-apk/app-release.apk').Entries.FullName | Where-Object { $_ -like 'lib/*' } | ForEach-Object { $_.Split('/')[1] } | Sort-Object -Unique
  ```

Comprobaciones con el buscador:
- `withData: true` ya no aparece en `library_page.dart`.
- `clearTemporaryFiles` aparece solo en `library_page.dart`.
- `abiFilters` aparece solo en el bloque `release` de `build.gradle.kts`.

**Verificación pendiente en dispositivo** (no la hace el constructor): en el Pixel, importar un PDF y comprobar que la caché de file_picker queda vacía:
```bash
adb shell run-as com.lectorsync.lectorsync ls cache
```

## Alcance

- **Sí**:
  - `lectorsync/lib/core/constants/import_limits.dart` (nuevo)
  - `lectorsync/lib/features/library/presentation/utils/picked_book_reader.dart` (nuevo)
  - `lectorsync/test/features/library/presentation/utils/picked_book_reader_test.dart` (nuevo)
  - `lectorsync/lib/features/library/presentation/pages/library_page.dart` (solo `_importBook` y sus imports)
  - `lectorsync/lib/features/library/data/repositories/local_library_repository.dart` (solo la constante)
  - `lectorsync/android/app/build.gradle.kts` (solo el bloque `release`)
  - `.claude/docs/GETTING-STARTED.md` (solo la línea 57)
- **No**: todo lo demás. En particular `CLAUDE.md`, el resto de `.claude/`, `.env*`, `android/key.properties`, `*.jks`, `pubspec.yaml`, `pubspec.lock` y el backend.

## Entrega

- Rama `encargo/importacion-2026-10-22`, creada con `git switch -c encargo/importacion-2026-10-22 --track desarrollo`.
- Un commit por punto, en español y con el formato `tipo(área): verbo imperativo`:
  - P1 → `fix(library): …`;
  - P2 → `build(android): …`.
- **Sin firma de IA ni `Co-Authored-By`** (preferencia dura del usuario). Mensajes con tildes mediante `git commit -F archivo`.
- Sin push.
- Reporte en `docs/prompts/IMPORTACION_2026-10-22_CONSTRUCCION.reporte.md`, sin commitear.
