package com.lectorsync.lectorsync

import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Extiende [AudioServiceActivity] y no `FlutterActivity` porque audio_service
 * comparte el motor de Flutter con su servicio de reproducción: así la voz
 * sigue leyendo con la pantalla apagada (ADR 12).
 */
class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // El motor sobrevive a la actividad; al volver a engancharse una
        // actividad nueva, el manejador se registra otra vez con ella.
        val quietMode = ReadingQuietMode(applicationContext)
        // Red de seguridad: si el proceso anterior murió con el "No molestar"
        // del lector puesto, se quita al arrancar. Va aquí y no en Dart porque
        // el motor de audio_service ejecuta main() antes de que esta actividad
        // registre el canal, y la llamada desde Dart se perdería en silencio.
        // Una vez por proceso: si el motor sobrevive a la actividad, el estado
        // de Dart sigue siendo válido y no hay que tocarlo.
        if (!quietCleanupDone) {
            quietCleanupDone = true
            quietMode.deactivate()
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lectorsync/quiet_mode")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isSupported" -> result.success(quietMode.isSupported())
                    "hasAccess" -> result.success(quietMode.hasAccess())
                    "openAccessSettings" -> result.success(quietMode.openAccessSettings(this))
                    "activate" -> result.success(quietMode.activate())
                    "deactivate" -> {
                        quietMode.deactivate()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private companion object {
        /** Vive lo que el proceso: un arranque nuevo vuelve a limpiar. */
        var quietCleanupDone = false
    }
}
