package com.clubmates.app.data.repository

import com.clubmates.app.BuildConfig
import com.clubmates.app.data.network.ApiService
import com.clubmates.app.data.network.CheckInRequest
import com.clubmates.app.domain.model.UserProfile
import com.clubmates.app.domain.model.Venue
import javax.inject.Inject
import javax.inject.Singleton

private val mockVenues = listOf(
    Venue(id = "v1", name = "Harbour Social", neighborhood = "Bandra", vibe = "Upscale Lounge", music = "Deep House", symbolName = "wineglass", gradientHex = listOf("#1a1a2e", "#16213e"), occupancy = 42),
    Venue(id = "v2", name = "The Tilt", neighborhood = "Lower Parel", vibe = "Craft Beer Bar", music = "Indie Rock", symbolName = "mug", gradientHex = listOf("#2d1b69", "#11998e"), occupancy = 28),
    Venue(id = "v3", name = "Aer Rooftop", neighborhood = "Worli", vibe = "Rooftop Party", music = "Commercial EDM", symbolName = "star", gradientHex = listOf("#f7971e", "#ffd200"), occupancy = 75),
    Venue(id = "v4", name = "Kala Ghoda Café", neighborhood = "Fort", vibe = "Chill & Artsy", music = "Jazz & Lo-fi", symbolName = "cup.and.saucer", gradientHex = listOf("#134e5e", "#71b280"), occupancy = 19),
)

@Singleton
class VenueRepository @Inject constructor(private val api: ApiService) {

    suspend fun getVenues(): List<Venue> {
        if (BuildConfig.MOCK_MODE) return mockVenues
        return api.getVenues().venues.map { it.toDomain() }
    }

    suspend fun getRoster(venueId: String): List<UserProfile> {
        if (BuildConfig.MOCK_MODE) return mockDiscoverProfiles
        return api.getRoster(venueId).roster.map { it.toDomain() }
    }

    suspend fun checkIn(venueId: String, latitude: Double, longitude: Double) {
        if (BuildConfig.MOCK_MODE) return
        api.checkIn(venueId, CheckInRequest(latitude, longitude))
    }

    suspend fun checkOut(venueId: String) {
        if (BuildConfig.MOCK_MODE) return
        api.checkOut(venueId)
    }
}
