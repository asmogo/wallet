package com.cashu.me.test.fixtures

import android.content.Intent
import android.net.Uri
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.platform.app.InstrumentationRegistry
import com.cashu.me.App.AppContainer
import com.cashu.me.App.AppContainerDependencies
import com.cashu.me.App.MainActivity
import com.cashu.me.App.UiRuntimePolicy
import com.cashu.me.App.UiTestApplication
import com.cashu.me.Core.CDK.CdkWalletGatewayImpl
import com.cashu.me.Models.TransactionKind
import com.cashu.me.Models.PaymentMethodKind
import com.cashu.me.Models.TransactionStatus
import com.cashu.me.Models.TransactionType
import com.cashu.me.Models.WalletTransaction
import kotlinx.coroutines.runBlocking

enum class FixtureMode {
    EmptyWallet,
    SeededWithoutMint,
    SeededWithMint,
    FundedWithHistory,
    LiveSeededWithoutMint,
    LiveLocalMint,
}

data class LaunchedFixture(
    val scenario: ActivityScenario<MainActivity>,
    val container: AppContainer,
    val fakeGateway: FakeWalletGateway?,
) : AutoCloseable {
    override fun close() {
        scenario.close()
    }
}

/**
 * Installs a fixture before MainActivity exists, then launches the production
 * activity and Compose tree. No fake screen is rendered at any point.
 */
object AppTestFixture {
    fun launch(
        mode: FixtureMode,
        deepLink: String? = null,
        supportedMintMethods: List<PaymentMethodKind> = listOf(PaymentMethodKind.Bolt11),
    ): LaunchedFixture {
        val application = ApplicationProvider.getApplicationContext<UiTestApplication>()
        val usesLiveGateway = mode == FixtureMode.LiveLocalMint ||
            mode == FixtureMode.LiveSeededWithoutMint
        val mintUrl = if (usesLiveGateway) {
            InstrumentationRegistry.getArguments()
                .getString("cashu.nutshellMintUrl")
                ?.trim()
                ?.trimEnd('/')
                .orEmpty()
                .ifBlank { FakeWalletGateway.TestMintUrl }
        } else {
            FakeWalletGateway.TestMintUrl
        }

        val history = listOf(
            WalletTransaction(
                id = "fixture-incoming",
                amount = 120,
                type = TransactionType.Incoming,
                kind = TransactionKind.Lightning,
                dateEpochMillis = 1_750_000_000_000,
                memo = "Test deposit",
                status = TransactionStatus.Completed,
                mintUrl = mintUrl,
                invoice = "lnbc120n1fixture",
            ),
            WalletTransaction(
                id = "fixture-outgoing",
                amount = 30,
                type = TransactionType.Outgoing,
                kind = TransactionKind.Ecash,
                dateEpochMillis = 1_749_999_000_000,
                memo = "Test payment",
                status = TransactionStatus.Completed,
                mintUrl = mintUrl,
                fee = 1,
            ),
        )
        val fake = if (usesLiveGateway) {
            null
        } else {
            FakeWalletGateway(
                supportedMintMethods = supportedMintMethods,
                initialBalances = if (mode == FixtureMode.FundedWithHistory) {
                    mapOf(mintUrl to 500L)
                } else {
                    emptyMap()
                },
                initialTransactions = if (mode == FixtureMode.FundedWithHistory) history else emptyList(),
            )
        }
        val dependencies = AppContainerDependencies(
            runtimePolicy = UiRuntimePolicy.DeterministicTest,
            walletGateway = { fake ?: CdkWalletGatewayImpl() },
        )
        val container = AppContainer(application, dependencies)

        runBlocking {
            container.walletManager.initialize()
            if (mode != FixtureMode.EmptyWallet) {
                container.walletManager.createNewWalletFromMnemonic(FakeWalletGateway.FixedMnemonic)
            }
            if (mode == FixtureMode.SeededWithMint ||
                mode == FixtureMode.FundedWithHistory ||
                mode == FixtureMode.LiveLocalMint
            ) {
                container.walletManager.addMint(mintUrl)
                container.walletManager.refreshBalance()
                container.walletManager.loadTransactions()
            }
        }
        application.installContainer(container)

        val intent = Intent(application, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (!deepLink.isNullOrBlank()) {
                action = Intent.ACTION_VIEW
                data = Uri.parse(deepLink)
            }
        }
        val scenario = ActivityScenario.launch<MainActivity>(intent)
        return LaunchedFixture(
            scenario = scenario,
            container = container,
            fakeGateway = fake,
        )
    }
}
