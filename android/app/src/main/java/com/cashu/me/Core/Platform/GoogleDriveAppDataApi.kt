package com.cashu.me.Core.Platform

import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.HttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import com.cashu.me.Core.DriveBackupException

data class DriveFileRef(val id: String, val modifiedTime: String?)

/**
 * The Drive REST v3 surface the backup needs, restricted to the hidden
 * appDataFolder space. Bearer tokens come from [DriveAuthClient]; HTTP
 * failures surface as typed [DriveBackupException]s so the service can map
 * them to user-facing outcomes (401 → silent re-auth, everything else → error).
 */
interface DriveAppDataApi {
    /** Backup files matching [fileName], newest first. */
    suspend fun findBackupFiles(accessToken: String, fileName: String): List<DriveFileRef>
    suspend fun createFile(accessToken: String, fileName: String, content: ByteArray): String
    suspend fun updateFile(accessToken: String, fileId: String, content: ByteArray)
    suspend fun downloadFile(accessToken: String, fileId: String): ByteArray
    suspend fun deleteFile(accessToken: String, fileId: String)
    suspend fun accountEmail(accessToken: String): String?
}

class GoogleDriveAppDataApi(
    private val client: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .build(),
) : DriveAppDataApi {
    private val json = Json { ignoreUnknownKeys = true }

    override suspend fun findBackupFiles(accessToken: String, fileName: String): List<DriveFileRef> {
        val url = apiUrl("drive/v3/files")
            .addQueryParameter("spaces", "appDataFolder")
            .addQueryParameter("q", "name = '$fileName'")
            .addQueryParameter("fields", "files(id,modifiedTime)")
            .addQueryParameter("orderBy", "modifiedTime desc")
            .build()
        val body = execute(get(url, accessToken)).use { it.body?.string().orEmpty() }
        return json.parseToJsonElement(body).jsonObject["files"]?.jsonArray.orEmpty().mapNotNull { element ->
            val fields = element.jsonObject
            val id = fields["id"]?.jsonPrimitive?.contentOrNull ?: return@mapNotNull null
            DriveFileRef(id = id, modifiedTime = fields["modifiedTime"]?.jsonPrimitive?.contentOrNull)
        }
    }

    override suspend fun createFile(accessToken: String, fileName: String, content: ByteArray): String {
        val metadata = """{"name":"$fileName","parents":["appDataFolder"],"mimeType":"application/json"}"""
        val multipart = MultipartBody.Builder()
            .setType("multipart/related".toMediaType())
            .addPart(metadata.toRequestBody("application/json; charset=UTF-8".toMediaType()))
            .addPart(content.toRequestBody("application/json".toMediaType()))
            .build()
        val url = apiUrl("upload/drive/v3/files")
            .addQueryParameter("uploadType", "multipart")
            .addQueryParameter("fields", "id")
            .build()
        val request = Request.Builder().url(url).bearer(accessToken).post(multipart).build()
        val body = execute(request).use { it.body?.string().orEmpty() }
        return json.parseToJsonElement(body).jsonObject["id"]?.jsonPrimitive?.contentOrNull
            ?: throw DriveBackupException.Http(code = 200)
    }

    override suspend fun updateFile(accessToken: String, fileId: String, content: ByteArray) {
        val url = apiUrl("upload/drive/v3/files/$fileId")
            .addQueryParameter("uploadType", "media")
            .build()
        val request = Request.Builder()
            .url(url)
            .bearer(accessToken)
            .patch(content.toRequestBody("application/json".toMediaType()))
            .build()
        execute(request).close()
    }

    override suspend fun downloadFile(accessToken: String, fileId: String): ByteArray {
        val url = apiUrl("drive/v3/files/$fileId")
            .addQueryParameter("alt", "media")
            .build()
        return execute(get(url, accessToken)).use { it.body?.bytes() ?: ByteArray(0) }
    }

    override suspend fun deleteFile(accessToken: String, fileId: String) {
        val url = apiUrl("drive/v3/files/$fileId").build()
        val request = Request.Builder().url(url).bearer(accessToken).delete().build()
        // 404 = already gone; deletion is idempotent from the caller's view.
        execute(request, allowNotFound = true).close()
    }

    override suspend fun accountEmail(accessToken: String): String? {
        val url = apiUrl("drive/v3/about")
            .addQueryParameter("fields", "user(emailAddress)")
            .build()
        val body = execute(get(url, accessToken)).use { it.body?.string().orEmpty() }
        return runCatching {
            json.parseToJsonElement(body).jsonObject["user"]
                ?.jsonObject?.get("emailAddress")?.jsonPrimitive?.contentOrNull
        }.getOrNull()
    }

    private fun apiUrl(path: String): HttpUrl.Builder = HttpUrl.Builder()
        .scheme("https")
        .host("www.googleapis.com")
        .addPathSegments(path)

    private fun get(url: HttpUrl, accessToken: String): Request =
        Request.Builder().url(url).bearer(accessToken).get().build()

    private fun Request.Builder.bearer(accessToken: String): Request.Builder =
        header("Authorization", "Bearer $accessToken")

    private suspend fun execute(request: Request, allowNotFound: Boolean = false): Response =
        withContext(Dispatchers.IO) {
            val response = try {
                client.newCall(request).execute()
            } catch (e: IOException) {
                throw DriveBackupException.Network(e)
            }
            if (!response.isSuccessful && !(allowNotFound && response.code == 404)) {
                val code = response.code
                response.close()
                throw DriveBackupException.Http(code)
            }
            response
        }
}
