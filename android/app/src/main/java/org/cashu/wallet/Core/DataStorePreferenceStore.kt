package org.cashu.wallet.Core

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.SharedPreferencesMigration
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.MutablePreferences
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.floatPreferencesKey
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.longPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.core.stringSetPreferencesKey
import androidx.datastore.preferences.preferencesDataStoreFile
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking

internal class DataStorePreferenceStore(
    context: Context,
    name: String,
) {
    private val dataStore = DataStorePreferenceRegistry.store(context, name)

    fun string(key: String): String? = read()[stringPreferencesKey(key)]

    fun putString(key: String, value: String?) {
        if (value == null) {
            remove(key)
        } else {
            edit { preferences -> preferences[stringPreferencesKey(key)] = value }
        }
    }

    fun boolean(key: String, defaultValue: Boolean): Boolean =
        read()[booleanPreferencesKey(key)] ?: defaultValue

    fun putBoolean(key: String, value: Boolean) {
        edit { preferences -> preferences[booleanPreferencesKey(key)] = value }
    }

    fun long(key: String, defaultValue: Long): Long =
        read()[longPreferencesKey(key)] ?: defaultValue

    fun putLong(key: String, value: Long) {
        edit { preferences -> preferences[longPreferencesKey(key)] = value }
    }

    fun keys(): Set<String> = all().keys

    fun all(): Map<String, Any> =
        read().asMap().mapKeys { it.key.name }.mapValues { it.value.snapshotPreferenceValue() }

    fun remove(key: String) {
        edit { preferences -> preferences.remove(stringPreferencesKey(key)) }
    }

    fun removeKeys(keys: Iterable<String>) {
        edit { preferences ->
            keys.forEach { key -> removeDynamicPreference(preferences, key) }
        }
    }

    fun removePrefix(prefixes: Iterable<String>) {
        val matched = keys().filter { key -> prefixes.any(key::startsWith) }
        removeKeys(matched)
    }

    fun snapshot(keys: Set<String>): PreferenceSnapshot {
        val currentValues = all()
        val values = keys.mapNotNull { key ->
            currentValues[key]?.let { value -> key to value.snapshotPreferenceValue() }
        }.toMap()
        return PreferenceSnapshot(keys = keys, values = values)
    }

    fun restore(snapshot: PreferenceSnapshot) {
        edit { preferences ->
            snapshot.keys.forEach { key ->
                when (val value = snapshot.values[key]) {
                    is String -> preferences[stringPreferencesKey(key)] = value
                    is Set<*> -> preferences[stringSetPreferencesKey(key)] = value.filterIsInstance<String>().toSet()
                    is Int -> preferences[intPreferencesKey(key)] = value
                    is Long -> preferences[longPreferencesKey(key)] = value
                    is Float -> preferences[floatPreferencesKey(key)] = value
                    is Boolean -> preferences[booleanPreferencesKey(key)] = value
                    null -> removeDynamicPreference(preferences, key)
                    else -> removeDynamicPreference(preferences, key)
                }
            }
        }
    }

    private fun read(): Preferences =
        runBlocking(Dispatchers.IO) { dataStore.data.first() }

    private fun edit(block: (MutablePreferences) -> Unit) {
        runBlocking(Dispatchers.IO) { dataStore.edit(block) }
    }

    private fun removeDynamicPreference(preferences: MutablePreferences, key: String) {
        preferences.remove(stringPreferencesKey(key))
        preferences.remove(booleanPreferencesKey(key))
        preferences.remove(longPreferencesKey(key))
        preferences.remove(intPreferencesKey(key))
        preferences.remove(floatPreferencesKey(key))
        preferences.remove(stringSetPreferencesKey(key))
    }
}

private object DataStorePreferenceRegistry {
    private val stores = mutableMapOf<String, DataStore<Preferences>>()

    @Synchronized
    fun store(context: Context, name: String): DataStore<Preferences> {
        val appContext = context.applicationContext
        val file = appContext.preferencesDataStoreFile(name)
        return stores.getOrPut(file.absolutePath) {
            PreferenceDataStoreFactory.create(
                migrations = listOf(SharedPreferencesMigration(appContext, name)),
                produceFile = { file },
            )
        }
    }
}
