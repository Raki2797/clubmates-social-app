package com.clubmates.app.data.network

import com.clubmates.app.domain.model.*
import com.clubmates.app.domain.model.DatePreferences
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.Contextual
import java.util.Date

// ── Auth ────────────────────────────────────────────────────────────────────

@Serializable
data class SendOtpRequest(val phone: String, val restore: Boolean? = null)

@Serializable
data class SendOtpResponse(
    val ok: Boolean,
    val userExists: Boolean? = null,
    val devCode: String? = null,
    val deletionScheduledAt: String? = null  // non-null = account pending deletion, show restore UI
)

@Serializable
data class VerifyOtpRequest(val phone: String, val code: String, val restore: Boolean? = null)

@Serializable
data class AuthUser(val id: String, val phone: String, val profileCompleted: Boolean)

@Serializable
data class AuthResponse(
    val accessToken: String,
    val refreshToken: String,
    val user: AuthUser,
    val isNewUser: Boolean? = null
)

@Serializable
data class RefreshRequest(val refreshToken: String)

@Serializable
data class LogoutRequest(val refreshToken: String)

// ── Profile ──────────────────────────────────────────────────────────────────

@Serializable
data class ApiNotificationPreferences(
    val enabled: Boolean = true,
    val newMatch: Boolean = true,
    val newMessage: Boolean = true,
    val likedYou: Boolean = true,
    val superLike: Boolean = true,
    val venueActivity: Boolean = true
)

@Serializable
data class ApiPreferences(
    val ageMin: Int = 18,
    val ageMax: Int = 60,
    val genders: List<String> = emptyList(),
    val heightMin: Int = 140,
    val heightMax: Int = 220,
    val verifiedOnly: Boolean = false
)

@Serializable
data class ApiPrompt(
    val id: String? = null,
    val question: String,
    val answer: String
)

@Serializable
data class ApiPhoto(
    val id: String,
    val storageKey: String = "",
    val cdnUrl: String? = null,
    val position: Int = 0
)

@Serializable
data class ApiUserProfile(
    val id: String,
    val phone: String? = null,
    val name: String,
    val age: Int,
    val bio: String,
    val profession: String = "Student",
    val gender: String = "Male",
    val height: Int = 170,
    val interests: List<String> = emptyList(),
    val isVerified: Boolean = false,
    val profileCompleted: Boolean? = null,
    val verificationSelfieUrl: String? = null,
    val prompts: List<ApiPrompt>? = null,
    val photos: List<ApiPhoto>? = null,
    val photoUrl: String? = null,
    val distance: Double? = null,
    val hasSuperLikedMe: Boolean? = null,
    val lookingFor: String? = null,
    val preferences: ApiPreferences? = null,
    val notificationPreferences: ApiNotificationPreferences? = null,
    val isGhostMode: Boolean? = null,
    val verificationStatus: String? = null,
    val verificationMismatchedPhotoIds: List<String>? = null
) {
    fun toDomain() = UserProfile(
        id = id,
        name = name.ifBlank { "New ClubMate" },
        age = age,
        bio = bio,
        profession = profession,
        gender = gender,
        height = height,
        interests = interests,
        prompts = prompts?.map { UserProfile.Prompt(id = it.id ?: "", question = it.question, answer = it.answer) } ?: emptyList(),
        photos = run {
            val fromArray = photos
                ?.sortedBy { it.position }
                ?.filter { it.cdnUrl != null }
                ?.map { ProfilePhoto(id = it.id, cdnUrl = it.cdnUrl, position = it.position) }
                ?.takeIf { it.isNotEmpty() }
            fromArray ?: (if (photoUrl != null) listOf(ProfilePhoto(cdnUrl = photoUrl, position = 0)) else emptyList())
        },
        isVerified = isVerified,
        verificationStatus = verificationStatus ?: (if (isVerified) "verified" else "unverified"),
        verificationMismatchedPhotoIds = verificationMismatchedPhotoIds ?: emptyList(),
        distance = distance ?: 0.0,
        hasSuperLikedMe = hasSuperLikedMe ?: false,
        isGhostMode = isGhostMode ?: false,
        lookingFor = lookingFor ?: "",
        notificationPreferences = notificationPreferences?.let {
            NotificationPreferences(
                enabled = it.enabled, newMatch = it.newMatch,
                newMessage = it.newMessage, likedYou = it.likedYou,
                superLike = it.superLike, venueActivity = it.venueActivity
            )
        } ?: NotificationPreferences(),
        preferences = preferences?.let {
            DatePreferences(
                ageMin = it.ageMin, ageMax = it.ageMax,
                genders = it.genders, heightMin = it.heightMin,
                heightMax = it.heightMax, verifiedOnly = it.verifiedOnly
            )
        } ?: DatePreferences()
    )
}

@Serializable
data class UserResponse(val user: ApiUserProfile)

/** Partial update — only include fields you want to change. null = not sent. */
@Serializable
data class PatchProfileRequest(
    val name: String? = null,
    val age: Int? = null,
    val bio: String? = null,
    val profession: String? = null,
    val gender: String? = null,
    val height: Int? = null,
    val interests: List<String>? = null,
    val prompts: List<ApiPrompt>? = null,
    val lookingFor: String? = null,
    val preferences: ApiPreferences? = null,
    val notificationPreferences: ApiNotificationPreferences? = null,
    val isGhostMode: Boolean? = null
)

@Serializable
data class UpdateProfileRequest(
    val name: String,
    val age: Int,
    val bio: String,
    val profession: String,
    val gender: String,
    val height: Int,
    val interests: List<String>,
    val prompts: List<ApiPrompt>,
    val lookingFor: String? = null,
    val preferences: ApiPreferences? = null,
    val notificationPreferences: ApiNotificationPreferences? = null
)

@Serializable
data class DeviceTokenRequest(val token: String)

@Serializable
data class VerificationSelfieResponse(val ok: Boolean, val selfieUrl: String? = null)

@Serializable
data class ReorderPhotosRequest(val order: List<String>)

// ── Venues ───────────────────────────────────────────────────────────────────

@Serializable
data class ApiVenue(
    val id: String,
    val name: String,
    val neighborhood: String,
    val city: String = "",
    val vibe: String = "",
    val music: String = "",
    val symbolName: String = "",
    val gradientHex: List<String> = emptyList(),
    val occupancy: Int = 0,
    val latitude: Double? = null,
    val longitude: Double? = null,
    val checkinRadiusMeters: Int? = null
) {
    fun toDomain() = Venue(
        id = id, name = name, neighborhood = neighborhood,
        city = city, vibe = vibe, music = music, symbolName = symbolName,
        gradientHex = gradientHex, occupancy = occupancy,
        latitude = latitude, longitude = longitude,
        checkinRadiusMeters = checkinRadiusMeters ?: 200
    )
}

@Serializable
data class VenuesResponse(val venues: List<ApiVenue>)

@Serializable
data class RosterResponse(val roster: List<ApiUserProfile>)

@Serializable
data class CheckInRequest(val latitude: Double, val longitude: Double)

// ── Discovery ────────────────────────────────────────────────────────────────

@Serializable
data class DiscoverResponse(val profiles: List<ApiUserProfile>)

// ── Treat Invites ─────────────────────────────────────────────────────────────

enum class TreatType(val value: String, val emoji: String, val title: String, val notificationNoun: String) {
    DRINK("drink", "🥂", "Drink", "buy a drink"),
    DESSERT("dessert", "🍰", "Dessert", "buy dessert"),
    COFFEE("coffee", "☕", "Coffee", "buy a coffee"),
    STARTER("starter", "🍟", "Starter", "buy a starter"),
    DECIDE_TOGETHER("decide_together", "🤝", "Decide together", "decide on a treat together");

    companion object {
        fun fromValue(value: String) = entries.firstOrNull { it.value == value }
    }
}

@Serializable
data class ApiTreatInvite(
    val id: String,
    val venueId: String? = null,
    val treatType: String,
    val intent: String = "If we both meet and vibe, I'm open to this treat.",
    val createdAt: String = "",
    val profile: ApiUserProfile? = null
) {
    val treat: TreatType? get() = TreatType.fromValue(treatType)
}

@Serializable
data class IncomingTreatInvitesResponse(val invites: List<ApiTreatInvite>)

@Serializable
data class AcceptTreatInviteResponse(val matchId: String)

@Serializable
data class SendTreatInviteRequest(val targetUserId: String, val venueId: String, val treatType: String)

@Serializable
data class SendTreatInviteResponse(
    val invite: ApiTreatInvite? = null,
    val isMatch: Boolean = false,
    val matchId: String? = null,
    val status: String? = null
)

@Serializable
data class IncomingSwipe(
    val profile: ApiUserProfile,
    val direction: String,
    val createdAt: String = "",
    val venueId: String? = null
)

@Serializable
data class IncomingSwipesResponse(val swipes: List<IncomingSwipe>)

@Serializable
data class SwipeRequest(
    val targetUserId: String,
    val venueId: String,
    val direction: String
)

@Serializable
data class SwipeResponse(val isMatch: Boolean, val matchId: String? = null)

// ── Matches & Chat ───────────────────────────────────────────────────────────

@Serializable
data class ApiMatch(
    val id: String,
    val venueId: String? = null,
    val profile: ApiUserProfile,
    val lastMessage: String = "",
    val lastMessageAt: String = "",
    val unreadCount: Int = 0,
    val isNew: Boolean = false,
    val updatedAt: String? = null,  // ISO-8601, used as delta sync cursor
    val deletedAt: String? = null   // non-null = soft-deleted, remove from local DB
) {
    fun toDomain() = Match(
        id = id, profile = profile.toDomain(), venueId = venueId,
        lastMessage = lastMessage, lastMessageAt = lastMessageAt,
        unreadCount = unreadCount, isNew = isNew
    )
}

@Serializable
data class MatchesResponse(
    val matches: List<ApiMatch>,
    val total: Int = 0,
    val page: Int = 1,
    val limit: Int = 0
)

@Serializable
data class ApiMessage(
    val id: String,
    val matchId: String,
    val body: String,
    val isFromMe: Boolean,
    val senderId: String,
    val isRead: Boolean,
    val createdAt: String,
    val deletedAt: String? = null   // non-null = soft-deleted, remove from local DB
) {
    fun toDomain() = ChatMessage(
        id = id, matchId = matchId, body = body,
        isFromMe = isFromMe, senderId = senderId,
        isRead = isRead, createdAt = createdAt
    )
}

@Serializable
data class MessagesResponse(
    val messages: List<ApiMessage>,
    val total: Int = 0,
    val page: Int = 1,
    val limit: Int = 50
)

@Serializable
data class MessageResponse(val message: ApiMessage)

@Serializable
data class SendMessageRequest(val body: String)

@Serializable
data class MarkReadRequest(val upToMessageId: String? = null)

// ── Safety ───────────────────────────────────────────────────────────────────

@Serializable
data class BlockRequest(val blockedUserId: String)

@Serializable
data class ReportRequest(
    val reportedUserId: String,
    val matchId: String? = null,
    val category: String,
    val reason: String,
    val details: String? = null
)

@Serializable
data class HiddenUsersResponse(val userIds: List<String>)

@Serializable
data class SOSRequest(
    val venueId: String? = null,
    val matchId: String? = null,
    val latitude: Double? = null,
    val longitude: Double? = null,
    val accuracyMeters: Double? = null,
    val source: String,
    val message: String? = null
)

@Serializable
data class SOSResponse(
    val ok: Boolean,
    val eventId: String? = null,
    val emergencyNumber: String? = null
)

// ── WebSocket ────────────────────────────────────────────────────────────────

@Serializable
data class WsEnvelope(val type: String)

@Serializable
data class WsMessageNew(
    val type: String,
    val matchId: String? = null,  // present in "message.new", absent in "message.created"
    val message: ApiMessage
)

@Serializable
data class WsMessageAck(
    val type: String,
    val tempId: String,
    val serverId: String,
    val createdAt: String
)

@Serializable
data class WsTyping(val type: String, val matchId: String, val userId: String)

@Serializable
data class WsMatchCreated(val type: String, val match: ApiMatch)

@Serializable
data class WsPresence(
    val type: String,
    val venueId: String,
    val userId: String,
    val name: String? = null,
    val photoUrl: String? = null
)

@Serializable
data class WsPresenceSnapshot(
    val type: String,
    val userIds: List<String> = emptyList()
)

@Serializable
data class WsPresenceUpdate(
    val type: String,
    val userId: String,
    val online: Boolean
)

@Serializable
data class WsSend(
    val type: String,
    val matchId: String? = null,
    val tempId: String? = null,
    val body: String? = null,
    val upToMessageId: String? = null,
    val venueId: String? = null
)

// ── Account ──────────────────────────────────────────────────────────────────

@Serializable
data class AccountDeletionResponse(val ok: Boolean, val deletionScheduledAt: String)

// ── Realtime Events ──────────────────────────────────────────────────────────

@Serializable
data class ChatRealtimeEvent(
    val type: String,
    val message: ApiMessage? = null,
    val matchId: String? = null,
    val readerId: String? = null,
    val upToMessageId: String? = null,
    val userId: String? = null,
    val online: Boolean? = null,
    val userIds: List<String>? = null,
    val profile: ApiUserProfile? = null,
    val direction: String? = null,
    val isMatch: Boolean? = null,
    val venueId: String? = null
)

@Serializable
data class WsInviteReceived(
    val type: String,
    val inviteId: String,
    val treatType: String,
    val intent: String? = null,
    val venueId: String? = null,
    val createdAt: String = "",
    val profile: ApiUserProfile? = null,
    val status: String? = null,
    val matchId: String? = null,
    val isMatch: Boolean = false
)

@Serializable
data class WsSwipeReceived(
    val type: String,
    val profile: ApiUserProfile,
    val direction: String,
    val isMatch: Boolean = false,
    val matchId: String? = null,
    val venueId: String? = null
)

@Serializable
data class WsVerificationUpdated(
    val type: String,
    val verificationStatus: String,
    val mismatchedPhotoIds: List<String> = emptyList()
)
