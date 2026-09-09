package com.cashu.me.Core.CDK

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/** CDK 0.18 returns JSON-serialized incomplete sagas. Read only account identity. */
internal fun receiveRecoveryCandidate(saga: String): ReceiveRecoveryCandidate? = runCatching {
    val payload = Json.parseToJsonElement(saga).jsonObject
    if (payload["kind"]?.jsonPrimitive?.content != "receive") return@runCatching null
    val mint = payload["mint_url"]?.jsonPrimitive?.content ?: return@runCatching null
    val unit = payload["unit"]?.jsonPrimitive?.content ?: return@runCatching null
    ReceiveRecoveryCandidate(mint, unit.lowercase())
}.getOrNull()
