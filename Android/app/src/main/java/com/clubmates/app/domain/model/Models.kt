package com.clubmates.app.domain.model

import java.util.UUID
import kotlinx.serialization.Serializable
import kotlinx.serialization.Transient

@Serializable
data class NotificationPreferences(
    val enabled: Boolean = true,
    val newMatch: Boolean = true,
    val newMessage: Boolean = true,
    val likedYou: Boolean = true,
    val superLike: Boolean = true,
    val venueActivity: Boolean = true
)

@Serializable
data class DatePreferences(
    val ageMin: Int = 18,
    val ageMax: Int = 60,
    val genders: List<String> = emptyList(),
    val heightMin: Int = 140,
    val heightMax: Int = 220,
    val verifiedOnly: Boolean = false
)

@Serializable
data class UserProfile(
    val id: String,
    val name: String,
    val age: Int,
    val bio: String,
    val profession: String = "Student",
    val gender: String = "Male",
    val height: Int = 170,
    val interests: List<String>,
    val prompts: List<Prompt>,
    val photos: List<ProfilePhoto>,
    val isVerified: Boolean,
    val distance: Double = 0.0,
    val hasSuperLikedMe: Boolean = false,
    val lookingFor: String = "",
    val preferences: DatePreferences = DatePreferences(),
    val notificationPreferences: NotificationPreferences = NotificationPreferences(),
    val isGhostMode: Boolean = false,
    val verificationStatus: String = "unverified",  // "unverified"|"pending"|"verified"|"failed"
    val verificationMismatchedPhotoIds: List<String> = emptyList()
) {
    @Serializable
    data class Prompt(
        val id: String = UUID.randomUUID().toString(),
        val question: String,
        val answer: String
    )
}

@Serializable
data class ProfilePhoto(
    val id: String = UUID.randomUUID().toString(),
    val cdnUrl: String? = null,
    @Transient val localUri: android.net.Uri? = null,
    val position: Int = 0
)

data class Venue(
    val id: String,
    val name: String,
    val neighborhood: String,
    val city: String = "",
    val vibe: String,
    val music: String,
    val symbolName: String,
    val gradientHex: List<String>,
    val occupancy: Int = 0,
    val latitude: Double? = null,
    val longitude: Double? = null,
    val checkinRadiusMeters: Int = 200
)

data class Match(
    val id: String,
    val profile: UserProfile,
    val venueId: String?,
    val lastMessage: String,
    val lastMessageAt: String,
    val unreadCount: Int,
    val isNew: Boolean
)

data class ChatMessage(
    val id: String = UUID.randomUUID().toString(),
    val matchId: String,
    val body: String,
    val isFromMe: Boolean,
    val senderId: String,
    val isRead: Boolean,
    val createdAt: String,
    val tempId: String? = null
)

enum class SwipeDirection { LIKE, NOPE, SUPERLIKE }
