package com.cashu.me.Core.Platform

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import com.google.android.gms.auth.api.identity.AuthorizationRequest
import com.google.android.gms.auth.api.identity.Identity
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.google.android.gms.common.api.Scope
import kotlinx.coroutines.tasks.await
import com.cashu.me.Core.AppLogger

/**
 * Opaque handle to the consent UI. Production wraps the Authorization API's
 * PendingIntent; JVM tests construct one from a lambda without touching
 * Android classes. Only the UI launcher ever unwraps it.
 */
fun interface DriveConsentResolution {
    fun pendingIntent(): PendingIntent
}

sealed interface DriveAuthorization {
    /** A usable OAuth access token for the drive.appdata scope. */
    data class Ready(val accessToken: String) : DriveAuthorization

    /** The user must grant access via this consent resolution (account picker + scope sheet). */
    data class NeedsResolution(val consent: DriveConsentResolution) : DriveAuthorization

    /** Google Play services is missing or broken on this device. */
    data object Unavailable : DriveAuthorization
}

/**
 * Token acquisition for Google Drive's appDataFolder via the Play services
 * Identity Authorization API. After the user has granted the scope once,
 * `authorize()` returns tokens silently — which is what lets fire-and-forget
 * backup triggers run without UI.
 */
interface DriveAuthClient {
    fun isPlayServicesAvailable(): Boolean
    suspend fun authorize(): DriveAuthorization

    /** Completes a NeedsResolution round-trip. Returns the token, or null when declined. */
    fun resultFromIntent(intent: Intent?): String?
}

class PlayServicesDriveAuth(context: Context) : DriveAuthClient {
    private val appContext = context.applicationContext

    override fun isPlayServicesAvailable(): Boolean =
        GoogleApiAvailability.getInstance()
            .isGooglePlayServicesAvailable(appContext) == ConnectionResult.SUCCESS

    override suspend fun authorize(): DriveAuthorization {
        if (!isPlayServicesAvailable()) return DriveAuthorization.Unavailable
        val request = AuthorizationRequest.builder()
            .setRequestedScopes(listOf(Scope(APP_DATA_SCOPE)))
            .build()
        return try {
            val result = Identity.getAuthorizationClient(appContext).authorize(request).await()
            val pendingIntent = result.pendingIntent
            when {
                result.hasResolution() && pendingIntent != null ->
                    DriveAuthorization.NeedsResolution { pendingIntent }
                result.accessToken != null -> DriveAuthorization.Ready(result.accessToken!!)
                else -> DriveAuthorization.Unavailable
            }
        } catch (t: Throwable) {
            AppLogger.network.error("Drive authorization failed", t)
            DriveAuthorization.Unavailable
        }
    }

    override fun resultFromIntent(intent: Intent?): String? {
        intent ?: return null
        return runCatching {
            Identity.getAuthorizationClient(appContext)
                .getAuthorizationResultFromIntent(intent)
                .accessToken
        }.getOrNull()
    }

    companion object {
        const val APP_DATA_SCOPE = "https://www.googleapis.com/auth/drive.appdata"
    }
}
