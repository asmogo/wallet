package org.cashu.wallet.Core.Services

import android.nfc.NdefMessage
import android.nfc.NdefRecord
import android.nfc.Tag
import android.nfc.tech.Ndef

object NFCReaderDelegate {
    fun readTextPayloads(tag: Tag): List<String> {
        val ndef = Ndef.get(tag) ?: return emptyList()
        return ndef.cachedNdefMessage?.records.orEmpty().mapNotNull(::decodeRecord)
    }

    fun decodeMessage(message: NdefMessage): List<String> =
        message.records.orEmpty().mapNotNull(::decodeRecord)

    private fun decodeRecord(record: NdefRecord): String? {
        return NDEFTextRecordCoder.decode(record)
    }
}
