package com.clubmates.app.data.repository

import com.clubmates.app.data.local.SafetyVisibilityStore
import com.clubmates.app.data.network.ApiService
import com.clubmates.app.data.network.BlockRequest
import com.clubmates.app.data.network.ReportRequest
import com.clubmates.app.data.network.SOSRequest
import com.clubmates.app.data.network.SOSResponse
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class SafetyRepository @Inject constructor(private val api: ApiService) {

    suspend fun block(blockedUserId: String) {
        api.block(BlockRequest(blockedUserId))
        SafetyVisibilityStore.hide(blockedUserId)
    }

    suspend fun report(
        reportedUserId: String,
        matchId: String? = null,
        category: String,
        reason: String,
        details: String? = null
    ) {
        api.report(ReportRequest(reportedUserId, matchId, category, reason, details))
        SafetyVisibilityStore.hide(reportedUserId)
    }

    suspend fun syncHiddenUsers() {
        runCatching { api.hiddenUsers() }
            .onSuccess { SafetyVisibilityStore.hide(it.userIds) }
    }

    suspend fun triggerSOS(
        source: String,
        venueId: String? = null,
        matchId: String? = null,
        latitude: Double? = null,
        longitude: Double? = null,
        accuracyMeters: Double? = null,
        message: String? = null
    ): SOSResponse = api.triggerSOS(
        SOSRequest(venueId, matchId, latitude, longitude, accuracyMeters, source, message)
    )
}
