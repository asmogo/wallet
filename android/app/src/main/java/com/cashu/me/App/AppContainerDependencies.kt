package com.cashu.me.App

import android.content.Context
import com.cashu.me.Core.CDK.CdkWalletGatewayImpl
import com.cashu.me.Core.CDK.WalletGateway
import com.cashu.me.Core.Platform.AndroidSecureStorage
import com.cashu.me.Core.Protocols.SecureStorage
import com.cashu.me.Core.SettingsStore
import com.cashu.me.Core.WalletStore
import com.cashu.me.Core.PriceService
import com.cashu.me.Core.AppLockManager
import com.cashu.me.Core.SettingsManager
import com.cashu.me.Core.NPCService

/**
 * Runtime switches for work that is unrelated to an explicitly requested UI
 * action. Production retains every behavior; deterministic instrumentation
 * disables network listeners, telemetry and timer-driven maintenance.
 */
data class UiRuntimePolicy(
    val initializeTelemetry: Boolean = true,
    val startExternalListeners: Boolean = true,
    val runStartupMaintenance: Boolean = true,
    val startNwc: Boolean = true,
    val pollQuotesInForeground: Boolean = true,
    val allowAutomaticClipboardReads: Boolean = true,
    val allowCleartextLocalTestMints: Boolean = false,
    val useDeterministicCameraPermission: Boolean = false,
) {
    companion object {
        val Production = UiRuntimePolicy()
        val DeterministicTest = UiRuntimePolicy(
            initializeTelemetry = false,
            startExternalListeners = false,
            runStartupMaintenance = false,
            startNwc = false,
            pollQuotesInForeground = false,
            allowAutomaticClipboardReads = false,
            allowCleartextLocalTestMints = true,
            useDeterministicCameraPermission = true,
        )
    }
}

/**
 * Manual dependency-injection seam shared by production and instrumentation.
 *
 * Stores remain Android-backed by default. Test Orchestrator clears their
 * package data between tests, while fixtures can still supply named stores or
 * an in-memory gateway when a journey needs tighter control.
 */
data class AppContainerDependencies(
    val runtimePolicy: UiRuntimePolicy = UiRuntimePolicy.Production,
    val walletGateway: () -> WalletGateway = { CdkWalletGatewayImpl() },
    val secureStorage: (Context) -> SecureStorage = { AndroidSecureStorage(it) },
    val walletStore: (Context) -> WalletStore = { WalletStore(it) },
    val settingsStore: (Context) -> SettingsStore = { SettingsStore(it) },
    val priceService: (SettingsStore) -> PriceService = { PriceService(it) },
    val appLockManager: (Context, SettingsManager) -> AppLockManager = { context, settings ->
        AppLockManager(context, settings)
    },
    val npcService: (Context, SettingsManager) -> NPCService = { context, settings -> NPCService(context, settings) },
)
