package org.cashu.wallet.App

import android.content.Context
import org.cashu.wallet.Core.CDK.CdkWalletGatewayImpl
import org.cashu.wallet.Core.CashuRequestListener
import org.cashu.wallet.Core.MintDiscoveryManager
import org.cashu.wallet.Core.NPCService
import org.cashu.wallet.Core.Navigation.NavigationManager
import org.cashu.wallet.Core.NostrService
import org.cashu.wallet.Core.Platform.AndroidConnectivityObserver
import org.cashu.wallet.Core.Platform.AndroidSecureStorage
import org.cashu.wallet.Core.Platform.WalletDatabasePathManager
import org.cashu.wallet.Core.PriceService
import org.cashu.wallet.Core.SettingsManager
import org.cashu.wallet.Core.SettingsStore
import org.cashu.wallet.Core.WalletManager
import org.cashu.wallet.Core.WalletStore

class AppContainer(context: Context) {
    private val appContext = context.applicationContext
    val secureStorage = AndroidSecureStorage(appContext)
    val walletStore = WalletStore(appContext)
    val settingsStore = SettingsStore(appContext)
    val settingsManager = SettingsManager(settingsStore, secureStorage)
    val nostrService = NostrService(secureStorage, settingsStore)
    val navigationManager = NavigationManager()
    val connectivityObserver = AndroidConnectivityObserver(appContext)
    val walletDatabasePathManager = WalletDatabasePathManager(appContext)
    val cdkGateway = CdkWalletGatewayImpl()
    val npcService = NPCService(appContext, nostrService, settingsManager)
    val walletManager = WalletManager(
        secureStorage = secureStorage,
        walletStore = walletStore,
        settingsManager = settingsManager,
        nostrService = nostrService,
        npcService = npcService,
        databasePathManager = walletDatabasePathManager,
        gateway = cdkGateway,
    )
    val priceService = PriceService(settingsStore)
    val mintDiscoveryManager = MintDiscoveryManager(settingsManager)
    val cashuRequestListener = CashuRequestListener(
        context = appContext,
        nostrService = nostrService,
        settingsManager = settingsManager,
        walletManager = walletManager,
    )

    init {
        npcService.quoteClaimHandler = walletManager
    }
}
