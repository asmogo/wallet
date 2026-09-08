package com.cashu.me.Core

/**
 * Pure logic for the home balance unit pager (port of iOS HomeBalance).
 *
 * Held balances determine visibility independently of advertised payment units.
 */
object HomeBalance {
    /** Pager page order: sat first, then held non-sat units sorted. */
    fun homeBalanceUnits(balancesByUnit: Map<String, Long>): List<String> {
        val heldNonSat = balancesByUnit
            .filterKeys { it.lowercase() != "sat" }
            .filterValues { it > 0 }
            .keys
            .sorted()
        return listOf("sat") + heldNonSat
    }

    /** Clamp a persisted unit selection back to sat when it no longer holds balance. */
    fun resolvedUnit(unit: String, units: List<String>): String =
        if (units.contains(unit)) unit else "sat"

    fun showsUnitPager(
        balancesByUnit: Map<String, Long>,
    ): Boolean = homeBalanceUnits(balancesByUnit).size > 1
}
