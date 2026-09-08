package com.cashu.me.Core

import android.content.Context
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import kotlin.coroutines.resume
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.suspendCancellableCoroutine

data class AppLockState(
    val isLocked: Boolean = false,
    val isAuthenticating: Boolean = false,
    val isObscured: Boolean = false,
    val isAvailable: Boolean = false,
)

class AppLockManager(
    context: Context,
    private val settingsManager: SettingsManager,
    private val nowMillis: () -> Long = { System.currentTimeMillis() },
    private val authenticationAvailable: (() -> Boolean)? = null,
    private val authenticationPrompt: (suspend (String) -> Boolean)? = null,
) {
    private val appContext = context.applicationContext
    private val authenticators =
        BiometricManager.Authenticators.BIOMETRIC_WEAK or BiometricManager.Authenticators.DEVICE_CREDENTIAL
    private var runtime = AppLockPolicy.initial(isAvailable = canAuthenticate())
    private val mutableState = MutableStateFlow(runtime.state)
    val state: StateFlow<AppLockState> = mutableState.asStateFlow()

    fun startAuthenticatedSession() {
        applyRuntime(
            AppLockPolicy.startAuthenticatedSession(
                runtime = runtime,
                appLockEnabled = settingsManager.state.value.appLockEnabled,
                isAvailable = canAuthenticate(),
            ),
        )
    }

    fun endAuthenticatedSession() {
        applyRuntime(AppLockPolicy.endAuthenticatedSession(isAvailable = canAuthenticate()))
    }

    fun setEnabled(enabled: Boolean) {
        if (!enabled) {
            applyRuntime(AppLockPolicy.setEnabled(runtime, enabled = false))
            return
        }
        refreshAvailability()
    }

    fun appResignedActive() {
        applyRuntime(
            AppLockPolicy.appResignedActive(
                runtime = runtime,
                appLockEnabled = settingsManager.state.value.appLockEnabled,
                nowMillis = nowMillis(),
            ),
        )
    }

    fun appBecameActive() {
        applyRuntime(
            AppLockPolicy.appBecameActive(
                runtime = runtime,
                appLockEnabled = settingsManager.state.value.appLockEnabled,
                nowMillis = nowMillis(),
            ),
        )
    }

    fun refreshAvailability(): Boolean {
        val available = canAuthenticate()
        if (!available && settingsManager.state.value.appLockEnabled) {
            AppLogger.security.info("App Lock authentication unavailable; wallet remains unlocked")
        }
        applyRuntime(
            AppLockPolicy.refreshAvailability(
                runtime = runtime,
                appLockEnabled = settingsManager.state.value.appLockEnabled,
                isAvailable = available,
            ),
        )
        return available
    }

    suspend fun authenticate(
        activity: FragmentActivity?,
        reason: String = "Unlock your wallet",
    ): Boolean = authenticate(
        activity = activity,
        reason = reason,
        succeedWhenUnavailable = true,
    )

    /**
     * Confirms that the user can satisfy App Lock before the setting is enabled.
     * Unlike the runtime unlock path, unavailable authentication must fail closed:
     * persisting an unusable lock would leave the setting enabled without a
     * successful device-owner challenge.
     */
    suspend fun authenticateForAppLockEnablement(
        activity: FragmentActivity?,
    ): Boolean = authenticate(
        activity = activity,
        reason = "Confirm to enable App Lock",
        succeedWhenUnavailable = false,
    )

    private suspend fun authenticate(
        activity: FragmentActivity?,
        reason: String,
        succeedWhenUnavailable: Boolean,
    ): Boolean {
        if (mutableState.value.isAuthenticating) return false
        if (!refreshAvailability()) {
            if (succeedWhenUnavailable) {
                applyRuntime(AppLockPolicy.authenticated(runtime))
            }
            return succeedWhenUnavailable
        }
        if (activity == null) {
            AppLogger.security.error("Authentication unavailable: no FragmentActivity")
            return false
        }

        applyRuntime(AppLockPolicy.authenticating(runtime, isAuthenticating = true))
        return try {
            val success = authenticationPrompt?.invoke(reason) ?: prompt(activity, reason)
            if (success) applyRuntime(AppLockPolicy.authenticated(runtime))
            success
        } finally {
            applyRuntime(AppLockPolicy.authenticating(runtime, isAuthenticating = false))
        }
    }

    private suspend fun prompt(activity: FragmentActivity, reason: String): Boolean =
        suspendCancellableCoroutine { continuation ->
            val executor = ContextCompat.getMainExecutor(activity)
            val prompt = BiometricPrompt(
                activity,
                executor,
                object : BiometricPrompt.AuthenticationCallback() {
                    override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                        if (continuation.isActive) continuation.resume(true)
                    }

                    override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                        if (continuation.isActive) {
                            AppLogger.security.info("Authentication not completed")
                            continuation.resume(false)
                        }
                    }

                    override fun onAuthenticationFailed() {
                        AppLogger.security.info("Authentication failed")
                    }
                },
            )
            val promptInfo = BiometricPrompt.PromptInfo.Builder()
                .setTitle(reason)
                .setSubtitle("Authenticate to continue.")
                .setAllowedAuthenticators(authenticators)
                .build()
            continuation.invokeOnCancellation { prompt.cancelAuthentication() }
            runCatching { prompt.authenticate(promptInfo) }
                .onFailure { error ->
                    AppLogger.security.error("Authentication prompt failed", error)
                    if (continuation.isActive) continuation.resume(false)
                }
        }

    /** Whether biometrics specifically (not just a device credential) can authenticate. */
    fun hasEnrolledBiometrics(): Boolean =
        BiometricManager.from(appContext)
            .canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_WEAK) == BiometricManager.BIOMETRIC_SUCCESS

    private fun canAuthenticate(): Boolean =
        authenticationAvailable?.invoke()
            ?: (BiometricManager.from(appContext).canAuthenticate(authenticators) == BiometricManager.BIOMETRIC_SUCCESS)

    private fun applyRuntime(next: AppLockRuntime) {
        runtime = next
        mutableState.value = next.state
    }
}
