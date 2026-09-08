package com.cashu.me.ui.security

import android.app.Dialog
import android.os.Build
import android.view.KeyEvent
import android.window.OnBackInvokedCallback
import android.window.OnBackInvokedDispatcher
import android.view.Window
import android.view.WindowManager
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCompositionContext
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.ViewCompositionStrategy
import androidx.core.view.WindowCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.setViewTreeLifecycleOwner
import androidx.savedstate.compose.LocalSavedStateRegistryOwner
import androidx.savedstate.setViewTreeSavedStateRegistryOwner
import com.cashu.me.R

/**
 * A full-screen native modal window. The Activity and its drafts stay mounted;
 * a later app sheet yields focus back to this gate, while system authentication
 * remains free to take focus.
 */
@Composable
internal fun AppLockDialog(isAuthenticating: Boolean = false, content: @Composable () -> Unit) {
    val context = LocalContext.current
    val source = LocalView.current
    val parentComposition = rememberCompositionContext()
    val lifecycleOwner = LocalLifecycleOwner.current
    val savedStateOwner = LocalSavedStateRegistryOwner.current
    val currentContent by rememberUpdatedState(content)
    val authenticating by rememberUpdatedState(isAuthenticating)
    val onFocusChanged = remember { mutableListOf<(Boolean) -> Unit>() }
    val dialog = remember(context, source) {
        // The gate must be opaque from its first frame, including after a re-show.
        object : Dialog(context, R.style.Theme_CashuWallet_AppLock) {
            @Suppress("OVERRIDE_DEPRECATION")
            override fun onWindowFocusChanged(hasFocus: Boolean) {
                super.onWindowFocusChanged(hasFocus)
                onFocusChanged.forEach { it(hasFocus) }
            }
        }.apply {
            requestWindowFeature(Window.FEATURE_NO_TITLE)
            setCancelable(false)
            setCanceledOnTouchOutside(false)
            setOnKeyListener { _, keyCode, _ -> keyCode == KeyEvent.KEYCODE_BACK }
            window?.apply {
                addFlags(WindowManager.LayoutParams.FLAG_SECURE or WindowManager.LayoutParams.FLAG_ALT_FOCUSABLE_IM)
                clearFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND)
                // The non-floating theme fills the window; also extend the cover
                // behind system bars and display cutouts on every supported API.
                WindowCompat.enableEdgeToEdge(this)
            }
        }
    }
    val useDarkSystemBarIcons = MaterialTheme.colorScheme.background.luminance() > 0.5f
    SideEffect {
        dialog.window?.let { window ->
            WindowCompat.getInsetsController(window, window.decorView).apply {
                isAppearanceLightStatusBars = useDarkSystemBarIcons
                isAppearanceLightNavigationBars = useDarkSystemBarIcons
            }
        }
    }
    DisposableEffect(dialog, lifecycleOwner, savedStateOwner) {
        val compose = ComposeView(context).apply {
            setParentCompositionContext(parentComposition)
            setViewCompositionStrategy(ViewCompositionStrategy.DisposeOnLifecycleDestroyed(lifecycleOwner))
            setViewTreeLifecycleOwner(lifecycleOwner)
            setViewTreeSavedStateRegistryOwner(savedStateOwner)
            setContent { currentContent() }
        }
        dialog.setContentView(compose)
        val blockedBack = if (Build.VERSION.SDK_INT >= 33) OnBackInvokedCallback {} else null
        fun showGate() {
            dialog.show()
            dialog.window?.setLayout(WindowManager.LayoutParams.MATCH_PARENT, WindowManager.LayoutParams.MATCH_PARENT)
            if (Build.VERSION.SDK_INT >= 33 && blockedBack != null) {
                dialog.onBackInvokedDispatcher.registerOnBackInvokedCallback(OnBackInvokedDispatcher.PRIORITY_OVERLAY, blockedBack)
            }
        }
        var active = true
        val focusListener: (Boolean) -> Unit = { hasFocus ->
            if (!hasFocus) source.post {
                if (active && dialog.isShowing && dialog.window?.decorView?.hasWindowFocus() == false && !authenticating &&
                    lifecycleOwner.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) {
                    // Re-add this app window above a later sheet. Retain its
                    // composition so the one-shot authentication effect stays put.
                    // System authentication is allowed to own focus instead.
                    dialog.dismiss()
                    showGate()
                }
            }
        }
        onFocusChanged.add(focusListener)
        val resumeObserver = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) focusListener(false)
        }
        lifecycleOwner.lifecycle.addObserver(resumeObserver)
        showGate()
        onDispose {
            active = false
            onFocusChanged.remove(focusListener)
            lifecycleOwner.lifecycle.removeObserver(resumeObserver)
            if (Build.VERSION.SDK_INT >= 33 && blockedBack != null) {
                dialog.onBackInvokedDispatcher.unregisterOnBackInvokedCallback(blockedBack)
            }
            dialog.dismiss()
            compose.disposeComposition()
        }
    }
    LaunchedEffect(isAuthenticating) {
        if (!isAuthenticating) onFocusChanged.forEach { it(false) }
    }
}
