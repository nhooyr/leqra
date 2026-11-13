package com.leqra.android.network

import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

/** Credentials are bound to an origin, never a path, redirect, or invite URL. */
object ServerAddress {
    fun origin(value: String): String {
        val normalized =
            when {
                value.startsWith("wss://", true) -> "https://" + value.substring(6)
                value.startsWith("ws://", true) -> "http://" + value.substring(5)
                else -> value
            }
        val url =
            normalized.trim().toHttpUrlOrNull()
                ?: throw NetworkFailure("invalid_url", "Enter an HTTP or HTTPS server address.")
        require(url.username.isEmpty() && url.password.isEmpty()) {
            "Server addresses cannot contain credentials."
        }
        return url.newBuilder()
            .encodedPath("/")
            .query(null)
            .fragment(null)
            .build()
            .toString()
            .removeSuffix("/")
    }

    fun endpoint(origin: String, path: String): HttpUrl =
        (origin(origin) + path).toHttpUrlOrNull()
            ?: throw NetworkFailure("invalid_url", "Enter an HTTP or HTTPS server address.")
}

class NetworkFailure(
    val code: String,
    override val message: String,
    val seat: Int? = null,
    val terminal: Boolean = true,
) : Exception(message)
