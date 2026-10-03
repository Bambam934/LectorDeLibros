package com.lectorsync.lectorsync

import android.app.Activity
import android.app.AutomaticZenRule
import android.app.NotificationManager
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.service.notification.Condition
import android.service.notification.ZenPolicy
import androidx.annotation.RequiresApi

/**
 * "No molestar" mientras se lee, con una regla propia de la app (ADR 12).
 *
 * Una [AutomaticZenRule] y no `setInterruptionFilter`: la regla se suma a los
 * modos del usuario, y apagarla no toca su No molestar manual ni sus modos
 * automáticos. Cambiar el filtro global, en cambio, al salir apagaba también
 * cualquier modo del usuario que hubiera empezado entretanto ("Dormir" a las
 * 23:00, por ejemplo), y se quedaba puesto si la app moría.
 *
 * Filtro PRIORITY: pasan las excepciones del usuario (favoritos, alarmas,
 * llamadas repetidas). La política permite la multimedia de forma explícita;
 * si no, la regla silenciaría la propia voz de lectura.
 */
class ReadingQuietMode(private val context: Context) {
    private val notificationManager =
        context.getSystemService(NotificationManager::class.java)
    private val prefs =
        context.getSharedPreferences("reading_quiet_mode", Context.MODE_PRIVATE)

    /** `setAutomaticZenRuleState` existe desde Android 10. */
    fun isSupported(): Boolean = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q

    fun hasAccess(): Boolean = notificationManager.isNotificationPolicyAccessGranted

    /**
     * Abre la pantalla de "Acceso a No molestar". Se intenta y se captura el
     * fallo en vez de consultar antes con `resolveActivity`: desde Android 11
     * la visibilidad de paquetes puede ocultar esa actividad a la consulta
     * aunque exista.
     */
    fun openAccessSettings(activity: Activity): Boolean =
        try {
            activity.startActivity(Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS))
            true
        } catch (e: ActivityNotFoundException) {
            false
        }

    fun activate(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q || !hasAccess()) return false
        return try {
            notificationManager.setAutomaticZenRuleState(ensureRule(), condition(Condition.STATE_TRUE))
            true
        } catch (e: Exception) {
            false
        }
    }

    /** Nunca lanza: es la operación que tiene que salir bien siempre. */
    fun deactivate() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q || !hasAccess()) return
        val id = prefs.getString(KEY_RULE_ID, null) ?: return
        try {
            notificationManager.setAutomaticZenRuleState(id, condition(Condition.STATE_FALSE))
        } catch (e: Exception) {
            // La regla pudo borrarla el usuario; entonces ya no silencia nada.
        }
    }

    /** La regla se crea una vez y se reutiliza; si el usuario la borró, se recrea. */
    @RequiresApi(Build.VERSION_CODES.Q)
    private fun ensureRule(): String {
        prefs.getString(KEY_RULE_ID, null)?.let { id ->
            if (notificationManager.getAutomaticZenRule(id) != null) return id
        }
        // Desde Android 15 se prefiere AutomaticZenRule.Builder, pero este
        // constructor sigue vigente y es el que cubre de Android 10 en adelante.
        @Suppress("DEPRECATION")
        val rule = AutomaticZenRule(
            "Lectura (LectorSync)",
            null,
            ComponentName(context, MainActivity::class.java),
            CONDITION_ID,
            ZenPolicy.Builder().allowMedia(true).build(),
            NotificationManager.INTERRUPTION_FILTER_PRIORITY,
            true,
        )
        val id = notificationManager.addAutomaticZenRule(rule)
        prefs.edit().putString(KEY_RULE_ID, id).apply()
        return id
    }

    private fun condition(state: Int) = Condition(CONDITION_ID, "Leyendo en LectorSync", state)

    private companion object {
        const val KEY_RULE_ID = "rule_id"
        val CONDITION_ID: Uri = Uri.parse("condition://com.lectorsync.lectorsync/reading")
    }
}
