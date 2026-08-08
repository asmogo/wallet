package com.cashu.me.ui.shell

import org.junit.Assert.assertEquals
import org.junit.Test

class WalletFlowHandoffCoordinatorTest {
    @Test
    fun destinationDispatchesOnlyAfterSheetDismissalCompletes() {
        val events = mutableListOf<Any>()
        val coordinator = WalletFlowHandoffCoordinator()

        coordinator.request(FlowHandoffDestination.Scanner(ScannerTarget.Auto)) {
            events += "close-sheet"
        }

        assertEquals(listOf<Any>("close-sheet"), events)

        coordinator.completeDismissal { events += it }

        assertEquals(
            listOf("close-sheet", FlowHandoffDestination.Scanner(ScannerTarget.Auto)),
            events,
        )
    }

    @Test
    fun completedHandoffIsConsumedExactlyOnceWithPayloadIntact() {
        val dispatched = mutableListOf<FlowHandoffDestination>()
        val coordinator = WalletFlowHandoffCoordinator()

        coordinator.request(FlowHandoffDestination.ReceiveDetail("cashuAeyJ0b2tlbiI")) {}
        repeat(2) {
            coordinator.completeDismissal { dispatched += it }
        }

        assertEquals(
            listOf<FlowHandoffDestination>(
                FlowHandoffDestination.ReceiveDetail("cashuAeyJ0b2tlbiI"),
            ),
            dispatched,
        )
    }

    @Test
    fun secondRequestBeforeDismissalReplacesTheFirst() {
        val dispatched = mutableListOf<FlowHandoffDestination>()
        val coordinator = WalletFlowHandoffCoordinator()

        coordinator.request(FlowHandoffDestination.Scanner(ScannerTarget.Auto)) {}
        coordinator.request(FlowHandoffDestination.Scanner(ScannerTarget.P2pkLock)) {}
        coordinator.completeDismissal { dispatched += it }

        assertEquals(
            listOf<FlowHandoffDestination>(
                FlowHandoffDestination.Scanner(ScannerTarget.P2pkLock),
            ),
            dispatched,
        )
    }

    @Test
    fun plainDismissalDispatchesNothing() {
        val dispatched = mutableListOf<FlowHandoffDestination>()

        WalletFlowHandoffCoordinator().completeDismissal { dispatched += it }

        assertEquals(emptyList<FlowHandoffDestination>(), dispatched)
    }
}
