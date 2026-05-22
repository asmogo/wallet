package org.cashu.wallet.Core

import android.util.Log

object AppLogger {
    private const val prefix = "CashuWallet"

    object wallet {
        fun info(message: String) = Log.i("$prefix.Wallet", message)
        fun debug(message: String) = Log.d("$prefix.Wallet", message)
        fun error(message: String, throwable: Throwable? = null) = Log.e("$prefix.Wallet", message, throwable)
    }

    object security {
        fun info(message: String) = Log.i("$prefix.Security", message)
        fun debug(message: String) = Log.d("$prefix.Security", message)
        fun error(message: String, throwable: Throwable? = null) = Log.e("$prefix.Security", message, throwable)
    }

    object network {
        fun info(message: String) = Log.i("$prefix.Network", message)
        fun debug(message: String) = Log.d("$prefix.Network", message)
        fun error(message: String, throwable: Throwable? = null) = Log.e("$prefix.Network", message, throwable)
    }
}
