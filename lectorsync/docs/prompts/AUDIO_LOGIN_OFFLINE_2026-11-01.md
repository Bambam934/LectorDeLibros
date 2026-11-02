# Encargo: ambiente en Windows y arranque sin login en offline (2026-11-01)

Spec de Claude para Antigravity. Decisiones aprobadas por el usuario el 2026-11-01. Rama `encargo/audio-login-offline`, ya creada desde `desarrollo`, con el paquete `just_audio_windows` ya añadido por Claude en su primer commit.

**Directorio de trabajo: `lectorsync/`.** Todas las rutas y comandos de esta spec son relativos a esa carpeta. Tú no añades ni quitas dependencias.

## Contexto verificado (hechos medidos por Claude)

1. `just_audio_windows` hace sonar el audio en Windows, pero **`play()` llamado justo después de cargar la fuente, sin otra llamada nativa con `await` en medio, se pierde sin error**: vuelve en 5 ms con `playing=false` (reproducido 2 de 2; `just_audio-0.10.5/lib/just_audio.dart:1099`). Con `await setLoopMode(...)` entre la carga y el `play()`, suena y hace bucle (3 de 3).
2. La app hace ese patrón: `lib/features/reader/data/repositories/ambient_sound_repository.dart:20` pone el bucle en el constructor sin `await`, y las líneas `103-104` y `120-123` cargan y llaman a `play()` seguidos.
3. Otro fallo en el mismo archivo: `restorePreferences` (`:91-109`) asigna `_current` sin cargar la fuente si `enabled` es false. Después, `play(sound)` con ese mismo sonido se salta la carga (`:118`) y no suena. `AudioPlayer.audioSource` existe (`just_audio.dart:462`) y es null si no hay fuente.
4. En offline el login no protege nada: `LocalAuthRepository` acepta cualquier texto no vacío (`lib/features/auth/data/repositories/local_auth_repository.dart:10`). `AuthCubit.checkAuthStatus` emite `Unauthenticated` para todo lo que no sea remoto (`lib/features/auth/presentation/cubit/auth_cubit.dart:29-44`).
5. `lib/app.dart:21` llama a `checkAuthStatus()` antes de construir el router (`:49`). La rama local no tiene `await`, así que el estado queda en `Authenticated` antes de la primera navegación. El `redirect` de `lib/core/router/app_router.dart:22` lleva entonces a la biblioteca.
6. `test/widget_test.dart` usa un `_FakeAuthRepository` que no es local ni remoto y espera ver el login. Por eso la condición nueva debe ser `is LocalAuthRepository`, no un simple `else`.

## Decisiones (no hay nada abierto)

| Tema | Decisión |
|---|---|
| Dónde se fija el bucle | Al final de `_loadSource`, con `await`. Sale del constructor. Vale para todas las plataformas. |
| Fuente sin cargar | `play()` carga también si `_player.audioSource == null`. |
| Login en offline | `checkAuthStatus` emite `Authenticated` con `LocalAuthRepository`. |
| Botón «Cerrar sesión» | Oculto en offline, con `canLogout` en `AuthCubit`. |
| Pantallas de login y registro | No se borran: siguen en uso en modo conectado. |
| Voces de servidor | No se tocan: solo corren en modo conectado. |

## Pasos

### P1. Ambiente (`lib/features/reader/data/repositories/ambient_sound_repository.dart`)

1. Constructor. Deja exactamente:
   ```dart
   AmbientSoundRepository() : _player = AudioPlayer();
   ```
2. `_loadSource`. Sustituye el cuerpo por:
   ```dart
   Future<void> _loadSource(AmbientSound sound) async {
     if (sound.isSynth) {
       await _player.setAudioSource(await _synthSource(sound));
     } else if (sound.isAsset) {
       await _player.setAsset(sound.assetPath);
     } else {
       await _player.setUrl(sound.source);
     }
     // Loop forever: el ambiente es un fondo continuo. Va aquí, con `await`,
     // y no en el constructor: en Windows, un `play()` justo después de cargar
     // se pierde sin error si no hay otra llamada nativa en medio.
     await _player.setLoopMode(LoopMode.one);
   }
   ```
   Conserva su comentario de documentación.
3. `play`. Cambia la condición del `if` por:
   ```dart
   if (_current?.id != sound.id || _player.audioSource == null) {
   ```
   No cambies nada más del método.
4. Commit P1, con los dos comandos de la lista.

### P2. Sin login en offline

1. `lib/features/auth/presentation/cubit/auth_cubit.dart`:
   - añade `import '../../data/repositories/local_auth_repository.dart';` antes del import de `remote_auth_repository.dart`;
   - en `checkAuthStatus`, justo antes del `else` final, añade:
     ```dart
     } else if (_authRepository is LocalAuthRepository) {
       // Sin servidor no hay cuenta que proteger: se entra directo.
       emit(const Authenticated());
     ```
   - debajo de `final AuthRepository _authRepository;` añade:
     ```dart

     /// En offline no hay sesión que cerrar.
     bool get canLogout => _authRepository is! LocalAuthRepository;
     ```
2. `lib/features/library/presentation/pages/library_page.dart`, en `_LogoutButton.build`, añade como primera línea:
   ```dart
   if (!context.read<AuthCubit>().canLogout) return const SizedBox.shrink();
   ```
3. Crea `test/features/auth/presentation/cubit/auth_cubit_test.dart` con exactamente estos casos, usando `flutter_test`:
   - `LocalAuthRepository`: tras `checkAuthStatus()`, `cubit.state` es `Authenticated` y `canLogout` es false;
   - un repositorio falso que implementa `AuthRepository` (igual que `_FakeAuthRepository` de `test/widget_test.dart`): tras `checkAuthStatus()`, `cubit.state` es `Unauthenticated` y `canLogout` es true.
   Cierra el cubit al final de cada test. No uses `bloc_test` ni paquetes nuevos.
4. Corre las verificaciones y haz el commit P2, con los comandos de la lista.

## Comandos permitidos, letra por letra

Copia cada uno exactamente. Cualquier otro comando corta tu turno. Además de estos están permitidos `git status`, `git diff` y `git log`, sin argumentos.

```text
flutter analyze
flutter test
flutter test test/features/auth/presentation/cubit/auth_cubit_test.dart
git add lib/features/reader/data/repositories/ambient_sound_repository.dart
git commit -F C:\Users\bamba\AppData\Local\Temp\claude\C--Users-bamba-Music-LectorDeLibros\c6d66d43-82b3-4f45-849c-97b389fa2a71\scratchpad\msg_audio_p1.txt
git add lib/features/auth/presentation/cubit/auth_cubit.dart lib/features/library/presentation/pages/library_page.dart test/features/auth/presentation/cubit/auth_cubit_test.dart
git commit -F C:\Users\bamba\AppData\Local\Temp\claude\C--Users-bamba-Music-LectorDeLibros\c6d66d43-82b3-4f45-849c-97b389fa2a71\scratchpad\msg_audio_p2.txt
```

Los mensajes de commit ya están escritos en esos archivos: no los cambies y no uses `-m`. No hagas push. No añadas firma de IA.

## Criterios de aceptación

- **CA-1.** `_player.setLoopMode` aparece una sola vez en el archivo de P1, dentro de `_loadSource`, con `await`, después de la carga.
- **CA-2.** El constructor de `AmbientSoundRepository` no tiene cuerpo.
- **CA-3.** La condición de `play` incluye `_player.audioSource == null`.
- **CA-4.** `checkAuthStatus` emite `Authenticated` con `LocalAuthRepository` y `Unauthenticated` con un repositorio falso (test nuevo).
- **CA-5.** `canLogout` es false con `LocalAuthRepository` y true con el falso (test nuevo). `_LogoutButton` devuelve `SizedBox.shrink()` si `canLogout` es false.
- **CA-6.** `flutter analyze` termina con «No issues found!».
- **CA-7.** `flutter test` pasa entero; la cifra base es 351 tests, más los nuevos. `test/widget_test.dart` no cambia.
- **CA-8.** Solo cambian los 4 archivos del alcance, más el reporte sin commitear. Hay exactamente 2 commits tuyos.

## Alcance

- **Sí**:
  - `lib/features/reader/data/repositories/ambient_sound_repository.dart`
  - `lib/features/auth/presentation/cubit/auth_cubit.dart`
  - `lib/features/library/presentation/pages/library_page.dart`
  - `test/features/auth/presentation/cubit/auth_cubit_test.dart` (nuevo)
  - `docs/prompts/AUDIO_LOGIN_OFFLINE_2026-11-01.reporte.md` (nuevo, sin commitear)
- **No**: todo lo demás. En particular `pubspec.yaml`, `pubspec.lock`, `windows/`, `android/`, las pantallas de login y registro, `app_router.dart`, `app.dart` y `test/widget_test.dart`.

## Verificación que hará Claude (no te corresponde)

La app real en Windows: arranca directo en la biblioteca y el ambiente suena al primer intento.
