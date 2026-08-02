package com.cashu.me.Core.Platform

import android.content.Context
import com.google.android.gms.auth.blockstore.Blockstore
import com.google.android.gms.auth.blockstore.DeleteBytesRequest
import com.google.android.gms.auth.blockstore.RetrieveBytesRequest
import com.google.android.gms.auth.blockstore.StoreBytesData
import kotlinx.coroutines.tasks.await

/**
 * Block Store copy of the wallet backup. Data stored here transfers to a new
 * device during Android's setup restore flow (cloud restore or device-to-device)
 * with no sign-in; the cloud replica is end-to-end encrypted when the device
 * has a screen lock. This is the E2E complement to the (non-E2E) Drive copy —
 * it cannot replace it because it is unreachable after a fresh device setup.
 */
interface BlockStoreFacade {
    suspend fun store(bytes: ByteArray)
    suspend fun retrieve(): ByteArray?
    suspend fun deleteAll()
}

class PlayServicesBlockStore(context: Context) : BlockStoreFacade {
    private val client = Blockstore.getClient(context.applicationContext)

    override suspend fun store(bytes: ByteArray) {
        // Cloud replication only when it would be end-to-end encrypted; the
        // local entry still transfers during cable/D2D setup either way.
        val e2eAvailable = runCatching {
            client.isEndToEndEncryptionAvailable.await()
        }.getOrDefault(false)
        val data = StoreBytesData.Builder()
            .setBytes(bytes)
            .setKey(ENTRY_KEY)
            .setShouldBackupToCloud(e2eAvailable)
            .build()
        client.storeBytes(data).await()
    }

    override suspend fun retrieve(): ByteArray? {
        val request = RetrieveBytesRequest.Builder()
            .setKeys(listOf(ENTRY_KEY))
            .build()
        val response = client.retrieveBytes(request).await()
        return response.blockstoreDataMap[ENTRY_KEY]?.bytes
    }

    override suspend fun deleteAll() {
        val request = DeleteBytesRequest.Builder()
            .setKeys(listOf(ENTRY_KEY))
            .build()
        client.deleteBytes(request).await()
    }

    companion object {
        const val ENTRY_KEY = "com.cashu.me.wallet_backup"
    }
}
