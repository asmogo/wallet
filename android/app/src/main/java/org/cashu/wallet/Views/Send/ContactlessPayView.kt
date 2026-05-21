package org.cashu.wallet.Views.Send

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.nfc.NdefMessage
import android.nfc.NfcAdapter
import android.nfc.Tag
import android.nfc.tech.Ndef
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.cashu.wallet.Core.Services.NFCPaymentInput
import org.cashu.wallet.Core.Services.NFCPaymentService
import org.cashu.wallet.Core.Services.NFCReaderDelegate
import org.cashu.wallet.Core.WalletManager
import org.cashu.wallet.Views.Components.PrimaryActionButton
import org.cashu.wallet.Views.Components.SecondaryActionButton

@Composable
fun ContactlessPayView(
    walletManager: WalletManager,
    contentPadding: PaddingValues = PaddingValues(),
    onClose: () -> Unit,
    onLightningRequest: (String) -> Unit,
) {
    val context = LocalContext.current
    val activity = remember(context) { context.findActivity() }
    val adapter = remember(context) { NfcAdapter.getDefaultAdapter(context) }
    val scope = rememberCoroutineScope()
    val service = remember(walletManager) { NFCPaymentService(walletManager) }
    var status by remember { mutableStateOf("Hold the phone near an NFC payment tag.") }
    var error by remember { mutableStateOf<String?>(null) }
    var isProcessing by remember { mutableStateOf(false) }
    var paymentComplete by remember { mutableStateOf(false) }
    var lastPaymentAmount by remember { mutableStateOf<Long?>(null) }

    DisposableEffect(activity, adapter, service) {
        if (activity != null && adapter?.isEnabled == true) {
            val flags = (
                NfcAdapter.FLAG_READER_NFC_A or
                    NfcAdapter.FLAG_READER_NFC_B or
                    NfcAdapter.FLAG_READER_NFC_F or
                    NfcAdapter.FLAG_READER_NFC_V or
                    NfcAdapter.FLAG_READER_NFC_BARCODE
                )
            adapter.enableReaderMode(
                activity,
                { tag ->
                    scope.launch {
                        if (isProcessing) return@launch
                        isProcessing = true
                        paymentComplete = false
                        lastPaymentAmount = null
                        error = null
                        runCatching {
                            status = "Reading payment request..."
                            val payload = withContext(Dispatchers.IO) { readFirstNdefPayload(tag) }
                            when (val input = service.decodePaymentInput(payload)) {
                                is NFCPaymentInput.CashuRequest -> {
                                    status = "Preparing payment..."
                                    val amount = input.summary.amount
                                    val token = service.preparePayment(payload)
                                    status = "Writing payment..."
                                    withContext(Dispatchers.IO) {
                                        writeTextRecord(tag, service.tokenRecord(token))
                                    }
                                    lastPaymentAmount = amount
                                    paymentComplete = true
                                    status = "Payment sent."
                                }
                                is NFCPaymentInput.LightningRequest -> {
                                    status = "Lightning request found."
                                    onLightningRequest(input.request)
                                }
                            }
                        }.onFailure { failure ->
                            error = failure.message ?: "NFC payment failed."
                            status = "Ready to scan again."
                        }
                        isProcessing = false
                    }
                },
                flags,
                null,
            )
        }
        onDispose {
            if (activity != null && adapter != null) {
                runCatching { adapter.disableReaderMode(activity) }
            }
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(contentPadding)
            .padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text("Contactless", style = MaterialTheme.typography.headlineSmall)
        if (adapter == null) {
            Text("NFC is not available on this device.", color = MaterialTheme.colorScheme.error)
        } else if (!adapter.isEnabled) {
            Text("NFC is disabled in system settings.", color = MaterialTheme.colorScheme.error)
        } else {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (isProcessing) {
                    CircularProgressIndicator()
                }
                Text(status, color = MaterialTheme.colorScheme.secondary)
            }
        }
        if (paymentComplete) {
            Text("Payment sent!", color = MaterialTheme.colorScheme.primary)
            lastPaymentAmount?.let { Text("$it sat", style = MaterialTheme.typography.headlineSmall) }
        }
        error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            PrimaryActionButton("Close", onClick = onClose)
            SecondaryActionButton(if (paymentComplete) "Pay again" else "Reset", enabled = !isProcessing) {
                error = null
                paymentComplete = false
                lastPaymentAmount = null
                status = "Hold the phone near an NFC payment tag."
            }
        }
    }
}

private fun readFirstNdefPayload(tag: Tag): String {
    val ndef = Ndef.get(tag) ?: error("Tag does not support NDEF.")
    try {
        ndef.connect()
        val message = ndef.ndefMessage ?: ndef.cachedNdefMessage ?: error("No readable data on tag.")
        return NFCReaderDelegate.decodeMessage(message).firstOrNull()
            ?: error("No readable data on tag.")
    } finally {
        runCatching { ndef.close() }
    }
}

private fun writeTextRecord(tag: Tag, record: android.nfc.NdefRecord) {
    val ndef = Ndef.get(tag) ?: error("Tag does not support NDEF.")
    val message = NdefMessage(arrayOf(record))
    try {
        ndef.connect()
        require(ndef.isWritable) { "NFC tag is not writable." }
        require(ndef.maxSize >= message.toByteArray().size) { "NFC tag is too small for payment token." }
        ndef.writeNdefMessage(message)
    } finally {
        runCatching { ndef.close() }
    }
}

private tailrec fun Context.findActivity(): Activity? =
    when (this) {
        is Activity -> this
        is ContextWrapper -> baseContext.findActivity()
        else -> null
    }
