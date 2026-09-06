package com.cashu.me.Core

import android.content.SharedPreferences
import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder

@Serializable(with = PreferenceSnapshotSerializer::class)
internal data class PreferenceSnapshot(
    val keys: Set<String>,
    val values: Map<String, Any>,
)

/** Explicit type tags preserve Android preference types across process restarts. */
internal object PreferenceSnapshotSerializer : KSerializer<PreferenceSnapshot> {
    @Serializable
    private data class Value(val type: String, val text: String = "", val strings: Set<String> = emptySet())
    @Serializable
    private data class Stored(val keys: Set<String>, val values: Map<String, Value>)
    override val descriptor = Stored.serializer().descriptor
    override fun serialize(encoder: Encoder, value: PreferenceSnapshot) {
        val values = value.values.mapValues { (_, item) ->
            when (item) {
                is String -> Value("string", item)
                is Boolean -> Value("boolean", item.toString())
                is Int -> Value("int", item.toString())
                is Long -> Value("long", item.toString())
                is Float -> Value("float", item.toString())
                is Set<*> -> Value("set", strings = item.filterIsInstance<String>().toSet())
                else -> error("Unsupported wallet preference type.")
            }
        }
        encoder.encodeSerializableValue(Stored.serializer(), Stored(value.keys, values))
    }
    override fun deserialize(decoder: Decoder): PreferenceSnapshot {
        val stored = decoder.decodeSerializableValue(Stored.serializer())
        return PreferenceSnapshot(stored.keys, stored.values.mapValues { (_, item) ->
            when (item.type) {
                "string" -> item.text
                "boolean" -> item.text.toBooleanStrict()
                "int" -> item.text.toInt()
                "long" -> item.text.toLong()
                "float" -> item.text.toFloat()
                "set" -> item.strings
                else -> error("Unknown wallet preference type.")
            }
        })
    }
}

internal fun SharedPreferences.snapshot(keys: Set<String>): PreferenceSnapshot {
    val currentValues = all
    val values = keys.mapNotNull { key ->
        currentValues[key]?.let { value -> key to value.snapshotPreferenceValue() }
    }.toMap()
    return PreferenceSnapshot(keys = keys, values = values)
}

internal fun SharedPreferences.restore(snapshot: PreferenceSnapshot, synchronous: Boolean = false) {
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
    if (synchronous) check(editor.commit()) { "Wallet preferences could not be restored." }
    else editor.apply()
}

internal fun Any.snapshotPreferenceValue(): Any = when (this) {
    is Set<*> -> filterIsInstance<String>().toSet()
    else -> this
}
