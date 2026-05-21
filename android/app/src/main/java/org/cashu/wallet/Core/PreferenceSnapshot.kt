package org.cashu.wallet.Core

import android.content.SharedPreferences

internal data class PreferenceSnapshot(
    val keys: Set<String>,
    val values: Map<String, Any>,
)

internal fun SharedPreferences.snapshot(keys: Set<String>): PreferenceSnapshot {
    val currentValues = all
    val values = keys.mapNotNull { key ->
        currentValues[key]?.let { value -> key to value.snapshotValue() }
    }.toMap()
    return PreferenceSnapshot(keys = keys, values = values)
}

internal fun SharedPreferences.restore(snapshot: PreferenceSnapshot) {
    val editor = edit()
    snapshot.keys.forEach { key ->
        when (val value = snapshot.values[key]) {
            is String -> editor.putString(key, value)
            is Set<*> -> editor.putStringSet(key, value.filterIsInstance<String>().toSet())
            is Int -> editor.putInt(key, value)
            is Long -> editor.putLong(key, value)
            is Float -> editor.putFloat(key, value)
            is Boolean -> editor.putBoolean(key, value)
            null -> editor.remove(key)
            else -> editor.remove(key)
        }
    }
    editor.apply()
}

private fun Any.snapshotValue(): Any = when (this) {
    is Set<*> -> filterIsInstance<String>().toSet()
    else -> this
}
