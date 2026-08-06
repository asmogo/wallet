package com.cashu.me.App

import android.content.Context
import androidx.compose.material3.SnackbarHostState
import java.security.MessageDigest
import com.cashu.me.Core.AppLockManager
import com.cashu.me.Core.CashuRequestListener
import com.cashu.me.Core.CashuRequestStore
import com.cashu.me.Core.MintDiscoveryManager
import com.cashu.me.Core.NPCService
import com.cashu.me.Core.Navigation.NavigationManager
import com.cashu.me.Core.NostrMintBackupService
import com.cashu.me.Core.NostrService
import com.cashu.me.Core.NwcManager
import com.cashu.me.Core.NfcReceive.NfcReceiveCoordinator
import com.cashu.me.Core.Platform.AndroidConnectivityObserver
import com.cashu.me.Core.Platform.WalletDatabasePathManager
import com.cashu.me.Core.PriceService
import com.cashu.me.Core.PrimaryP2PKKey
import com.cashu.me.Core.SentryService
import com.cashu.me.Core.SettingsManager
import com.cashu.me.Core.WalletManager
import com.cashu.me.Core.Protocols.StorageKeys

class AppContainer(
    context: Context,
    dependencies: AppContainerDependencies = AppContainerDependencies(),
) {
    private val appContext = context.applicationContext
    val runtimePolicy = dependencies.runtimePolicy
    val secureStorage = dependencies.secureStorage(appContext)
    val walletStore = dependencies.walletStore(appContext)
    val cashuRequestStore = CashuRequestStore(walletStore)
    val settingsStore = dependencies.settingsStore(appContext)
    val settingsManager = SettingsManager(settingsStore, secureStorage)
    val appLockManager = AppLockManager(appContext, settingsManager)
    val sentryService = SentryService(appContext, settingsStore)
    val nostrService = NostrService(secureStorage, settingsStore)
    val navigationManager = NavigationManager()
    val snackbarHostState = SnackbarHostState()
    val connectivityObserver = AndroidConnectivityObserver(appContext)
    val walletDatabasePathManager = WalletDatabasePathManager(appContext)
    val cdkGateway = dependencies.walletGateway()
    val nwcManager = NwcManager(
        settingsStore = settingsStore,
        secureStorage = secureStorage,
        gateway = cdkGateway,
        seedProvider = {
            secureStorage.loadString(StorageKeys.secureWalletMnemonic)?.let { mnemonic ->
                MessageDigest.getInstance("SHA-512").digest(mnemonic.toByteArray(Charsets.UTF_8))
            }
        },
        relayProvider = { settingsManager.state.value.nostrRelays },
    )
    val npcService = NPCService(appContext, settingsManager)
    val nostrMintBackupService = NostrMintBackupService(settingsManager, settingsStore, cdkGateway)
    val walletManager = WalletManager(
        secureStorage = secureStorage,
        walletStore = walletStore,
        cashuRequestStore = cashuRequestStore,
        settingsManager = settingsManager,
        nostrService = nostrService,
        npcService = npcService,
        nwcManager = nwcManager,
        nostrMintBackupService = nostrMintBackupService,
        databasePathManager = walletDatabasePathManager,
        gateway = cdkGateway,
        runStartupMaintenance = runtimePolicy.runStartupMaintenance,
        startNwc = runtimePolicy.startNwc,
        pollQuotesInForeground = runtimePolicy.pollQuotesInForeground,
        externalServicesEnabled = runtimePolicy.startExternalListeners,
        allowCleartextLocalTestMints = runtimePolicy.allowCleartextLocalTestMints,
    )
    val priceService = PriceService(settingsStore)
    val mintDiscoveryManager = MintDiscoveryManager(settingsManager)
    val cashuRequestListener = CashuRequestListener(
        nostrService = nostrService,
        settingsManager = settingsManager,
        walletManager = walletManager,
        cashuRequestStore = cashuRequestStore,
        walletStore = walletStore,
    )
    val nfcReceiveCoordinator = NfcReceiveCoordinator(
        context = appContext,
        walletManager = walletManager,
        requestStore = cashuRequestStore,
    )

    init {
        walletManager.cashuRequestListener = cashuRequestListener
        npcService.quoteClaimHandler = walletManager
        settingsManager.sentryService = sentryService
        settingsManager.claimEligibleHeldPayments =
            cashuRequestListener::claimEligibleHeldPaymentsAsync
        // Seed-derived primary P2PK key (iOS primaryP2PKPublicKey/PrivateKeyHex):
        // included in the signing set so ecash locked to the wallet's own key
        // (e.g. NPC locked quotes, locked receive requests) is redeemable.
        settingsManager.primaryP2PKKeyProvider = provider@{
            val privateKeyHex = nostrService.seedDerivedPrivateKeyHex() ?: return@provider null
            val publicKeyHex = nostrService.seedDerivedPublicKeyHex()
                .takeIf { it.length == 64 } ?: return@provider null
            PrimaryP2PKKey(publicKey = "02$publicKeyHex", privateKeyHex = privateKeyHex)
        }
    }
}
