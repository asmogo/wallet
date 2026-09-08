package com.cashu.me.App

import android.content.Intent
import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import androidx.fragment.app.FragmentActivity
import com.cashu.me.ui.shell.CashuApp

class MainActivity : FragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Replaces the default circular launcher-icon splash with a solid canvas
        // that matches the Compose LoadingScreen (light/dark via values-night).
        installSplashScreen()
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        // A consumed launch link must not navigate again when Android recreates
        // the activity (rotation, theme change, or process state restoration).
        // New links delivered to the running activity are handled below.
        if (savedInstanceState == null) handleIntent(intent)
        setContent {
            CashuApp(containerFlow = (application as CashuWalletApplication).container)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        if (intent?.action == Intent.ACTION_VIEW) {
            (application as CashuWalletApplication).handleDeepLink(intent.dataString)
        }
    }
}
