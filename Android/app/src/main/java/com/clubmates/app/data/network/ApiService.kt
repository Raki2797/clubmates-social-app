package com.clubmates.app.data.network

import okhttp3.MultipartBody
import retrofit2.http.*

interface ApiService {

    // Auth
    @POST("auth/otp/send")
    suspend fun sendOtp(@Body request: SendOtpRequest): SendOtpResponse

    @POST("auth/otp/verify")
    suspend fun verifyOtp(@Body request: VerifyOtpRequest): AuthResponse

    @POST("auth/refresh")
    suspend fun refresh(@Body request: RefreshRequest): AuthResponse

    @DELETE("auth/session")
    suspend fun logout(@Body request: LogoutRequest)

    // Profile
    @GET("users/me")
    suspend fun getMe(): UserResponse

    @GET("users/{id}/profile")
    suspend fun getUserProfile(@Path("id") userId: String): UserResponse

    @PUT("users/me")
    suspend fun updateMe(@Body request: UpdateProfileRequest): UserResponse

    @PATCH("users/me")
    suspend fun patchMe(@Body request: PatchProfileRequest): UserResponse

    @Multipart
    @POST("users/me/photos")
    suspend fun uploadPhoto(
        @Part photo: MultipartBody.Part,
        @Query("position") position: Int,
        @Query("clientPhotoId") clientPhotoId: String? = null
    ): Map<String, String>

    @Multipart
    @POST("users/me/verification-selfie")
    suspend fun uploadVerificationSelfie(@Part selfie: MultipartBody.Part): VerificationSelfieResponse

    @DELETE("users/me/photos/{photoId}")
    suspend fun deletePhoto(@Path("photoId") photoId: String)

    @PUT("users/me/photos/order")
    suspend fun reorderPhotos(@Body request: ReorderPhotosRequest)

    @POST("users/me/device-token")
    suspend fun registerDeviceToken(@Body request: DeviceTokenRequest)

    // Venues
    @GET("venues")
    suspend fun getVenues(): VenuesResponse

    @GET("venues/{id}/roster")
    suspend fun getRoster(@Path("id") venueId: String): RosterResponse

    @POST("venues/{id}/checkin")
    suspend fun checkIn(@Path("id") venueId: String, @Body request: CheckInRequest)

    @DELETE("venues/{id}/checkin")
    suspend fun checkOut(@Path("id") venueId: String)

    // Discovery
    @GET("venues/{id}/discover")
    suspend fun discover(@Path("id") venueId: String): DiscoverResponse

    @GET("swipes/incoming")
    suspend fun incomingSwipes(): IncomingSwipesResponse

    // Treat Invites
    @GET("invites/incoming")
    suspend fun incomingTreatInvites(): IncomingTreatInvitesResponse

    @POST("invites")
    suspend fun sendTreatInvite(@Body request: SendTreatInviteRequest): SendTreatInviteResponse

    @POST("invites/{id}/accept")
    suspend fun acceptTreatInvite(@Path("id") inviteId: String): AcceptTreatInviteResponse

    @POST("invites/{id}/decline")
    suspend fun declineTreatInvite(@Path("id") inviteId: String)

    @POST("swipes")
    suspend fun swipe(@Body request: SwipeRequest): SwipeResponse

    @DELETE("swipes/{targetUserId}/{venueId}")
    suspend fun undoSwipe(
        @Path("targetUserId") targetUserId: String,
        @Path("venueId") venueId: String
    )

    // Matches & Chat
    @GET("matches")
    suspend fun getMatches(
        @Query("updatedSince") updatedSince: String? = null,
        @Query("limit") limit: Int? = null,
        @Query("page") page: Int? = null
    ): MatchesResponse

    @GET("matches/{id}/messages")
    suspend fun getMessages(
        @Path("id") matchId: String,
        @Query("since") since: String? = null,
        @Query("before") before: String? = null,
        @Query("limit") limit: Int? = null,
        @Query("page") page: Int? = null
    ): MessagesResponse

    @POST("matches/{id}/messages")
    suspend fun sendMessage(
        @Path("id") matchId: String,
        @Body request: SendMessageRequest
    ): MessageResponse

    @PUT("matches/{id}/messages/read")
    suspend fun markRead(
        @Path("id") matchId: String,
        @Body request: MarkReadRequest
    )

    @DELETE("matches/{id}")
    suspend fun unmatch(@Path("id") matchId: String)

    // Account
    @DELETE("users/me")
    suspend fun deleteAccount(): AccountDeletionResponse

    // Safety
    @POST("blocks")
    suspend fun block(@Body request: BlockRequest)

    @POST("reports")
    suspend fun report(@Body request: ReportRequest)

    @GET("safety/hidden-users")
    suspend fun hiddenUsers(): HiddenUsersResponse

    @POST("safety/sos")
    suspend fun triggerSOS(@Body request: SOSRequest): SOSResponse
}
