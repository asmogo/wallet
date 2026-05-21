package org.cashu.wallet.Core

internal fun nextTransactionUpdateVersion(current: Long): Long =
    if (current == Long.MAX_VALUE) 1 else current + 1

