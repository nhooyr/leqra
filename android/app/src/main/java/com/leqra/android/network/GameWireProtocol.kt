package com.leqra.android.network

import org.json.JSONObject

internal object GameWireProtocol {
    const val epoch = 1
    private const val legacyEpoch = 1

    fun check(metadata: JSONObject) {
        val advertised = metadata.opt("protocol") ?: legacyEpoch
        if (advertised != epoch && advertised != epoch.toLong())
            throw NetworkFailure(
                "version_mismatch",
                "This server uses an unsupported game protocol.",
            )
    }
}
