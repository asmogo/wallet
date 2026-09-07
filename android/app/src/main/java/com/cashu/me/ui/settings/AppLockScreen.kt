package com.cashu.me.ui.settings

import androidx.compose.runtime.setValue
import androidx.compose.runtime.getValue
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import com.cashu.me.Core.AppLockManager
import com.cashu.me.Core.SettingsManager
import com.cashu.me.ui.components.InlineNotice
import com.cashu.me.ui.components.NoticeSeverity
import com.cashu.me.ui.components.ToggleRow
import com.cashu.me.ui.components.ToolbarIcon
import com.cashu.me.ui.security.findFragmentActivity
import com.cashu.me.ui.theme.CashuTheme
import kotlinx.coroutines.launch

/** iOS SettingsView.securityDetailView / SecuritySettingsSection. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AppLockScreen(
    settingsManager: SettingsManager,
    appLockManager: AppLockManager,
    onClose: () -> Unit,
) {
    val settings by settingsManager.state.collectAsState()
    val lockState by appLockManager.state.collectAsState()
    val context = LocalContext.current
    val activity = remember(context) { context.findFragmentActivity() }
    val scope = rememberCoroutineScope()
    var isEnablingAppLock by remember { mutableStateOf(false) }
    var showEnableFailure by remember { mutableStateOf(false) }
    var hasBiometrics by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        appLockManager.refreshAvailability()
        hasBiometrics = appLockManager.hasEnrolledBiometrics()
    }
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("App Lock", style = MaterialTheme.typography.titleMedium) },
                navigationIcon = {
                    IconButton(onClick = onClose) {
                        ToolbarIcon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = "Back")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background,
                ),
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState()),
        ) {
            ToggleRow(
                title = if (hasBiometrics) "Require biometric unlock" else "Require screen lock",
                subtitle = if (hasBiometrics) {
                    "Ask for biometric unlock when opening the wallet."
                } else {
                    "Ask for your screen lock when opening the wallet."
                },
                checked = settings.appLockEnabled,
                onCheckedChange = { enabled ->
                    showEnableFailure = false
                    if (!enabled) {
                        settingsManager.setAppLockEnabled(false)
                    } else {
                        scope.launch {
                            isEnablingAppLock = true
                            try {
                                val authenticated = enableAppLockAfterAuthentication(
                                    authenticate = { appLockManager.authenticateForAppLockEnablement(activity) },
                                    setEnabled = settingsManager::setAppLockEnabled,
                                )
                                if (!authenticated) showEnableFailure = true
                            } finally {
                                isEnablingAppLock = false
                            }
                        }
                    }
                },
                enabled = !isEnablingAppLock,
            )
            Column(
                modifier = Modifier.padding(
                    horizontal = CashuTheme.spacing.comfortable,
                    vertical = CashuTheme.spacing.tight,
                ),
                verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.snug),
            ) {
                if (showEnableFailure) {
                    InlineNotice(
                        text = "Authentication failed. App Lock was not enabled. Try turning it on again.",
                        severity = NoticeSeverity.Error,
                    )
                }
                if (!lockState.isAvailable) {
                    Text(
                        text = "Set a screen lock in Android settings to use App Lock.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Text(
                    text = "Your seed phrase always requires authentication to reveal, " +
                        "even when App Lock is off.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }

}

internal suspend fun enableAppLockAfterAuthentication(
    authenticate: suspend () -> Boolean,
    setEnabled: (Boolean) -> Unit,
): Boolean {
    val authenticated = authenticate()
    setEnabled(authenticated)
    return authenticated
}
