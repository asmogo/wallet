package com.cashu.me.Core.CDK

import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Test

class CdkGatewayThreadingTest {
    @Test
    fun cdkGatewayOperationsAreGuardedOffMainThread() {
        val source = sourceFile(
            "src/main/java/com/cashu/me/Core/CDK/CdkWalletGatewayImpl.kt",
            "app/src/main/java/com/cashu/me/Core/CDK/CdkWalletGatewayImpl.kt",
        ).readText()

        assertTrue(source.contains("private val operationMutex = Mutex()"))
        assertTrue(source.contains("withContext(Dispatchers.IO)"))
        assertTrue(source.contains("operationMutex.withLock"))

        val missingGuard = Regex("""override suspend fun\s+([A-Za-z0-9_]+)""")
            .findAll(source)
            .map { it.groupValues[1] }
            .filter { method ->
                val declarationStart = source.indexOf("override suspend fun $method")
                // Signatures may span multiple lines; the first opening brace
                // closes the declaration because guarded methods use `= cdkCall {`.
                val declarationEnd = source.indexOf('{', declarationStart).takeIf { it >= 0 } ?: source.length
                !source.substring(declarationStart, declarationEnd).contains("= cdkCall")
            }
            .toList()

        assertTrue("Expected CDK suspend methods to use cdkCall: $missingGuard", missingGuard.isEmpty())
    }

    @Test
    fun mintQuoteSubscriptionDoesNotHoldGatewayLockWhileWaiting() {
        val source = sourceFile(
            "src/main/java/com/cashu/me/Core/CDK/CdkWalletGatewayImpl.kt",
            "app/src/main/java/com/cashu/me/Core/CDK/CdkWalletGatewayImpl.kt",
        ).readText()

        assertTrue(source.contains("val subscription = cdkCall"))
        assertTrue(source.contains("subscription.recv()"))
        assertTrue(source.contains("}.flowOn(Dispatchers.IO)"))
    }

    @Test
    fun safeMintRemovalEnumeratesAndRemovesInsideOneGatewayCall() {
        val source = sourceFile(
            "src/main/java/com/cashu/me/Core/CDK/CdkWalletGatewayImpl.kt",
            "app/src/main/java/com/cashu/me/Core/CDK/CdkWalletGatewayImpl.kt",
        ).readText()
        val methodStart = source.indexOf("override suspend fun removeWalletIfSingleUnit")
        assertTrue(methodStart >= 0)
        val methodEnd = source.indexOf("\n    override suspend fun", methodStart + 1)
            .takeIf { it >= 0 }
            ?: source.length
        val method = source.substring(methodStart, methodEnd)

        assertTrue(method.contains("= cdkCall {"))
        assertTrue(method.contains("getWallets()"))
        assertTrue(method.contains("repository.removeWallet("))
    }

    private fun sourceFile(vararg candidates: String): File {
        val roots = generateSequence(File("").absoluteFile) { it.parentFile }
        return roots
            .flatMap { root -> candidates.asSequence().map { File(root, it) } }
            .firstOrNull { it.exists() }
            ?: error("Missing test fixture: ${candidates.joinToString()}")
    }
}
