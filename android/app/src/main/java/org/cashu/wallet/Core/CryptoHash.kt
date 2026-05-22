package org.cashu.wallet.Core

import java.security.MessageDigest

fun ByteArray.sha256(): ByteArray = MessageDigest.getInstance("SHA-256").digest(this)
