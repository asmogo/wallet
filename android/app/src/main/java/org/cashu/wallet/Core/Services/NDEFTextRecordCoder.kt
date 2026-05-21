package org.cashu.wallet.Core.Services

import android.nfc.NdefRecord
import java.nio.charset.Charset
import java.util.Locale

object NDEFTextRecordCoder {
    private val textRecordType = byteArrayOf('T'.code.toByte())
    private val uriRecordType = byteArrayOf('U'.code.toByte())

    fun encode(text: String, locale: Locale = Locale.US): NdefRecord {
        val payload = encodeTextPayload(text, locale)
        return NdefRecord(NdefRecord.TNF_WELL_KNOWN, NdefRecord.RTD_TEXT, ByteArray(0), payload)
    }

    fun encodeTextPayload(text: String, locale: Locale = Locale.US): ByteArray {
        val language = locale.language.toByteArray(Charsets.US_ASCII)
        val payload = ByteArray(1 + language.size + text.toByteArray(Charsets.UTF_8).size)
        payload[0] = language.size.toByte()
        System.arraycopy(language, 0, payload, 1, language.size)
        val textBytes = text.toByteArray(Charsets.UTF_8)
        System.arraycopy(textBytes, 0, payload, 1 + language.size, textBytes.size)
        return payload
    }

    fun decode(record: NdefRecord): String? {
        return decodeRecordPayload(record.tnf, record.type, record.payload)
    }

    fun decodeRecordPayload(tnf: Short, type: ByteArray, payload: ByteArray): String? =
        when {
            tnf == NdefRecord.TNF_WELL_KNOWN && type.contentEquals(textRecordType) -> decodeTextPayload(payload)
            tnf == NdefRecord.TNF_WELL_KNOWN && type.contentEquals(uriRecordType) -> decodeUriPayload(payload)
            tnf == NdefRecord.TNF_EXTERNAL_TYPE || tnf == NdefRecord.TNF_MIME_MEDIA -> decodePayloadText(payload)
            else -> decodePayloadText(payload)?.takeIf { it.isNotEmpty() }
        }

    fun decodeTextPayload(payload: ByteArray): String? {
        if (payload.isEmpty()) return null
        val status = payload[0].toInt()
        val isUtf16 = (status and 0x80) != 0
        val languageLength = status and 0x3f
        if (payload.size <= languageLength + 1) return null
        val charset = if (isUtf16) Charsets.UTF_16 else Charsets.UTF_8
        return String(payload, 1 + languageLength, payload.size - 1 - languageLength, charset)
    }

    fun decodeUriPayload(payload: ByteArray): String? {
        if (payload.isEmpty()) return null
        val prefix = uriPrefix(payload[0].toInt() and 0xff)
        val suffix = runCatching {
            String(payload, 1, payload.size - 1, Charsets.UTF_8)
        }.getOrNull() ?: return null
        return prefix + suffix
    }

    fun decodePayloadText(payload: ByteArray): String? =
        runCatching { String(payload, Charset.forName("UTF-8")).trim('\u0000') }.getOrNull()

    private fun uriPrefix(code: Int): String = when (code) {
        0x01 -> "http://www."
        0x02 -> "https://www."
        0x03 -> "http://"
        0x04 -> "https://"
        0x05 -> "tel:"
        0x06 -> "mailto:"
        0x07 -> "ftp://anonymous:anonymous@"
        0x08 -> "ftp://ftp."
        0x09 -> "ftps://"
        0x0a -> "sftp://"
        0x0b -> "smb://"
        0x0c -> "nfs://"
        0x0d -> "ftp://"
        0x0e -> "dav://"
        0x0f -> "news:"
        0x10 -> "telnet://"
        0x11 -> "imap:"
        0x12 -> "rtsp://"
        0x13 -> "urn:"
        0x14 -> "pop:"
        0x15 -> "sip:"
        0x16 -> "sips:"
        0x17 -> "tftp:"
        0x18 -> "btspp://"
        0x19 -> "btl2cap://"
        0x1a -> "btgoep://"
        0x1b -> "tcpobex://"
        0x1c -> "irdaobex://"
        0x1d -> "file://"
        0x1e -> "urn:epc:id:"
        0x1f -> "urn:epc:tag:"
        0x20 -> "urn:epc:pat:"
        0x21 -> "urn:epc:raw:"
        0x22 -> "urn:epc:"
        0x23 -> "urn:nfc:"
        else -> ""
    }
}
