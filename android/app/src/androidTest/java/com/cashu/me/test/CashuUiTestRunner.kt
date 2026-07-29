package com.cashu.me.test

import android.app.Application
import android.content.Context
import android.os.Bundle
import androidx.test.runner.AndroidJUnitRunner
import com.cashu.me.App.UiTestApplication
import java.util.Locale

/**
 * Instrumentation runner that gives app-level tests control of container
 * creation. Android Test Orchestrator launches a fresh process for every test,
 * so an installed fixture can never bleed into the next journey.
 */
class CashuUiTestRunner : AndroidJUnitRunner() {
    override fun onCreate(arguments: Bundle?) {
        Locale.setDefault(Locale.US)
        super.onCreate(arguments)
    }

    override fun newApplication(
        classLoader: ClassLoader?,
        className: String?,
        context: Context?,
    ): Application = super.newApplication(
        classLoader,
        UiTestApplication::class.java.name,
        context,
    )
}
