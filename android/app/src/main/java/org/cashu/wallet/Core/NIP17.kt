package org.cashu.wallet.Core

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull

@Serializable
data class NostrIncomingEvent(
    val id: String,
    val pubkey: String,
    @SerialName("created_at")
    val createdAt: Long,
    val kind: Int,
    val tags: List<List<String>>,
    val content: String,
    val sig: String,
)

data class NostrRumor(
    val id: String,
    val pubkey: String,
    val createdAt: Long,
    val kind: Int,
    val tags: List<List<String>>,
    val content: String,
)

internal object NIP17 {
    private val json = Json { ignoreUnknownKeys = true }

    fun unwrap(giftWrap: NostrIncomingEvent, recipientPrivateKey: ByteArray): NostrRumor {
        val sealJson = NIP44.decrypt(
            payload = giftWrap.content,
            recipientPrivateKey = recipientPrivateKey,
            senderPubkeyHex = giftWrap.pubkey,
        )
        val seal = json.decodeFromString<NostrIncomingEvent>(sealJson)
        require(seal.kind == 13) { "Invalid NIP-17 seal." }
        val rumorJson = NIP44.decrypt(
            payload = seal.content,
            recipientPrivateKey = recipientPrivateKey,
            senderPubkeyHex = seal.pubkey,
        )
        return decodeRumor(rumorJson, expectedAuthor = seal.pubkey)
    }

    private fun decodeRumor(rawJson: String, expectedAuthor: String): NostrRumor {
        val fields = json.parseToJsonElement(rawJson).jsonObject
        val pubkey = fields["pubkey"]?.jsonPrimitive?.contentOrNull ?: expectedAuthor
        require(pubkey == expectedAuthor) { "Invalid NIP-17 rumor author." }
        val tags = fields["tags"]?.jsonArray?.map { tag ->
            tag.jsonArray.mapNotNull { value -> value.jsonPrimitive.contentOrNull }
        }.orEmpty()
        return NostrRumor(
            id = fields["id"]?.jsonPrimitive?.contentOrNull.orEmpty(),
            pubkey = pubkey,
            createdAt = fields["created_at"]?.jsonPrimitive?.longOrNull
                ?: fields["created_at"]?.jsonPrimitive?.intOrNull?.toLong()
                ?: 0,
            kind = fields["kind"]?.jsonPrimitive?.intOrNull ?: 0,
            tags = tags,
            content = fields["content"]?.jsonPrimitive?.contentOrNull.orEmpty(),
        )
    }
}
