package com.cashu.me.Views.Send

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.nfc.NdefMessage
import android.nfc.NfcAdapter
import android.nfc.Tag
import android.nfc.tech.Ndef
import android.provider.Settings
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Nfc
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.Icon
import androidx.compose.material3.LoadingIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SheetValue
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.rememberBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import com.cashu.me.Core.Services.NFCPaymentInput
import com.cashu.me.Core.Services.NFCPaymentService
import com.cashu.me.Core.Services.NFCReaderDelegate
import com.cashu.me.Core.WalletManager
import com.cashu.me.ui.components.InlineNotice
import com.cashu.me.ui.components.InlineNoticeHost
import com.cashu.me.ui.components.PrimaryButton

/**
 * Android has no system-owned NFC reader sheet, so reader mode is presented in
 * a native Material 3 modal bottom sheet. The host owns dismissal animation and
 * prevents accidental swipe/back dismissal while a tag is being read or written.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ContactlessPaySheet(
    walletManager: WalletManager,
    onDismissed: () -> Unit,
    onLightningRequest: (String) -> Unit,
) {
    val dismissLocked = remember { mutableStateOf(false) }
    val confirmValueChange = remember {
        { value: SheetValue -> value != SheetValue.Hidden || !dismissLocked.value }
    }
    val sheetState = rememberBottomSheetState(
        initialValue = SheetValue.Hidden,
        enabledValues = setOf(SheetValue.Hidden, SheetValue.Expanded),
        confirmValueChange = confirmValueChange,
    )
    val scope = rememberCoroutineScope()
    var closing by remember { mutableStateOf(false) }

    fun hideThen(action: () -> Unit) {
        if (closing) return
        closing = true
        // Deliberate navigation is allowed to end the session even if the tag
        // callback has not yet delivered its final idle-state recomposition.
        dismissLocked.value = false
        scope.launch { sheetState.hide() }.invokeOnCompletion { action() }
    }

    ModalBottomSheet(
        onDismissRequest = {
            if (!dismissLocked.value && !closing) {
                closing = true
                onDismissed()
            }
        },
        sheetState = sheetState,
    ) {
        ContactlessPayView(
            walletManager = walletManager,
            onLightningRequest = { invoice ->
                hideThen { onLightningRequest(invoice) }
            },
            onDismissLockChanged = { dismissLocked.value = it },
        )
    }
}

@Composable
fun ContactlessPayView(
    walletManager: WalletManager,
    modifier: Modifier = Modifier,
    onLightningRequest: (String) -> Unit,
    onDismissLockChanged: (Boolean) -> Unit = {},
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val activity = remember(context) { context.findActivity() }
    val adapter = remember(context) { NfcAdapter.getDefaultAdapter(context) }
    val scope = rememberCoroutineScope()
    val service = remember(walletManager) { NFCPaymentService(walletManager) }
    val currentDismissLockChanged by rememberUpdatedState(onDismissLockChanged)
    var nfcEnabled by remember(adapter) { mutableStateOf(adapter?.isEnabled == true) }
    var status by remember { mutableStateOf("Hold the phone near an NFC payment tag.") }
    var error by remember { mutableStateOf<String?>(null) }
    var isProcessing by remember { mutableStateOf(false) }
    var paymentComplete by remember { mutableStateOf(false) }
    var lastPaymentAmount by remember { mutableStateOf<Long?>(null) }

    DisposableEffect(lifecycleOwner, adapter) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                nfcEnabled = adapter?.isEnabled == true
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    DisposableEffect(activity, adapter, service, nfcEnabled) {
        if (activity != null && adapter != null && nfcEnabled) {
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
                        currentDismissLockChanged(true)
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
                        currentDismissLockChanged(false)
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
            currentDismissLockChanged(false)
        }
    }

    ContactlessPayContent(
        availability = when {
            adapter == null -> ContactlessAvailability.Unavailable
            !nfcEnabled -> ContactlessAvailability.Disabled
            else -> ContactlessAvailability.Ready
        },
        status = status,
        error = error,
        isProcessing = isProcessing,
        paymentComplete = paymentComplete,
        lastPaymentAmount = lastPaymentAmount,
        modifier = modifier,
        onOpenNfcSettings = { context.openNfcSettings() },
    )
}

internal enum class ContactlessAvailability { Unavailable, Disabled, Ready }

@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
internal fun ContactlessPayContent(
    availability: ContactlessAvailability,
    status: String,
    error: String?,
    isProcessing: Boolean,
    paymentComplete: Boolean,
    lastPaymentAmount: Long?,
    onOpenNfcSettings: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .testTag("contactlessSheetContent")
            .padding(horizontal = 24.dp)
            .padding(bottom = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text(
            text = "Contactless",
            style = MaterialTheme.typography.headlineSmall,
            textAlign = TextAlign.Center,
        )
        Surface(
            modifier = Modifier.size(80.dp),
            shape = CircleShape,
            color = MaterialTheme.colorScheme.surfaceContainerHigh,
        ) {
            Box(contentAlignment = Alignment.Center) {
                Icon(
                    imageVector = Icons.Outlined.Nfc,
                    contentDescription = null,
                    modifier = Modifier.size(40.dp),
                    tint = MaterialTheme.colorScheme.onSurface,
                )
            }
        }

        when (availability) {
            ContactlessAvailability.Unavailable ->
                InlineNotice(text = "NFC is not available on this device.")
            ContactlessAvailability.Disabled ->
                InlineNotice(text = "NFC is disabled in system settings.")
            ContactlessAvailability.Ready ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.Center,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    // The working indicator and the status line fade/swap
                    // instead of popping per read-stage.
                    AnimatedVisibility(
                        visible = isProcessing,
                        enter = fadeIn(tween(200)),
                        exit = fadeOut(tween(150)),
                    ) {
                        LoadingIndicator(modifier = Modifier.size(24.dp))
                    }
                    AnimatedContent(
                        targetState = status,
                        transitionSpec = { fadeIn(tween(200)) togetherWith fadeOut(tween(150)) },
                        label = "contactless-status",
                    ) { currentStatus ->
                        Text(
                            text = currentStatus,
                            modifier = Modifier.padding(start = if (isProcessing) 8.dp else 0.dp),
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            textAlign = TextAlign.Center,
                        )
                    }
                }
        }

        // The success beat arrives with the same fade + scale-in the shared
        // terminal glyph uses — a payment landing never pops in.
        AnimatedVisibility(
            visible = paymentComplete,
            enter = fadeIn(tween(200)) + scaleIn(
                animationSpec = spring(
                    dampingRatio = 0.7f,
                    stiffness = Spring.StiffnessMediumLow,
                ),
                initialScale = 0.9f,
            ),
            exit = fadeOut(tween(150)),
        ) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                Text("Payment sent!", style = MaterialTheme.typography.titleMedium)
                lastPaymentAmount?.let {
                    Text("$it sat", style = MaterialTheme.typography.headlineSmall)
                }
            }
        }
        InlineNoticeHost(text = error)

        when (availability) {
            ContactlessAvailability.Disabled ->
                PrimaryButton("Open NFC settings", onClick = onOpenNfcSettings)
            ContactlessAvailability.Unavailable,
            ContactlessAvailability.Ready -> Unit
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

private fun Context.openNfcSettings() {
    runCatching { startActivity(Intent(Settings.ACTION_NFC_SETTINGS)) }
        .recoverCatching { startActivity(Intent(Settings.ACTION_WIRELESS_SETTINGS)) }
}
