package org.cashu.wallet.Views.Components

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay

@Composable
fun ActivityOrbView(
    isActive: Boolean,
    modifier: Modifier = Modifier,
    autoHideDelayMillis: Long = 2_000,
) {
    var isVisible by remember { mutableStateOf(false) }
    LaunchedEffect(isActive) {
        if (isActive) {
            isVisible = true
        } else {
            delay(autoHideDelayMillis)
            isVisible = false
        }
    }
    AnimatedVisibility(visible = isVisible, modifier = modifier) {
        CircularProgressIndicator(
            modifier = Modifier
                .size(22.dp)
                .semantics { contentDescription = "Activity in progress" },
            strokeWidth = 2.dp,
        )
    }
}

@Composable
fun LoadingSpinnerView(
    message: String? = null,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier.semantics {
            contentDescription = message ?: "Loading"
        },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        CircularProgressIndicator()
        message?.let { Text(it, style = MaterialTheme.typography.bodyMedium) }
    }
}

@Composable
fun MutexLockOverlay(
    isLocked: Boolean,
    modifier: Modifier = Modifier,
    message: String = "Processing...",
) {
    AnimatedVisibility(visible = isLocked, modifier = modifier.fillMaxSize()) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Color.Black.copy(alpha = 0.6f))
                .semantics { contentDescription = message },
            contentAlignment = Alignment.Center,
        ) {
            Card(
                shape = RoundedCornerShape(20.dp),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                elevation = CardDefaults.cardElevation(defaultElevation = 6.dp),
            ) {
                LoadingSpinnerView(
                    message = message,
                    modifier = Modifier.padding(40.dp),
                )
            }
        }
    }
}
