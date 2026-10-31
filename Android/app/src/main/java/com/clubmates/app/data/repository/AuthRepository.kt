package com.clubmates.app.data.repository

import android.content.ContentResolver
import android.content.Context
import android.util.Log
import com.clubmates.app.BuildConfig
import com.clubmates.app.data.local.TokenStore
import com.clubmates.app.data.local.db.UserProfileDao
import com.clubmates.app.data.local.db.UserProfileEntity
import com.clubmates.app.data.network.*
import com.clubmates.app.domain.model.ProfilePhoto
import com.clubmates.app.domain.model.UserProfile
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.MultipartBody
import okhttp3.RequestBody.Companion.toRequestBody
import javax.inject.Inject
import javax.inject.Singleton

private val profileJson = Json { ignoreUnknownKeys = true; encodeDefaults = true }

@Singleton
class AuthRepository @Inject constructor(
    private val api: ApiService,
    private val tokenStore: TokenStore,
    private val userProfileDao: UserProfileDao,
    @ApplicationContext private val context: Context
) {
    suspend fun sendOtp(phone: String, restore: Boolean = false): SendOtpResponse {
        if (BuildConfig.MOCK_MODE) return SendOtpResponse(ok = true, userExists = false, devCode = "123456")
        Log.d("ClubMates", "sendOtp → phone=$phone restore=$restore baseUrl=${BuildConfig.API_BASE_URL}")
        return try {
            val response = api.sendOtp(SendOtpRequest(phone, if (restore) true else null))
            Log.d("ClubMates", "sendOtp ← ok=${response.ok} userExists=${response.userExists} deletionScheduledAt=${response.deletionScheduledAt}")
            response
        } catch (e: Exception) {
            Log.e("ClubMates", "sendOtp ERROR: ${e::class.simpleName}: ${e.message}")
            throw e
        }
    }

    suspend fun verifyOtp(phone: String, code: String, restore: Boolean = false): AuthResponse {
        if (BuildConfig.MOCK_MODE) {
            tokenStore.accessToken = "mock_access_token"
            tokenStore.refreshToken = "mock_refresh_token"
            tokenStore.userId = "mock_user_1"
            return AuthResponse(
                accessToken = "mock_access_token",
                refreshToken = "mock_refresh_token",
                user = AuthUser(id = "mock_user_1", phone = phone, profileCompleted = false),
                isNewUser = true
            )
        }
        val response = api.verifyOtp(VerifyOtpRequest(phone, code, if (restore) true else null))
        tokenStore.accessToken = response.accessToken
        tokenStore.refreshToken = response.refreshToken
        tokenStore.userId = response.user.id
        return response
    }

    suspend fun getMe(): UserProfile {
        if (BuildConfig.MOCK_MODE) return mockProfile
        val user = api.getMe().user
        user.verificationSelfieUrl?.let { tokenStore.verificationSelfieUrl = it }
        val profile = user.toDomain()
        // Cache profile locally
        val userId = tokenStore.userId ?: return profile
        userProfileDao.upsert(UserProfileEntity(
            userId = userId,
            profileJson = profileJson.encodeToString(profile),
            lastSyncedAt = System.currentTimeMillis(),
            isDirty = false
        ))
        return profile
    }

    /** Load profile from local cache — instant, no network call */
    suspend fun getCachedProfile(): UserProfile? {
        val userId = tokenStore.userId ?: return null
        val entity = userProfileDao.get(userId) ?: return null
        return runCatching { profileJson.decodeFromString<UserProfile>(entity.profileJson) }.getOrNull()
    }

    fun getCachedLastSyncedAt(): Long? {
        return tokenStore.userId?.let { /* synchronous check not needed — use coroutine flow */ null }
    }

    suspend fun uploadVerificationSelfie(jpegBytes: ByteArray) {
        if (BuildConfig.MOCK_MODE) return
        val body = jpegBytes.toRequestBody("image/jpeg".toMediaTypeOrNull())
        val part = MultipartBody.Part.createFormData("selfie", "selfie.jpg", body)
        runCatching { api.uploadVerificationSelfie(part) }
            .onSuccess { response -> response.selfieUrl?.let { tokenStore.verificationSelfieUrl = it } }
    }

    suspend fun reorderPhotos(photoIds: List<String>) {
        if (BuildConfig.MOCK_MODE) return
        api.reorderPhotos(ReorderPhotosRequest(photoIds))
    }

    val verificationSelfieUrl: String? get() = tokenStore.verificationSelfieUrl

    suspend fun updateProfile(profile: UserProfile, previousPhotos: List<ProfilePhoto> = emptyList()): UserProfile {
        if (BuildConfig.MOCK_MODE) return profile
        val request = UpdateProfileRequest(
            name = profile.name,
            age = profile.age,
            bio = profile.bio,
            profession = profile.profession,
            gender = profile.gender,
            height = profile.height,
            interests = profile.interests,
            prompts = profile.prompts.map { ApiPrompt(question = it.question, answer = it.answer) },
            lookingFor = profile.lookingFor.ifBlank { null },
            preferences = profile.preferences.let {
                ApiPreferences(
                    ageMin = it.ageMin, ageMax = it.ageMax,
                    genders = it.genders, heightMin = it.heightMin,
                    heightMax = it.heightMax, verifiedOnly = it.verifiedOnly
                )
            },
            notificationPreferences = profile.notificationPreferences.let {
                ApiNotificationPreferences(
                    enabled = it.enabled, newMatch = it.newMatch,
                    newMessage = it.newMessage, likedYou = it.likedYou,
                    superLike = it.superLike, venueActivity = it.venueActivity
                )
            }
        )
        api.updateMe(request)
        syncProfilePhotos(profile.photos, previousPhotos)
        // Re-fetch to get server truth then update cache
        return getMe()
    }

    private suspend fun syncProfilePhotos(desired: List<ProfilePhoto>, previous: List<ProfilePhoto>) {
        val resolver: ContentResolver = context.contentResolver
        val previousRemoteIds = previous
            .filter { it.cdnUrl != null && it.localUri == null }
            .map { it.id }
            .toSet()

        val uploadedIds = mutableListOf<String>()

        desired.forEachIndexed { index, photo ->
            when {
                photo.localUri != null -> {
                    // New photo from gallery — read bytes and upload
                    val bytes = runCatching {
                        resolver.openInputStream(photo.localUri)?.use { it.readBytes() }
                    }.getOrNull() ?: return@forEachIndexed

                    val mimeType = resolver.getType(photo.localUri) ?: "image/jpeg"
                    val ext = if (mimeType.contains("png")) "png" else if (mimeType.contains("webp")) "webp" else "jpg"
                    val body = bytes.toRequestBody(mimeType.toMediaTypeOrNull())
                    val part = MultipartBody.Part.createFormData("photo", "photo.$ext", body)
                    // Send stable clientPhotoId so retries are idempotent (server uses it as DB row + storage path)
                    val clientPhotoId = photo.id

                    val result = runCatching { api.uploadPhoto(part, index, clientPhotoId) }.getOrNull()
                    val serverId = result?.get("id") ?: result?.get("photoId") ?: clientPhotoId
                    if (serverId != null) uploadedIds.add(serverId)
                }
                photo.cdnUrl != null -> {
                    // Existing remote photo — keep its id for reorder
                    uploadedIds.add(photo.id)
                }
            }
        }

        // Delete photos that were in previous but not in desired
        val desiredRemoteIds = desired
            .filter { it.cdnUrl != null && it.localUri == null }
            .map { it.id }
            .toSet()
        val removedIds = previousRemoteIds - desiredRemoteIds
        removedIds.forEach { id ->
            runCatching { api.deletePhoto(id) }
        }

        // Reorder if we have ids
        if (uploadedIds.isNotEmpty()) {
            runCatching { api.reorderPhotos(ReorderPhotosRequest(uploadedIds)) }
        }
    }

    /** Partial update — only sends the fields provided, leaves everything else unchanged on server */
    suspend fun patchProfile(request: PatchProfileRequest): UserProfile {
        if (BuildConfig.MOCK_MODE) return getMe()
        return api.patchMe(request).user.toDomain()
    }

    suspend fun registerDeviceToken(token: String) {
        if (BuildConfig.MOCK_MODE) return
        api.registerDeviceToken(DeviceTokenRequest(token))
    }

    suspend fun logout() {
        if (BuildConfig.MOCK_MODE) { tokenStore.clear(); return }
        val refreshToken = tokenStore.refreshToken
        if (refreshToken != null) {
            runCatching { api.logout(LogoutRequest(refreshToken)) }
        }
        tokenStore.clear()
    }

    suspend fun deleteAccount() {
        if (BuildConfig.MOCK_MODE) { tokenStore.clear(); return }
        api.deleteAccount()
        tokenStore.clear()
    }

    val isLoggedIn: Boolean get() = tokenStore.hasTokens
    val userId: String? get() = tokenStore.userId
}

val mockProfile = UserProfile(
    id = "mock_user_1",
    name = "Vikram",
    age = 26,
    bio = "Love good music, great venues, and even better people.",
    profession = "Designer",
    gender = "Male",
    height = 180,
    interests = listOf("Music", "Dancing", "Travel", "Coffee", "Photography"),
    prompts = listOf(
        UserProfile.Prompt(question = "My go-to karaoke song", answer = "Bohemian Rhapsody, every time."),
        UserProfile.Prompt(question = "Best way to find me", answer = "At the bar, debating cocktail menus.")
    ),
    photos = listOf(ProfilePhoto(cdnUrl = null, position = 0)),
    isVerified = true
)
