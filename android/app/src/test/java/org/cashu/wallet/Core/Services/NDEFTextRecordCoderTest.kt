package org.cashu.wallet.Core.Services

import android.nfc.NdefRecord
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class NDEFTextRecordCoderTest {
    @Test
    fun encodesAndDecodesWellKnownTextPayload() {
        val payload = NDEFTextRecordCoder.encodeTextPayload("cashu-token", Locale.US)

        assertEquals(
            "cashu-token",
            NDEFTextRecordCoder.decodeRecordPayload(
                tnf = NdefRecord.TNF_WELL_KNOWN,
                type = byteArrayOf('T'.code.toByte()),
                payload = payload,
            ),
        )
    }

    @Test
    fun rejectsTextPayloadWithoutContentAfterLanguageCode() {
        assertNull(NDEFTextRecordCoder.decodeTextPayload(byteArrayOf(2, 'e'.code.toByte(), 'n'.code.toByte())))
    }

    @Test
    fun decodesWellKnownUriPayloadWithNfcPrefix() {
        val payload = byteArrayOf(0x04) + "example.com/pay".toByteArray(Charsets.UTF_8)

        assertEquals(
            "https://example.com/pay",
            NDEFTextRecordCoder.decodeRecordPayload(
                tnf = NdefRecord.TNF_WELL_KNOWN,
                type = byteArrayOf('U'.code.toByte()),
                payload = payload,
            ),
        )
    }

    @Test
    fun decodesExternalAndMediaPayloadsAsUtf8Text() {
        val externalPayload = "cashu:creqa-test".toByteArray(Charsets.UTF_8)
        val mediaPayload = "lightning:lnbc10u1ptest".toByteArray(Charsets.UTF_8)

        assertEquals(
            "cashu:creqa-test",
            NDEFTextRecordCoder.decodeRecordPayload(
                tnf = NdefRecord.TNF_EXTERNAL_TYPE,
                type = "cashu:request".toByteArray(Charsets.UTF_8),
                payload = externalPayload,
            ),
        )
        assertEquals(
            "lightning:lnbc10u1ptest",
            NDEFTextRecordCoder.decodeRecordPayload(
                tnf = NdefRecord.TNF_MIME_MEDIA,
                type = "text/plain".toByteArray(Charsets.UTF_8),
                payload = mediaPayload,
            ),
        )
    }

    @Test
    fun decodesRawUtf8FallbackPayload() {
        assertEquals(
            "lnbc10u1ptest",
            NDEFTextRecordCoder.decodeRecordPayload(
                tnf = NdefRecord.TNF_UNKNOWN,
                type = ByteArray(0),
                payload = "lnbc10u1ptest".toByteArray(Charsets.UTF_8),
            ),
        )
    }
}
