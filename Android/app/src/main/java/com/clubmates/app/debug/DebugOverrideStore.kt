package com.clubmates.app.debug

import android.content.Context
import android.content.SharedPreferences
import androidx.core.content.edit

/**
 * Registry-driven engineering override store.
 *
 * To add a new override:
 *   1. Add an entry to [Keys] with the right [OverrideKey] type.
 *   2. Read it at the call site: DebugOverrideStore.get(context, DebugOverrideStore.Keys.YourKey)
 *
 * Non-null value in prefs → override wins. Missing / blank → real value wins.
 */
object DebugOverrideStore {

    sealed class OverrideKey<T>(
        val key: String,
        val label: String,
        val description: String,
        val type: Type,
        val default: T
    ) {
        enum class Type { STRING, DOUBLE, BOOLEAN }

        class StringKey(key: String, label: String, description: String) :
            OverrideKey<String?>(key, label, description, Type.STRING, null)

        class DoubleKey(key: String, label: String, description: String) :
            OverrideKey<Double?>(key, label, description, Type.DOUBLE, null)

        class BooleanKey(key: String, label: String, description: String, default: Boolean = false) :
            OverrideKey<Boolean>(key, label, description, Type.BOOLEAN, default)
    }

    // ── Registry ────────────────────────────────────────────────────────────────
    // Add new overrides here — that's the only file you need to touch.
    // To add a new override:
    //   val YourNewKey = OverrideKey.DoubleKey(
    //       key = "your_new_key",
    //       label = "Section — Field label",
    //       description = "What this overrides"
    //   )
    // Then add it to the `all` list below. The UI renders it automatically.
    object Keys {
        val OverrideLocationLat = OverrideKey.DoubleKey(
            key = "override_location_lat",
            label = "Location — Latitude",
            description = "Override GPS latitude used for check-in. Leave blank to use real device location."
        )
        val OverrideLocationLng = OverrideKey.DoubleKey(
            key = "override_location_lng",
            label = "Location — Longitude",
            description = "Override GPS longitude used for check-in. Leave blank to use real device location."
        )

        val all: List<OverrideKey<*>> = listOf(
            OverrideLocationLat,
            OverrideLocationLng
        )
    }

    // ── Read ─────────────────────────────────────────────────────────────────────

    @Suppress("UNCHECKED_CAST")
    fun <T> get(context: Context, key: OverrideKey<T>): T {
        val prefs = prefs(context)
        return when (key) {
            is OverrideKey.StringKey -> {
                val v = prefs.getString(key.key, null)
                (if (v.isNullOrBlank()) null else v) as T
            }
            is OverrideKey.DoubleKey -> {
                val raw = prefs.getString(key.key, null)
                (raw?.toDoubleOrNull()) as T
            }
            is OverrideKey.BooleanKey -> {
                prefs.getBoolean(key.key, key.default) as T
            }
            else -> key.default
        }
    }

    // ── Write ─────────────────────────────────────────────────────────────────────

    fun setString(context: Context, key: OverrideKey<*>, value: String) {
        prefs(context).edit { putString(key.key, value) }
    }

    fun setBoolean(context: Context, key: OverrideKey.BooleanKey, value: Boolean) {
        prefs(context).edit { putBoolean(key.key, value) }
    }

    fun clear(context: Context, key: OverrideKey<*>) {
        prefs(context).edit { remove(key.key) }
    }

    fun clearAll(context: Context) {
        prefs(context).edit { clear() }
    }

    // ── Raw string for display ─────────────────────────────────────────────────────

    fun getRawString(context: Context, key: OverrideKey<*>): String {
        return when (key) {
            is OverrideKey.BooleanKey -> prefs(context).getBoolean(key.key, key.default).toString()
            else -> prefs(context).getString(key.key, "") ?: ""
        }
    }

    private fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences("debug_overrides", Context.MODE_PRIVATE)
}
