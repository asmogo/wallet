package com.cashu.me.ui.shell

/**
 * Unprompted surfaces — deep-linked payments, incoming NUT-18 payments held
 * for approval — defer until every payment surface is idle. They must never
 * stack on, or replace, a story the user is in the middle of; nothing is
 * dropped, the pending payload re-presents when the shell goes idle.
 */
internal fun shellIsIdleForInterrupt(
    isRuntimeReady: Boolean,
    receiveDetailVisible: Boolean,
    flowActive: Boolean,
    scannerVisible: Boolean,
    locked: Boolean,
): Boolean =
    isRuntimeReady &&
        !receiveDetailVisible &&
        !flowActive &&
        !scannerVisible &&
        !locked
