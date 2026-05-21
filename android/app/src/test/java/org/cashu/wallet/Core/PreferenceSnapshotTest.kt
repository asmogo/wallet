package org.cashu.wallet.Core

import android.content.SharedPreferences
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class PreferenceSnapshotTest {
    @Test
    fun restoreReinstatesPresentValuesAndRemovesMissingSnapshotKeys() {
        val prefs = InMemorySharedPreferences(
            mutableMapOf(
                "wallet.mints" to "old-mints",
                "npc.enabled" to true,
                "settings.global" to "keep",
            ),
        )
        val snapshot = prefs.snapshot(setOf("wallet.mints", "npc.enabled", "wallet.pendingTokens"))

        prefs.edit()
            .putString("wallet.mints", "new-mints")
            .putString("wallet.pendingTokens", "new-pending")
            .remove("npc.enabled")
            .apply()

        prefs.restore(snapshot)

        assertEquals("old-mints", prefs.all["wallet.mints"])
        assertEquals(true, prefs.all["npc.enabled"])
        assertFalse(prefs.all.containsKey("wallet.pendingTokens"))
        assertEquals("keep", prefs.all["settings.global"])
    }
}

private class InMemorySharedPreferences(
    private val values: MutableMap<String, Any> = mutableMapOf(),
) : SharedPreferences {
    override fun getAll(): MutableMap<String, *> = values.toMutableMap()
    override fun getString(key: String?, defValue: String?): String? = values[key] as? String ?: defValue
    override fun getStringSet(key: String?, defValues: MutableSet<String>?): MutableSet<String>? {
        @Suppress("UNCHECKED_CAST")
        return (values[key] as? Set<String>)?.toMutableSet() ?: defValues
    }
    override fun getInt(key: String?, defValue: Int): Int = values[key] as? Int ?: defValue
    override fun getLong(key: String?, defValue: Long): Long = values[key] as? Long ?: defValue
    override fun getFloat(key: String?, defValue: Float): Float = values[key] as? Float ?: defValue
    override fun getBoolean(key: String?, defValue: Boolean): Boolean = values[key] as? Boolean ?: defValue
    override fun contains(key: String?): Boolean = values.containsKey(key)
    override fun edit(): SharedPreferences.Editor = Editor(values)
    override fun registerOnSharedPreferenceChangeListener(listener: SharedPreferences.OnSharedPreferenceChangeListener?) = Unit
    override fun unregisterOnSharedPreferenceChangeListener(listener: SharedPreferences.OnSharedPreferenceChangeListener?) = Unit

    private class Editor(private val values: MutableMap<String, Any>) : SharedPreferences.Editor {
        private val pending = mutableMapOf<String, Any?>()
        private var clear = false

        override fun putString(key: String?, value: String?): SharedPreferences.Editor = put(key, value)
        override fun putStringSet(key: String?, value: MutableSet<String>?): SharedPreferences.Editor =
            put(key, value?.toSet())
        override fun putInt(key: String?, value: Int): SharedPreferences.Editor = put(key, value)
        override fun putLong(key: String?, value: Long): SharedPreferences.Editor = put(key, value)
        override fun putFloat(key: String?, value: Float): SharedPreferences.Editor = put(key, value)
        override fun putBoolean(key: String?, value: Boolean): SharedPreferences.Editor = put(key, value)
        override fun remove(key: String?): SharedPreferences.Editor = put(key, null)
        override fun clear(): SharedPreferences.Editor = also { clear = true }
        override fun commit(): Boolean {
            apply()
            return true
        }
        override fun apply() {
            if (clear) values.clear()
            pending.forEach { (key, value) ->
                if (value == null) values.remove(key) else values[key] = value
            }
        }

        private fun put(key: String?, value: Any?): SharedPreferences.Editor {
            if (key != null) pending[key] = value
            return this
        }
    }
}
