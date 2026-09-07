package com.cashu.me.Core

import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import com.cashu.me.Core.Protocols.CurrencyAmount
import com.cashu.me.Core.Protocols.CurrencyRegistry
import com.cashu.me.test.fixtures.AppTestFixture
import com.cashu.me.test.fixtures.FakeWalletGateway
import com.cashu.me.test.fixtures.FixtureMode
import com.cashu.me.ui.testing.UiTestTags
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

class StoredCurrencyVisibilityInstrumentedTest {
    @Test fun storedCurrencyRemainsVisibleWithSatOnlyMintMetadata() {
        val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
        AppTestFixture.launch(FixtureMode.FundedWithHistory).use { fixture ->
            val fake = checkNotNull(fixture.fakeGateway)
            val manager = fixture.container.walletManager
            runBlocking {
                fake.setUnitBalance(FakeWalletGateway.TestMintUrl, "usd", 500)
                manager.refreshBalance()
            }
            assertEquals(listOf("sat"), manager.state.value.activeMint?.units)
            assertEquals(listOf("sat", "usd"), runBlocking { manager.storedAccountUnits(FakeWalletGateway.TestMintUrl) })
            assertTrue(device.wait(Until.hasObject(By.text("Mints")), 5_000))
            device.waitForIdle(5_000)
            // Derive the swipe from the displayed balance's actual bounds.
            val hero = device.wait(Until.findObject(By.descContains("500")), 5_000)
            assertNotNull(hero)
            val heroY = hero.visibleBounds.centerY()
            device.swipe(device.displayWidth * 4 / 5, heroY,
                device.displayWidth / 5, heroY, 20)
            val amount = CurrencyAmount(500, CurrencyRegistry.currencyForMintUnit("usd")).formatted()
            assertTrue(device.wait(Until.hasObject(By.descContains(amount)), 5_000))
            device.findObject(By.text("Mints")).click()
            val row = device.wait(Until.findObject(By.res(UiTestTags.mintRow(FakeWalletGateway.TestMintUrl))), 5_000)
            assertNotNull(row)
            row.click()
            assertTrue(device.wait(Until.hasObject(By.text("Balance (USD)")), 5_000))
            assertTrue(device.hasObject(By.text(amount)))
        }
    }
}
