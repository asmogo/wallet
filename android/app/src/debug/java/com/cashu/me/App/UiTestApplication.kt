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

    fun installContainer(container: AppContainer) {
        check(this.container.value == null) {
            "A UI-test container is already installed in this process."
        }
        publishContainer(container)
    }
}
