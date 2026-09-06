package com.cashu.me.Core.CDK

import com.cashu.me.Core.PaymentRequestDecodeResult
import com.cashu.me.Models.PaymentMethodKind
import org.cashudevkit.CurrencyUnit as CdkCurrencyUnit
import org.cashudevkit.MeltOptions as CdkMeltOptions
import org.cashudevkit.MeltMethodSettings as CdkMeltMethodSettings
import org.cashudevkit.MintMethodSettings as CdkMintMethodSettings
import org.cashudevkit.Nut04Settings as CdkNut04Settings
import org.cashudevkit.Nut05Settings as CdkNut05Settings
import org.cashudevkit.Nut29Settings as CdkNut29Settings
import org.cashudevkit.Nuts as CdkNuts
import org.cashudevkit.PaymentMethod as CdkPaymentMethod
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * NUT-04/05 rails keep their tri-state through the CDK → domain mapping:
 * reported-empty stays empty (never substituted with BOLT11) and unknown custom
 * rails are dropped, matching iOS `supportedMintPaymentMethods` / `…Melt…`.
 */
class CdkMintMethodMappingTest {

    @Test
    fun amountlessBolt12MeltUsesEnteredAmountInMillisatoshis() {
        val options = meltOptionsForLightningRequest(
            decoded = PaymentRequestDecodeResult.Bolt12(amountSats = null, description = null),
            amountSats = 21L,
        )

        assertTrue(options is CdkMeltOptions.Amountless)
        assertEquals(21_000uL, (options as CdkMeltOptions.Amountless).amountMsat.value)
    }

    @Test
    fun amountCarryingBolt12DoesNotOverrideRequestAmount() {
        val options = meltOptionsForLightningRequest(
            decoded = PaymentRequestDecodeResult.Bolt12(amountSats = 21L, description = null),
            amountSats = 42L,
        )

        assertEquals(null, options)
    }

    @Test
    fun emptyNut04MethodListStaysReportedEmpty() {
        val nuts = nuts(nut04Methods = emptyList())

        assertTrue(nuts.reportedMintMethods().isEmpty())
    }

    @Test
    fun emptyNut05MethodListStaysReportedEmpty() {
        val nuts = nuts(nut05Methods = emptyList())

        assertTrue(nuts.reportedMeltMethods().isEmpty())
    }

    @Test
    fun mintMethodsAreDedupedAcrossUnitsAndSortedCanonically() {
        val nuts = nuts(
            nut04Methods = listOf(
                mintMethod(CdkPaymentMethod.Onchain, CdkCurrencyUnit.Sat),
                mintMethod(CdkPaymentMethod.Bolt11, CdkCurrencyUnit.Sat),
                mintMethod(CdkPaymentMethod.Bolt11, CdkCurrencyUnit.Usd),
                mintMethod(CdkPaymentMethod.Bolt12, CdkCurrencyUnit.Sat),
            ),
        )

        assertEquals(
            listOf(PaymentMethodKind.Bolt11, PaymentMethodKind.Bolt12, PaymentMethodKind.Onchain),
            nuts.reportedMintMethods(),
        )
    }

    @Test
    fun meltMethodsStaySatOnly() {
        val nuts = nuts(
            nut05Methods = listOf(
                meltMethod(CdkPaymentMethod.Bolt11, CdkCurrencyUnit.Usd),
                meltMethod(CdkPaymentMethod.Bolt12, CdkCurrencyUnit.Sat),
            ),
        )

        assertEquals(listOf(PaymentMethodKind.Bolt12), nuts.reportedMeltMethods())
    }

    @Test
    fun unknownCustomMethodsAreDroppedNotRemapped() {
        val nuts = nuts(
            nut04Methods = listOf(
                mintMethod(CdkPaymentMethod.Custom("unknown"), CdkCurrencyUnit.Sat),
            ),
            nut05Methods = listOf(
                meltMethod(CdkPaymentMethod.Custom("unknown"), CdkCurrencyUnit.Sat),
            ),
        )

        assertTrue(nuts.reportedMintMethods().isEmpty())
        assertTrue(nuts.reportedMeltMethods().isEmpty())
    }

    @Test
    fun bolt12MintDescriptionFailsClosedUnlessAdvertisedTrue() {
        assertEquals(
            false,
            nuts(nut04Methods = emptyList()).reportsBolt12MintDescription(),
        )
        assertEquals(
            false,
            nuts(
                nut04Methods = listOf(
                    mintMethod(CdkPaymentMethod.Bolt12, CdkCurrencyUnit.Sat, description = null),
                ),
            ).reportsBolt12MintDescription(),
        )
        assertEquals(
            false,
            nuts(
                nut04Methods = listOf(
                    mintMethod(CdkPaymentMethod.Bolt12, CdkCurrencyUnit.Sat, description = false),
                ),
            ).reportsBolt12MintDescription(),
        )
        assertEquals(
            false,
            nuts(
                nut04Methods = listOf(
                    mintMethod(CdkPaymentMethod.Bolt11, CdkCurrencyUnit.Sat, description = true),
                ),
            ).reportsBolt12MintDescription(),
        )
        assertEquals(
            true,
            nuts(
                nut04Methods = listOf(
                    mintMethod(CdkPaymentMethod.Bolt11, CdkCurrencyUnit.Sat, description = false),
                    mintMethod(CdkPaymentMethod.Bolt12, CdkCurrencyUnit.Sat, description = true),
                ),
            ).reportsBolt12MintDescription(),
        )
        // Any bolt12 unit advertising true is enough.
        assertEquals(
            true,
            nuts(
                nut04Methods = listOf(
                    mintMethod(CdkPaymentMethod.Bolt12, CdkCurrencyUnit.Usd, description = false),
                    mintMethod(CdkPaymentMethod.Bolt12, CdkCurrencyUnit.Sat, description = true),
                ),
            ).reportsBolt12MintDescription(),
        )
    }

    private fun mintMethod(
        method: CdkPaymentMethod,
        unit: CdkCurrencyUnit,
        description: Boolean? = null,
    ) =
        CdkMintMethodSettings(
            method = method,
            unit = unit,
            methodName = null,
            minAmount = null,
            maxAmount = null,
            description = description,
        )

    private fun meltMethod(method: CdkPaymentMethod, unit: CdkCurrencyUnit) =
        CdkMeltMethodSettings(
            method = method,
            unit = unit,
            methodName = null,
            minAmount = null,
            maxAmount = null,
            amountless = null,
        )

    private fun nuts(
        nut04Methods: List<CdkMintMethodSettings> = listOf(
            mintMethod(CdkPaymentMethod.Bolt11, CdkCurrencyUnit.Sat),
        ),
        nut05Methods: List<CdkMeltMethodSettings> = listOf(
            meltMethod(CdkPaymentMethod.Bolt11, CdkCurrencyUnit.Sat),
        ),
    ) = CdkNuts(
        nut04 = CdkNut04Settings(methods = nut04Methods, disabled = false),
        nut05 = CdkNut05Settings(methods = nut05Methods, disabled = false),
        nut07Supported = false,
        nut08Supported = false,
        nut09Supported = false,
        nut10Supported = false,
        nut11Supported = false,
        nut12Supported = false,
        nut14Supported = false,
        nut20Supported = false,
        nut21 = null,
        nut22 = null,
        nut29 = CdkNut29Settings(maxBatchSize = null, methods = null),
        mintUnits = listOf(CdkCurrencyUnit.Sat),
        meltUnits = listOf(CdkCurrencyUnit.Sat),
    )
}
