package com.cashu.me.App

import android.app.Application
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

open class CashuWalletApplication : Application() {
    private val startupScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val mutableContainer = MutableStateFlow<AppContainer?>(null)
    val container: StateFlow<AppContainer?> = mutableContainer.asStateFlow()

    @Volatile
    private var pendingDeepLink: String? = null

    override fun onCreate() {
        super.onCreate()
        if (!createContainerAutomatically) return
        // AppContainer loads DataStore-backed settings and cached wallet JSON.
        // Construct it away from the main thread so Application.onCreate can
        // return immediately and Android can draw the first frame.
        startupScope.launch {
            val built = createContainer()
            publishContainer(built)
            // No-op unless the user opted into crash reports.
            if (built.runtimePolicy.initializeTelemetry) {
                built.sentryService.initialize()
            }
        }
    }

    protected open val createContainerAutomatically: Boolean = true

    protected open fun createContainer(): AppContainer = AppContainer(this)

    @Synchronized
    fun handleDeepLink(url: String?) {
        if (url.isNullOrBlank()) return
        val current = mutableContainer.value
        if (current != null) {
            current.navigationManager.handleDeepLink(url)
        } else {
            pendingDeepLink = url
        }
    }

    @Synchronized
    protected fun publishContainer(container: AppContainer) {
        pendingDeepLink?.let(container.navigationManager::handleDeepLink)
        pendingDeepLink = null
        mutableContainer.value = container
    }
}

/** True only in processes running the debug-only UiTestApplication the
 * instrumentation runner installs — i.e. instrumented UI runs. Decorative
 * ambient motion (the onboarding ASCII field's clock) freezes there the
 * same way it does for Reduce Motion and battery saver, sparing the CI
 * emulator's software GPU. The production manifest always installs
 * [CashuWalletApplication], so this stays false outside tests. */
internal object UiTestRuntime {
    @Volatile var active = false
}
