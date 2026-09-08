package com.cashu.me.Core.CDK

import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import okhttp3.Call
import okhttp3.Callback
import okhttp3.HttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import org.cashudevkit.PaymentType
import org.cashudevkit.decodeInvoice

internal class LightningAddressResolver(
    private val transport: LnurlHttpTransport = OkHttpLnurlHttpTransport(),
    private val invoiceDecoder: LightningInvoiceDecoder = CdkLightningInvoiceDecoder,
) {
    private val json = Json { ignoreUnknownKeys = true }

    suspend fun resolveBolt11Invoice(address: String, amountMsat: Long): String {
        require(amountMsat > 0) { "Lightning address payments require a positive amount." }

        val endpoint = lightningAddressEndpoint(address)
        val payRequestResponse = try {
            transport.get(endpoint)
        } catch (error: IOException) {
            throw LightningAddressResolutionException.Unavailable(
                "Lightning address service is unavailable.",
                error,
            )
        }
        if (payRequestResponse.code !in 200..299) {
            throw LightningAddressResolutionException.Unavailable(
                "Lightning address service returned HTTP ${payRequestResponse.code}.",
            )
        }

        val payRequest = try {
            json.decodeFromString<LnurlPayRequest>(payRequestResponse.body)
        } catch (error: Exception) {
            throw LightningAddressResolutionException.Unavailable(
                "Lightning address did not return an LNURL-pay request.",
                error,
            )
        }
        throwIfServiceError(payRequest.status, payRequest.reason)
        if (payRequest.tag != "payRequest") {
            throw LightningAddressResolutionException.Unavailable(
                "Lightning address did not return an LNURL-pay request.",
            )
        }

        val callback = payRequest.callback
            ?: throw LightningAddressResolutionException.Invalid(
                "Lightning address response is missing its payment callback.",
            )
        val minSendable = payRequest.minSendable
            ?: throw LightningAddressResolutionException.Invalid(
                "Lightning address response is missing its minimum amount.",
            )
        val maxSendable = payRequest.maxSendable
            ?: throw LightningAddressResolutionException.Invalid(
                "Lightning address response is missing its maximum amount.",
            )
        if (amountMsat < minSendable || amountMsat > maxSendable) {
            throw LightningAddressResolutionException.Invalid(
                "Requested amount is outside the range accepted by the Lightning address.",
            )
        }

        val callbackUrl = invoiceCallbackUrl(
            callback = callback,
            amountMsat = amountMsat,
        )
        val invoiceResponse = try {
            transport.get(callbackUrl)
        } catch (error: IOException) {
            throw LightningAddressResolutionException.Invalid(
                "Failed to request an invoice from the Lightning address service.",
                error,
            )
        }
        if (invoiceResponse.code !in 200..299) {
            throw LightningAddressResolutionException.Invalid(
                "Lightning address invoice callback returned HTTP ${invoiceResponse.code}.",
            )
        }

        val callbackResponse = try {
            json.decodeFromString<LnurlPayCallbackResponse>(invoiceResponse.body)
        } catch (error: Exception) {
            throw LightningAddressResolutionException.Invalid(
                "Lightning address service returned an invalid invoice response.",
                error,
            )
        }
        throwIfServiceError(callbackResponse.status, callbackResponse.reason)

        val invoice = callbackResponse.pr?.trim().takeUnless { it.isNullOrEmpty() }
            ?: throw LightningAddressResolutionException.Invalid(
                "Lightning address service did not return an invoice.",
            )
        val decoded = try {
            invoiceDecoder.decode(invoice)
        } catch (error: Exception) {
            throw LightningAddressResolutionException.Invalid(
                "Lightning address service returned an invalid invoice.",
                error,
            )
        }
        if (!decoded.isBolt11 || decoded.amountMsat != amountMsat.toULong()) {
            throw LightningAddressResolutionException.Invalid(
                "Lightning address invoice amount does not match the requested amount.",
            )
        }

        return invoice
    }

    private fun lightningAddressEndpoint(address: String): HttpUrl {
        val trimmed = address.trim()
        val separator = trimmed.indexOf('@')
        if (separator <= 0 || separator != trimmed.lastIndexOf('@') || separator == trimmed.lastIndex) {
            throw LightningAddressResolutionException.Invalid("That Lightning address does not look valid.")
        }

        val user = trimmed.substring(0, separator)
        val domain = trimmed.substring(separator + 1).lowercase()
        if (
            user == "." ||
            user == ".." ||
            !Lud16User.matches(user) ||
            !isValidPublicDomain(domain)
        ) {
            throw LightningAddressResolutionException.Invalid("That Lightning address does not look valid.")
        }

        return HttpUrl.Builder()
            .scheme("https")
            .host(domain)
            .addPathSegment(".well-known")
            .addPathSegment("lnurlp")
            .addPathSegment(user)
            .build()
    }

    private fun invoiceCallbackUrl(
        callback: String,
        amountMsat: Long,
    ): HttpUrl {
        val parsed = callback.toHttpUrlOrNull()
            ?: throw LightningAddressResolutionException.Invalid(
                "Lightning address service returned an invalid payment callback.",
            )
        val authority = runCatching { java.net.URI(callback).rawAuthority }.getOrNull()
        if (
            authority == null || authority.contains('@') ||
            parsed.scheme != "https" ||
            parsed.username.isNotEmpty() ||
            parsed.password.isNotEmpty() ||
            parsed.fragment != null
        ) {
            throw LightningAddressResolutionException.Invalid(
                "Lightning address service returned an unsafe payment callback.",
            )
        }

        val builder = parsed.newBuilder().query(null)
        repeat(parsed.querySize) { index ->
            val name = parsed.queryParameterName(index)
            if (!name.equals("amount", ignoreCase = true)) {
                builder.addQueryParameter(name, parsed.queryParameterValue(index))
            }
        }
        return builder
            .addQueryParameter("amount", amountMsat.toString())
            .build()
    }

    private fun throwIfServiceError(status: String?, reason: String?) {
        if (status.equals("ERROR", ignoreCase = true)) {
            throw LightningAddressResolutionException.Invalid(
                reason ?: "Lightning address service returned an error.",
            )
        }
    }

    private fun isValidPublicDomain(domain: String): Boolean {
        if (domain.length > 253) return false
        val labels = domain.split('.')
        return labels.size >= 2 && labels.all { label ->
            label.length in 1..63 &&
                label.first() != '-' &&
                label.last() != '-' &&
                label.all { it.isLowerCase() || it.isDigit() || it == '-' }
        }
    }

    private companion object {
        val Lud16User = Regex("[a-z0-9._+-]+")
    }
}

internal sealed class LightningAddressResolutionException(
    message: String,
    cause: Throwable? = null,
) : IllegalArgumentException(message, cause) {
    class Unavailable(message: String, cause: Throwable? = null) :
        LightningAddressResolutionException(message, cause)

    class Invalid(message: String, cause: Throwable? = null) :
        LightningAddressResolutionException(message, cause)
}

internal fun interface LnurlHttpTransport {
    suspend fun get(url: HttpUrl): LnurlHttpResponse
}

internal data class LnurlHttpResponse(
    val code: Int,
    val body: String,
)

internal fun interface LightningInvoiceDecoder {
    fun decode(invoice: String): LightningInvoiceMetadata
}

internal data class LightningInvoiceMetadata(
    val isBolt11: Boolean,
    val amountMsat: ULong?,
)

private object CdkLightningInvoiceDecoder : LightningInvoiceDecoder {
    override fun decode(invoice: String): LightningInvoiceMetadata {
        val decoded = decodeInvoice(invoice)
        return LightningInvoiceMetadata(
            isBolt11 = decoded.paymentType == PaymentType.BOLT11,
            amountMsat = decoded.amountMsat,
        )
    }
}

private class OkHttpLnurlHttpTransport(
    private val client: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(20, TimeUnit.SECONDS)
        .readTimeout(20, TimeUnit.SECONDS)
        .followRedirects(false)
        .followSslRedirects(false)
        .build(),
) : LnurlHttpTransport {
    override suspend fun get(url: HttpUrl): LnurlHttpResponse {
        val request = Request.Builder()
            .url(url)
            .header("Accept", "application/json")
            .get()
            .build()
        return client.newCall(request).awaitResponse()
    }

    private suspend fun Call.awaitResponse(): LnurlHttpResponse =
        suspendCancellableCoroutine { continuation ->
            continuation.invokeOnCancellation { cancel() }
            enqueue(object : Callback {
                override fun onFailure(call: Call, e: IOException) {
                    if (continuation.isActive) continuation.resumeWithException(e)
                }

                override fun onResponse(call: Call, response: Response) {
                    try {
                        val result = response.use {
                            LnurlHttpResponse(
                                code = it.code,
                                body = it.body?.string().orEmpty(),
                            )
                        }
                        if (continuation.isActive) continuation.resume(result)
                    } catch (error: Exception) {
                        if (continuation.isActive) continuation.resumeWithException(error)
                    }
                }
            })
        }
}

@Serializable
private data class LnurlPayRequest(
    val callback: String? = null,
    val maxSendable: Long? = null,
    val minSendable: Long? = null,
    val tag: String? = null,
    val status: String? = null,
    val reason: String? = null,
)

@Serializable
private data class LnurlPayCallbackResponse(
    val pr: String? = null,
    val status: String? = null,
    val reason: String? = null,
)
