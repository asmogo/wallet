package com.cashu.me.App

/**
 * Debug-only application installed by [com.cashu.me.test.CashuUiTestRunner].
 *
 * It deliberately publishes no container on process start. Each app-level
 * instrumentation test installs its deterministic fixture before launching
 * MainActivity, eliminating races with production startup.
 */
class UiTestApplication : CashuWalletApplication() {
    override val createContainerAutomatically: Boolean = false

    override fun onCreate() {
        // Marks the process as an instrumented UI run so decorative ambient
        // motion (the onboarding ASCII field's clock) freezes like it does
        // for Reduce Motion — see UiTestRuntime.
        UiTestRuntime.active = true
        super.onCreate()
    }

    fun installContainer(container: AppContainer) {
        check(this.container.value == null) {
            "A UI-test container is already installed in this process."
        }
        publishContainer(container)
    }
}
