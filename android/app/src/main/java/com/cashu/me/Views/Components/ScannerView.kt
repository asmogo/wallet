package com.cashu.me.Views.Components

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearWavyProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.cashu.me.Core.AnimatedUrDecoder
import com.cashu.me.Core.WalletHaptic
import com.cashu.me.Core.rememberWalletHaptics
import com.cashu.me.ui.components.PrimaryButton
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.common.InputImage
import java.util.concurrent.Executors

internal enum class CameraPermissionState {
    Checking,
    Requesting,
    Granted,
    CanRequest,
    NeedsSettings,
}

internal fun cameraPermissionResultState(
    granted: Boolean,
    canShowRationale: Boolean,
): CameraPermissionState = when {
    granted -> CameraPermissionState.Granted
    canShowRationale -> CameraPermissionState.CanRequest
    else -> CameraPermissionState.NeedsSettings
}

data class ScannerQuickAction(
    val label: String,
    val icon: ImageVector,
    val onClick: () -> Unit,
)

@Composable
fun ScannerView(
    onClose: () -> Unit,
    onScanned: (String) -> Unit,
    useDeterministicPermission: Boolean = false,
    promptText: String = "Scan Cashu Token, Payment Request, or Bitcoin Address",
    quickActions: List<ScannerQuickAction> = emptyList(),
) {
    val context = LocalContext.current
    val activity = remember(context) { context.findActivity() }
    val lifecycleOwner = LocalLifecycleOwner.current
    val haptics = rememberWalletHaptics()
    var cameraPermissionState by remember {
        mutableStateOf(
            when {
                useDeterministicPermission -> CameraPermissionState.CanRequest
                context.hasCameraPermission() -> CameraPermissionState.Granted
                else -> CameraPermissionState.Checking
            },
        )
    }
    var cameraError by remember { mutableStateOf<String?>(null) }
    var completedScan by remember { mutableStateOf(false) }
    var animatedProgress by remember { mutableStateOf(0f) }
    var animatedError by remember { mutableStateOf<String?>(null) }
    val animatedUrDecoder = remember { AnimatedUrDecoder() }
    val permissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        cameraPermissionState = cameraPermissionResultState(
            granted = granted,
            canShowRationale = activity?.let {
                ActivityCompat.shouldShowRequestPermissionRationale(it, Manifest.permission.CAMERA)
            } ?: true,
        )
    }

    LaunchedEffect(Unit) {
        if (!useDeterministicPermission &&
            cameraPermissionState != CameraPermissionState.Granted
        ) {
            cameraPermissionState = CameraPermissionState.Requesting
            permissionLauncher.launch(Manifest.permission.CAMERA)
        }
    }

    DisposableEffect(lifecycleOwner, context) {
        val observer = LifecycleEventObserver { _, event ->
            if (!useDeterministicPermission && event == Lifecycle.Event.ON_RESUME) {
                if (context.hasCameraPermission()) {
                    cameraPermissionState = CameraPermissionState.Granted
                } else if (cameraPermissionState == CameraPermissionState.Granted) {
                    cameraPermissionState = CameraPermissionState.CanRequest
                }
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    fun requestCameraPermission() {
        if (useDeterministicPermission) {
            cameraPermissionState = CameraPermissionState.Granted
        } else {
            cameraPermissionState = CameraPermissionState.Requesting
            permissionLauncher.launch(Manifest.permission.CAMERA)
        }
    }

    when (cameraPermissionState) {
        CameraPermissionState.Granted -> Unit
        CameraPermissionState.Checking,
        CameraPermissionState.Requesting -> CameraPermissionView(
            title = "Camera Access",
            message = "Waiting for permission to use the camera.",
            showsProgress = true,
            onClose = onClose,
        )
        CameraPermissionState.CanRequest -> CameraPermissionView(
            title = "Camera Access Needed",
            message = "Allow camera access to scan QR codes.",
            actionText = "Allow Camera",
            onAction = { requestCameraPermission() },
            onClose = onClose,
        )
        CameraPermissionState.NeedsSettings -> CameraPermissionView(
            title = "Camera Access Needed",
            message = "Camera access is turned off. Enable it in Settings to scan QR codes.",
            actionText = "Open Settings",
            onAction = {
                context.startActivity(
                    Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                        data = Uri.fromParts("package", context.packageName, null)
                    },
                )
            },
            onClose = onClose,
        )
    }
    if (cameraPermissionState != CameraPermissionState.Granted) return

    if (useDeterministicPermission) {
        CameraPermissionView(
            title = "Camera Ready",
            message = "The scanner is ready to read a QR code.",
            onClose = onClose,
        )
        return
    }

    cameraError?.let { message ->
        CameraPermissionView(
            title = "Camera Unavailable",
            message = message,
            actionText = "Try Again",
            onAction = { cameraError = null },
            onClose = onClose,
        )
        return
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black),
    ) {
        CameraPreviewScanner(
            onCode = { code ->
                if (completedScan) return@CameraPreviewScanner
                val trimmed = code.trim()
                if (trimmed.startsWith("ur:", ignoreCase = true)) {
                    val update = animatedUrDecoder.receivePart(trimmed)
                    animatedProgress = update.progress
                    animatedError = update.errorMessage
                    update.content?.let { decoded ->
                        completedScan = true
                        haptics.perform(WalletHaptic.Success)
                        onScanned(decoded)
                    }
                } else {
                    completedScan = true
                    animatedUrDecoder.reset()
                    haptics.perform(WalletHaptic.Success)
                    onScanned(trimmed)
                }
            },
            onError = { error -> cameraError = error },
        )
        ScannerTopBar(
            onClose = onClose,
            modifier = Modifier
                .fillMaxWidth()
                .align(Alignment.TopCenter),
        )
        ScannerStatusOverlay(
            progress = animatedProgress,
            error = animatedError,
            promptText = promptText,
            quickActions = quickActions,
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .navigationBarsPadding()
                .padding(bottom = 50.dp, start = 24.dp, end = 24.dp),
        )
    }
}

@Composable
private fun ScannerStatusOverlay(
    progress: Float,
    error: String?,
    promptText: String,
    quickActions: List<ScannerQuickAction>,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier.widthIn(max = 360.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        if (progress > 0f && progress < 1f) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(
                        color = Color.Black.copy(alpha = 0.8f),
                        shape = RoundedCornerShape(16.dp),
                    )
                    .padding(16.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(
                    text = "Scanning Animated QR...",
                    color = Color.White,
                    style = MaterialTheme.typography.titleSmall,
                )
                LinearWavyProgressIndicator(
                    progress = { progress.coerceIn(0f, 1f) },
                    modifier = Modifier.fillMaxWidth(),
                )
                Text(
                    text = "${(progress * 100).toInt()}%",
                    color = Color.White.copy(alpha = 0.8f),
                    style = MaterialTheme.typography.bodySmall,
                )
            }
        } else {
            quickActions.forEach { action ->
                FilledTonalButton(
                    onClick = action.onClick,
                    modifier = Modifier.heightIn(min = 48.dp),
                    shape = RoundedCornerShape(percent = 50),
                    contentPadding = PaddingValues(horizontal = 18.dp, vertical = 11.dp),
                    colors = ButtonDefaults.filledTonalButtonColors(
                        containerColor = Color.White.copy(alpha = 0.18f),
                        contentColor = Color.White,
                    ),
                ) {
                    Icon(
                        imageVector = action.icon,
                        contentDescription = null,
                        modifier = Modifier.size(18.dp),
                    )
                    androidx.compose.foundation.layout.Spacer(Modifier.size(8.dp))
                    Text(action.label)
                }
            }
            Text(
                text = promptText,
                color = Color.White,
                style = MaterialTheme.typography.bodySmall,
                textAlign = TextAlign.Center,
                modifier = Modifier
                    .background(
                        color = Color.Black.copy(alpha = 0.6f),
                        shape = RoundedCornerShape(20.dp),
                    )
                    .padding(16.dp),
            )
        }
        error?.let {
            Text(
                text = it,
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodySmall,
            )
        }
    }
}

@Composable
private fun CameraPermissionView(
    title: String,
    message: String,
    actionText: String? = null,
    onAction: (() -> Unit)? = null,
    showsProgress: Boolean = false,
    onClose: () -> Unit,
) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black),
    ) {
        ScannerTopBar(
            onClose = onClose,
            modifier = Modifier
                .fillMaxWidth()
                .align(Alignment.TopCenter),
        )

        Column(
            modifier = Modifier
                .align(Alignment.Center)
                .widthIn(max = 440.dp)
                .fillMaxWidth()
                .padding(horizontal = 32.dp)
                .navigationBarsPadding(),
            verticalArrangement = Arrangement.spacedBy(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Icon(
                imageVector = Icons.Default.CameraAlt,
                contentDescription = null,
                modifier = Modifier.size(48.dp),
                tint = Color.White,
            )
            Text(
                text = title,
                color = Color.White,
                style = MaterialTheme.typography.headlineSmall,
                textAlign = TextAlign.Center,
            )
            Text(
                text = message,
                color = Color.White.copy(alpha = 0.75f),
                style = MaterialTheme.typography.bodyLarge,
                textAlign = TextAlign.Center,
            )
            if (showsProgress) {
                CircularProgressIndicator(
                    modifier = Modifier.size(28.dp),
                    color = Color.White,
                    strokeWidth = 2.dp,
                )
            }
            if (actionText != null && onAction != null) {
                PrimaryButton(
                    text = actionText,
                    onClick = onAction,
                    colors = ButtonDefaults.buttonColors(
                        containerColor = Color.White,
                        contentColor = Color.Black,
                        disabledContainerColor = Color.White.copy(alpha = 0.5f),
                        disabledContentColor = Color.Black.copy(alpha = 0.5f),
                    ),
                )
            }
        }
    }
}

@Composable
private fun ScannerTopBar(
    onClose: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Box(
        modifier = modifier
            .statusBarsPadding()
            .heightIn(min = 56.dp)
            .padding(horizontal = 4.dp),
    ) {
        IconButton(
            onClick = onClose,
            modifier = Modifier.align(Alignment.CenterStart),
        ) {
            Icon(
                imageVector = Icons.Default.Close,
                contentDescription = "Close",
                tint = Color.White,
            )
        }
        Text(
            text = "Scan QR Code",
            color = Color.White,
            style = MaterialTheme.typography.titleMedium,
            modifier = Modifier.align(Alignment.Center),
        )
    }
}

@Composable
private fun CameraPreviewScanner(
    onCode: (String) -> Unit,
    onError: (String) -> Unit,
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val cameraProviderFuture = remember { ProcessCameraProvider.getInstance(context) }
    val analysisExecutor = remember { Executors.newSingleThreadExecutor() }

    DisposableEffect(Unit) {
        onDispose {
            runCatching { cameraProviderFuture.get().unbindAll() }
            analysisExecutor.shutdown()
        }
    }

    AndroidView(
        modifier = Modifier.fillMaxSize(),
        factory = { viewContext ->
            val previewView = PreviewView(viewContext).apply {
                scaleType = PreviewView.ScaleType.FILL_CENTER
            }
            val mainExecutor = ContextCompat.getMainExecutor(viewContext)
            cameraProviderFuture.addListener(
                {
                    runCatching {
                        val cameraProvider = cameraProviderFuture.get()
                        val preview = Preview.Builder().build().also {
                            it.setSurfaceProvider(previewView.surfaceProvider)
                        }
                        val analyzer = ImageAnalysis.Builder()
                            .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                            .build()
                            .also {
                                it.setAnalyzer(analysisExecutor, BarcodeAnalyzer { code ->
                                    mainExecutor.execute { onCode(code) }
                                })
                            }
                        cameraProvider.unbindAll()
                        cameraProvider.bindToLifecycle(
                            lifecycleOwner,
                            CameraSelector.DEFAULT_BACK_CAMERA,
                            preview,
                            analyzer,
                        )
                    }.onFailure { error ->
                        onError(error.message ?: "Unable to start the camera.")
                    }
                },
                mainExecutor,
            )
            previewView
        },
    )
}

private class BarcodeAnalyzer(
    private val onCode: (String) -> Unit,
) : ImageAnalysis.Analyzer {
    private val scanner = BarcodeScanning.getClient()

    @ExperimentalGetImage
    override fun analyze(imageProxy: ImageProxy) {
        val mediaImage = imageProxy.image
        if (mediaImage == null) {
            imageProxy.close()
            return
        }
        val image = InputImage.fromMediaImage(mediaImage, imageProxy.imageInfo.rotationDegrees)
        scanner.process(image)
            .addOnSuccessListener { barcodes ->
                barcodes.firstNotNullOfOrNull { it.rawValue }?.let(onCode)
            }
            .addOnCompleteListener {
                imageProxy.close()
            }
    }
}

private fun Context.hasCameraPermission(): Boolean =
    ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED

private tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}
