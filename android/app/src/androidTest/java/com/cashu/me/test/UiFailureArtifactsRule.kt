package com.cashu.me.test

import android.util.Log
import androidx.compose.ui.test.isRoot
import androidx.compose.ui.test.junit4.ComposeTestRule
import androidx.compose.ui.test.printToString
import androidx.test.core.graphics.writeToTestStorage
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.platform.io.PlatformTestStorageRegistry
import org.junit.rules.TestWatcher
import org.junit.runner.Description

/**
 * Captures the state needed to diagnose a managed-device failure without
 * reproducing it locally. GitHub Actions uploads these files with the normal
 * managed-device reports and logcat.
 */
class UiFailureArtifactsRule(
    private val compose: ComposeTestRule,
    private val onFinished: () -> Unit = {},
) : TestWatcher() {
    override fun failed(error: Throwable?, description: Description) {
        val baseName = description.displayName
            .replace(Regex("[^A-Za-z0-9._-]"), "_")
            .take(120)

        captureArtifact("screenshot") {
            checkNotNull(
                InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot(),
            ).writeToTestStorage("$baseName-failure")
        }
        captureArtifact("merged semantics") {
            val storage = PlatformTestStorageRegistry.getInstance()
            storage.openOutputFile("$baseName-semantics-merged.txt").bufferedWriter().use {
                it.write(
                    compose.onAllNodes(isRoot(), useUnmergedTree = false)
                        .printToString(maxDepth = 80),
                )
            }
        }
        captureArtifact("unmerged semantics") {
            val storage = PlatformTestStorageRegistry.getInstance()
            storage.openOutputFile("$baseName-semantics-unmerged.txt").bufferedWriter().use {
                it.write(
                    compose.onAllNodes(isRoot(), useUnmergedTree = true)
                        .printToString(maxDepth = 80),
                )
            }
        }
    }

    override fun finished(description: Description) {
        onFinished()
    }

    private inline fun captureArtifact(label: String, block: () -> Unit) {
        runCatching(block).onFailure {
            Log.e(LogTag, "Unable to capture $label", it)
        }
    }

    private companion object {
        const val LogTag = "UiFailureArtifacts"
    }
}
