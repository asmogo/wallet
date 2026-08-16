package com.cashu.me.Views.Components

import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.TextButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter
import kotlinx.coroutines.delay
import org.cashudevkit.Token as CdkToken
import org.cashudevkit.TokenUrEncoder

enum class QRSpeed(val label: String, val intervalMillis: Long) {
    Fast("F", 100),
    Medium("M", 300),
    Slow("S", 500);

    fun next(): QRSpeed = when (this) {
        Fast -> Medium
        Medium -> Slow
        Slow -> Fast
    }
}

enum class QRSize(val label: String, val chunkSize: Int) {
    Small("S", 50),
    Medium("M", 100),
    Large("L", 200);

    fun next(): QRSize = when (this) {
        Small -> Medium
        Medium -> Large
        Large -> Small
    }
}

internal data class QRFrameSequence(
    val firstFrame: String,
    val totalParts: Int,
    val encoder: TokenUrEncoder?,
)

@Composable
fun QRCodeView(
    content: String,
    modifier: Modifier = Modifier,
    showControls: Boolean = true,
    staticOnly: Boolean = false,
) {
    var speed by remember { mutableStateOf(QRSpeed.Fast) }
    var size by remember { mutableStateOf(QRSize.Large) }
    val sequence = remember(content, staticOnly, size) {
        qrFrameSequence(content = content, staticOnly = staticOnly, chunkSize = size.chunkSize)
    }
    var frame by remember(sequence) { mutableStateOf(sequence.firstFrame) }

    LaunchedEffect(sequence, speed) {
        frame = sequence.firstFrame
        val encoder = sequence.encoder ?: return@LaunchedEffect
        while (true) {
            delay(speed.intervalMillis)
            frame = runCatching { encoder.nextPart() }.getOrDefault(frame)
        }
    }

    val bitmap = remember(frame) { runCatching { qrBitmap(frame) }.getOrNull() }
    Column(
        modifier = modifier,
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        if (bitmap == null) {
            Box(Modifier.fillMaxWidth().aspectRatio(1f), contentAlignment = Alignment.Center) {
                Text("QR unavailable", color = MaterialTheme.colorScheme.secondary)
            }
        } else {
            Image(
                bitmap = bitmap.asImageBitmap(),
                contentDescription = "QR code",
                modifier = Modifier.fillMaxWidth().aspectRatio(1f),
                // QR modules must stay on a hard black/white pixel grid.
                // Platform-dependent bitmap filtering introduces gray edge
                // pixels and can make both scanners and screenshot goldens
                // less reliable when the bitmap is scaled.
                filterQuality = FilterQuality.None,
            )
        }
        if (showControls && sequence.totalParts > 1) {
            QRControlsRow(
                speed = speed,
                size = size,
                onSpeedClick = { speed = speed.next() },
                onSizeClick = { size = size.next() },
            )
        }
    }
}

@Composable
private fun QRControlsRow(
    speed: QRSpeed,
    size: QRSize,
    onSpeedClick: () -> Unit,
    onSizeClick: () -> Unit,
) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(16.dp),
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.padding(top = 2.dp),
    ) {
        TextButton(onClick = onSpeedClick) {
            Text("SPEED: ${speed.label}", fontWeight = FontWeight.Medium)
        }
        TextButton(onClick = onSizeClick) {
            Text("SIZE: ${size.label}", fontWeight = FontWeight.Medium)
        }
    }
}

/**
 * NUT-16 animated frames come from CDK's own fountain encoder. Only Cashu
 * tokens animate: anything else (invoices, addresses, request strings) is a
 * standardized static payload, and non-token content simply doesn't fit the
 * NUT-16 envelope — those fall back to a single static frame.
 */
internal fun qrFrameSequence(
    content: String,
    staticOnly: Boolean,
    chunkSize: Int,
): QRFrameSequence {
    if (staticOnly || content.length <= chunkSize) {
        return QRFrameSequence(firstFrame = content, totalParts = 1, encoder = null)
    }
    return runCatching {
        val encoder = CdkToken.decode(content).urEncoder(maxFragmentLength = chunkSize.toUInt())
        if (encoder.isSingleFragment()) {
            return QRFrameSequence(firstFrame = content, totalParts = 1, encoder = null)
        }
        QRFrameSequence(
            firstFrame = encoder.nextPart(),
            totalParts = encoder.fragmentCount().toInt().coerceAtLeast(1),
            encoder = encoder,
        )
    }.getOrElse {
        QRFrameSequence(firstFrame = content, totalParts = 1, encoder = null)
    }
}

private fun qrBitmap(content: String, size: Int = 768): Bitmap {
    val matrix = QRCodeWriter().encode(
        content,
        BarcodeFormat.QR_CODE,
        size,
        size,
        mapOf(EncodeHintType.MARGIN to 1),
    )
    val pixels = IntArray(size * size)
    for (y in 0 until size) {
        for (x in 0 until size) {
            pixels[y * size + x] = if (matrix[x, y]) 0xff000000.toInt() else 0xffffffff.toInt()
        }
    }
    return Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888).apply {
        setPixels(pixels, 0, size, 0, 0, size, size)
    }
}
