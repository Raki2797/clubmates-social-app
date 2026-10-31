package com.clubmates.app.ui.matches

import android.app.Application
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.clubmates.app.data.network.ApiService
import com.clubmates.app.data.network.WebSocketClient
import com.clubmates.app.data.network.WsEvent
import com.clubmates.app.data.network.WsSend
import com.clubmates.app.data.repository.MatchesRepository
import com.clubmates.app.data.local.SafetyVisibilityStore
import com.clubmates.app.data.repository.SafetyRepository
import com.clubmates.app.domain.model.ChatMessage
import com.clubmates.app.domain.model.Match
import com.clubmates.app.domain.model.UserProfile
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.util.UUID
import javax.inject.Inject

data class IncomingLikeBanner(
    val id: String = UUID.randomUUID().toString(),
    val profileId: String,
    val name: String,
    val isSuperLike: Boolean,
    val isMatch: Boolean = false,
    val matchId: String? = null,
    val photoUrl: String? = null
)

data class MatchesUiState(
    val matches: List<Match> = emptyList(),
    val isLoading: Boolean = false,
    val error: String? = null,
    val safetyError: String? = null,
    val isSubmittingSafetyAction: Boolean = false,
    val incomingLikeBanner: IncomingLikeBanner? = null,
    val selectedIncomingLikeProfile: UserProfile? = null
)

data class ChatUiState(
    val match: Match? = null,
    val messages: List<ChatMessage> = emptyList(),
    val isTyping: Boolean = false,
    val isLoading: Boolean = false,
    val messageError: String? = null
)

@HiltViewModel
class MatchesViewModel @Inject constructor(
    application: Application,
    private val matchesRepository: MatchesRepository,
    private val safetyRepository: SafetyRepository,
    private val wsClient: WebSocketClient,
    private val apiService: ApiService
) : AndroidViewModel(application) {

    companion object {
        const val ACTION_SIGN_OUT = "com.clubmates.app.ACTION_SIGN_OUT"
    }

    private val _matchesState = MutableStateFlow(MatchesUiState())
    val matchesState: StateFlow<MatchesUiState> = _matchesState.asStateFlow()

    private val _chatState = MutableStateFlow(ChatUiState())
    val chatState: StateFlow<ChatUiState> = _chatState.asStateFlow()

    private val _onlineUserIds = MutableStateFlow<Set<String>>(emptySet())
    val onlineUserIds: StateFlow<Set<String>> = _onlineUserIds.asStateFlow()

    // Optimistic messages — in memory only, never persisted to DB (tempId != null)
    private val optimisticMessages = mutableListOf<ChatMessage>()
    private var messageObserveJob: Job? = null

    private var bannerDismissJob: Job? = null
    private val pendingSwipeCardsByUserId = mutableMapOf<String, Match>()
    private val announcedIncomingLikeUserIds = mutableSetOf<String>()
    private val announcedMatchUserIds = mutableSetOf<String>()
    private val pendingTreatInvitesByUserId = mutableMapOf<String, com.clubmates.app.data.network.ApiTreatInvite>()

    val totalUnread: Int get() = _matchesState.value.matches.sumOf { it.unreadCount }

    private val signOutReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            handleSessionSignOut()
        }
    }

    // Internet reconnect → delta sync (catches missed messages while offline)
    private val connectivityManager =
        application.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

    private val networkCallback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
            viewModelScope.launch { matchesRepository.refreshMatches() }
            wsClient.connect()
        }
    }

    init {
        wsClient.connect()
        // Seed UI from DB immediately — no spinner on app open
        viewModelScope.launch {
            matchesRepository.observeMatches().collect { dbMatches ->
                _matchesState.update { state ->
                    state.copy(matches = mergeWithPendingSwipeCards(dbMatches), isLoading = false)
                }
            }
        }
        loadMatches(forceFullSync = true)  // full sync on sign-in — cleans up stale local matches
        loadIncomingSwipes()
        loadIncomingTreatInvites()
        observeWsEvents()
        application.registerReceiver(signOutReceiver, IntentFilter(ACTION_SIGN_OUT), Context.RECEIVER_NOT_EXPORTED)
        connectivityManager.registerNetworkCallback(
            NetworkRequest.Builder()
                .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                .build(),
            networkCallback
        )
    }

    override fun onCleared() {
        super.onCleared()
        getApplication<Application>().unregisterReceiver(signOutReceiver)
        runCatching { connectivityManager.unregisterNetworkCallback(networkCallback) }
    }

    fun isUserOnline(userId: String): Boolean = _onlineUserIds.value.contains(userId)

    fun isPendingIncomingLike(match: Match): Boolean =
        pendingSwipeCardsByUserId.containsKey(match.profile.id) || pendingTreatInvitesByUserId.containsKey(match.profile.id)

    private fun handleSessionSignOut() {
        _onlineUserIds.update { emptySet() }
        pendingSwipeCardsByUserId.clear()
        announcedIncomingLikeUserIds.clear()
        announcedMatchUserIds.clear()
        pendingTreatInvitesByUserId.clear()
        bannerDismissJob?.cancel()
        optimisticMessages.clear()
        messageObserveJob?.cancel()
        _matchesState.update { it.copy(incomingLikeBanner = null, selectedIncomingLikeProfile = null) }
        wsClient.disconnect()
        viewModelScope.launch { matchesRepository.clearAll() }
    }

    fun loadMatches(forceFullSync: Boolean = false) {
        viewModelScope.launch {
            _matchesState.update { it.copy(isLoading = true) }
            runCatching { matchesRepository.refreshMatches(forceFullSync) }
                .onSuccess { fresh ->
                    // Remove pending swipe cards that became real matches
                    val freshProfileIds = fresh.map { it.profile.id }.toSet()
                    pendingSwipeCardsByUserId.keys.retainAll { it !in freshProfileIds }
                    announcedIncomingLikeUserIds.retainAll { it in pendingSwipeCardsByUserId.keys }
                    // DB Flow (observeMatches) will re-emit automatically — no manual state update needed
                    _matchesState.update { it.copy(isLoading = false) }
                }
                .onFailure { e -> _matchesState.update { it.copy(isLoading = false, error = e.message) } }
        }
    }

    fun openChat(match: Match) {
        optimisticMessages.clear()
        _chatState.update { it.copy(match = match, messages = emptyList(), isLoading = true) }

        // Observe DB for this thread — emits instantly if messages are cached
        messageObserveJob?.cancel()
        messageObserveJob = viewModelScope.launch {
            matchesRepository.observeMessages(match.id).collect { dbMessages ->
                val merged = mergeWithOptimistic(dbMessages)
                _chatState.update { it.copy(messages = merged, isLoading = false) }
            }
        }

        // Background network refresh — writes to DB, Flow re-emits silently
        viewModelScope.launch {
            runCatching { matchesRepository.refreshMessages(match.id) }
            runCatching { matchesRepository.markRead(match.id) }
            _matchesState.update { state ->
                state.copy(matches = state.matches.map { m ->
                    if (m.id == match.id) m.copy(unreadCount = 0, isNew = false) else m
                })
            }
        }
    }

    fun closeChat() {
        messageObserveJob?.cancel()
        messageObserveJob = null
        optimisticMessages.clear()
        _chatState.update { ChatUiState() }
    }

    fun sendMessage(body: String) {
        val match = _chatState.value.match ?: return
        val trimmed = body.trim()
        if (trimmed.isEmpty()) return

        val tempId = UUID.randomUUID().toString()
        val optimistic = ChatMessage(
            id = tempId, matchId = match.id, body = trimmed,
            isFromMe = true, senderId = "", isRead = false,
            createdAt = System.currentTimeMillis().toString(), tempId = tempId
        )
        optimisticMessages.add(optimistic)
        _chatState.update { it.copy(messages = mergeWithOptimistic(_chatState.value.messages.filter { m -> m.tempId == null })) }
        updateLastMessage(match.id, trimmed)

        viewModelScope.launch {
            runCatching { matchesRepository.sendMessage(match.id, trimmed) }
                .onSuccess { sent ->
                    // Confirmed message persisted to DB by repository
                    // DB Flow re-emits, mergeWithOptimistic removes the optimistic bubble
                    optimisticMessages.removeAll { it.tempId == tempId }
                    updateLastMessage(match.id, trimmed)
                }
                .onFailure { e ->
                    reconcileSentMessage(match.id, tempId, trimmed, e.message)
                }
        }
    }

    fun sendTypingStart() {
        val matchId = _chatState.value.match?.id ?: return
        wsClient.send(WsSend(type = "typing.start", matchId = matchId))
    }

    fun sendTypingStop() {
        val matchId = _chatState.value.match?.id ?: return
        wsClient.send(WsSend(type = "typing.stop", matchId = matchId))
    }

    fun unmatch(matchId: String) {
        // Optimistic removal — disappears from UI immediately (mirrors iOS)
        _matchesState.update { state ->
            state.copy(matches = state.matches.filter { it.id != matchId })
        }
        if (_chatState.value.match?.id == matchId) closeChat()

        viewModelScope.launch {
            runCatching { matchesRepository.unmatch(matchId) }
            // Refresh from server whether it succeeded or failed — keeps list consistent
            loadMatches()
        }
    }

    fun addMatch(match: Match) {
        viewModelScope.launch {
            // Upsert to DB — observeMatches Flow will re-emit
            matchesRepository.refreshMatches()
        }
        // Optimistic in-memory update while refresh is in flight
        _matchesState.update { state ->
            if (state.matches.any { it.id == match.id }) state
            else state.copy(matches = (listOf(match) + state.matches).sortedByLastMessage())
        }
    }

    fun block(match: Match, onDone: () -> Unit) {
        if (_matchesState.value.isSubmittingSafetyAction) return
        viewModelScope.launch {
            _matchesState.update { it.copy(isSubmittingSafetyAction = true) }
            runCatching { safetyRepository.block(match.profile.id) }
                .onSuccess {
                    _matchesState.update { state ->
                        state.copy(
                            matches = state.matches.filter { it.id != match.id },
                            isSubmittingSafetyAction = false,
                            safetyError = null
                        )
                    }
                    if (_chatState.value.match?.id == match.id) closeChat()
                    onDone()
                }
                .onFailure { e ->
                    _matchesState.update { it.copy(isSubmittingSafetyAction = false, safetyError = e.message) }
                }
        }
    }

    fun reportSpam(match: Match, reason: String, onDone: () -> Unit) {
        if (_matchesState.value.isSubmittingSafetyAction) return
        viewModelScope.launch {
            _matchesState.update { it.copy(isSubmittingSafetyAction = true) }
            runCatching {
                safetyRepository.report(
                    reportedUserId = match.profile.id,
                    matchId = match.id,
                    category = "spam",
                    reason = reason,
                    details = "Reported from chat."
                )
            }
                .onSuccess {
                    _matchesState.update { state ->
                        state.copy(
                            matches = state.matches.filter { it.id != match.id },
                            isSubmittingSafetyAction = false,
                            safetyError = null
                        )
                    }
                    if (_chatState.value.match?.id == match.id) closeChat()
                    onDone()
                }
                .onFailure { e ->
                    _matchesState.update { it.copy(isSubmittingSafetyAction = false, safetyError = e.message) }
                }
        }
    }

    fun clearSafetyError() = _matchesState.update { it.copy(safetyError = null) }

    fun clearError() = _matchesState.update { it.copy(error = null) }

    fun dismissIncomingLikeProfile() = _matchesState.update { it.copy(selectedIncomingLikeProfile = null) }

    fun dismissIncomingLikeBanner() {
        bannerDismissJob?.cancel()
        _matchesState.update { it.copy(incomingLikeBanner = null) }
    }

    fun handleNewMatchTap(match: Match) {
        if (!_matchesState.value.matches.any { it.id == match.id }) return

        if (pendingSwipeCardsByUserId.containsKey(match.profile.id)) {
            viewModelScope.launch {
                val profile = runCatching { apiService.getUserProfile(match.profile.id).user.toDomain() }
                    .getOrDefault(match.profile)
                _matchesState.update { it.copy(selectedIncomingLikeProfile = profile) }
            }
            return
        }

        openChat(match)
    }

    private fun loadIncomingSwipes() {
        viewModelScope.launch {
            runCatching { apiService.incomingSwipes() }
                .onSuccess { response ->
                    val latestByUserId = response.swipes.associateBy { it.profile.id }
                    val toRemove = pendingSwipeCardsByUserId.keys - latestByUserId.keys.toSet()
                    toRemove.forEach { pendingSwipeCardsByUserId.remove(it) }
                    latestByUserId.values.forEach { swipe ->
                        upsertSwipeNotification(
                            profile = swipe.profile.toDomain(),
                            direction = swipe.direction,
                            isMatch = false,
                            matchId = null,
                            venueId = swipe.venueId
                        )
                    }
                }
        }
    }

    private fun upsertSwipeNotification(
        profile: UserProfile,
        direction: String,
        isMatch: Boolean,
        matchId: String?,
        venueId: String?
    ) {
        val existingMatchId = _matchesState.value.matches.firstOrNull { it.profile.id == profile.id }?.id
        val resolvedMatchId = matchId ?: existingMatchId ?: UUID.randomUUID().toString()

        val previewText = when {
            isMatch -> "It's a match!"
            direction == "superlike" -> "Super liked you"
            else -> "Liked you"
        }

        if (isMatch) {
            pendingSwipeCardsByUserId.remove(profile.id)
            announcedIncomingLikeUserIds.remove(profile.id)
        }

        _matchesState.update { state ->
            val existing = state.matches.firstOrNull { it.id == resolvedMatchId }
                ?: state.matches.firstOrNull { it.profile.id == profile.id }

            val seededMatch = Match(
                id = resolvedMatchId,
                profile = profile,
                venueId = venueId,
                lastMessage = previewText,
                lastMessageAt = System.currentTimeMillis().toString(),
                unreadCount = existing?.unreadCount ?: 0,
                isNew = existing?.isNew ?: true
            )

            if (isMatch) {
                val withoutOld = state.matches.filter { it.id != resolvedMatchId && it.profile.id != profile.id }
                return@update state.copy(matches = (listOf(seededMatch) + withoutOld).sortedByLastMessage())
            }

            if (!announcedIncomingLikeUserIds.contains(profile.id)) {
                showIncomingLikeBanner(profile.id, profile.name, direction == "superlike")
                announcedIncomingLikeUserIds.add(profile.id)
            }

            pendingSwipeCardsByUserId[profile.id] = seededMatch
            val withoutOld = state.matches.filter { it.profile.id != profile.id }
            state.copy(matches = mergeWithPendingSwipeCards(withoutOld))
        }
    }

    private fun mergeWithPendingSwipeCards(serverMatches: List<Match>): List<Match> {
        val serverProfileIds = serverMatches.map { it.profile.id }.toSet()
        val pendingCards = pendingSwipeCardsByUserId.values
            .filter { it.profile.id !in serverProfileIds }
            .filter { !SafetyVisibilityStore.isHidden(it.profile.id) }
        return (serverMatches + pendingCards).sortedByLastMessage()
    }

    private fun mergeWithOptimistic(dbMessages: List<ChatMessage>): List<ChatMessage> {
        val dbIds = dbMessages.map { it.id }.toSet()
        val pending = optimisticMessages.filter { it.id !in dbIds }
        return (dbMessages + pending).sortedBy {
            it.createdAt.toLongOrNull()
                ?: runCatching { java.time.Instant.parse(it.createdAt).toEpochMilli() }.getOrDefault(0L)
        }
    }

    private fun showIncomingLikeBanner(
        profileId: String,
        name: String,
        isSuperLike: Boolean,
        isMatch: Boolean = false,
        matchId: String? = null,
        photoUrl: String? = null
    ) {
        bannerDismissJob?.cancel()
        _matchesState.update {
            it.copy(incomingLikeBanner = IncomingLikeBanner(
                profileId = profileId,
                name = name,
                isSuperLike = isSuperLike,
                isMatch = isMatch,
                matchId = matchId,
                photoUrl = photoUrl
            ))
        }
        bannerDismissJob = viewModelScope.launch {
            delay(3_000L)
            _matchesState.update { it.copy(incomingLikeBanner = null) }
        }
    }

    fun isPendingTreatInvite(match: Match): Boolean = pendingTreatInvitesByUserId.containsKey(match.profile.id)

    /**
     * Clear pending invite + swipe cards for a specific invite/match pair.
     * Mirrors iOS clearPendingInviteState() — called when invite.accepted WS event fires
     * so the pending card disappears instantly without waiting for the next poll.
     */
    private fun clearPendingInviteState(inviteId: String?, matchId: String?) {
        // Find the profile associated with this invite
        val profileId = if (inviteId != null) {
            pendingTreatInvitesByUserId.entries.firstOrNull { it.value.id == inviteId }?.key
        } else {
            // No specific inviteId — clear all pending invites that became matches
            null
        }

        if (profileId != null) {
            pendingTreatInvitesByUserId.remove(profileId)
            pendingSwipeCardsByUserId.remove(profileId)
            // Remove the pending match card, keeping the real match if matchId differs
            _matchesState.update { state ->
                state.copy(matches = state.matches.filter { match ->
                    !(match.profile.id == profileId && match.id != matchId)
                })
            }
            // Close profile sheet if open for this person
            if (_matchesState.value.selectedIncomingLikeProfile?.id == profileId) {
                _matchesState.update { it.copy(selectedIncomingLikeProfile = null) }
            }
        }
    }

    fun pendingTreatInvite(match: Match): com.clubmates.app.data.network.ApiTreatInvite? =
        pendingTreatInvitesByUserId[match.profile.id]

    fun reviewIncomingLike(match: Match, accept: Boolean) {
        if (!isPendingIncomingLike(match)) return
        val venueId = match.venueId ?: run { loadIncomingSwipes(); return }

        // Optimistically remove from pending
        pendingSwipeCardsByUserId.remove(match.profile.id)
        announcedIncomingLikeUserIds.remove(match.profile.id)
        _matchesState.update { state ->
            state.copy(
                matches = state.matches.filter { it.id != match.id },
                selectedIncomingLikeProfile = null
            )
        }

        viewModelScope.launch {
            runCatching {
                val response = apiService.swipe(
                    com.clubmates.app.data.network.SwipeRequest(
                        targetUserId = match.profile.id,
                        venueId = venueId,
                        direction = if (accept) "like" else "nope"
                    )
                )
                if (accept && response.isMatch) {
                    val promotedMatch = Match(
                        id = response.matchId ?: match.id,
                        profile = match.profile,
                        venueId = venueId,
                        lastMessage = "It's a match!",
                        lastMessageAt = System.currentTimeMillis().toString(),
                        unreadCount = 0,
                        isNew = true
                    )
                    _matchesState.update { state ->
                        val without = state.matches.filter { it.profile.id != match.profile.id }
                        state.copy(matches = (listOf(promotedMatch) + without).sortedByLastMessage())
                    }
                    if (!announcedMatchUserIds.contains(match.profile.id)) {
                        announcedMatchUserIds.add(match.profile.id)
                        showIncomingLikeBanner(
                            profileId = match.profile.id,
                            name = match.profile.name,
                            isSuperLike = false,
                            isMatch = true,
                            matchId = response.matchId ?: match.id,
                            photoUrl = match.profile.photos.firstOrNull()?.cdnUrl
                        )
                    }
                }
            }.onFailure { loadIncomingSwipes() }
        }
    }

    fun reviewTreatInvite(match: Match, accept: Boolean) {
        val invite = pendingTreatInvitesByUserId[match.profile.id] ?: return
        pendingTreatInvitesByUserId.remove(match.profile.id)
        _matchesState.update { state ->
            state.copy(
                matches = state.matches.filter { it.id != match.id },
                selectedIncomingLikeProfile = null
            )
        }
        viewModelScope.launch {
            runCatching {
                if (accept) {
                    val response = apiService.acceptTreatInvite(invite.id)
                    val promotedMatch = Match(
                        id = response.matchId,
                        profile = match.profile,
                        venueId = invite.venueId,
                        lastMessage = "It's a match!",
                        lastMessageAt = System.currentTimeMillis().toString(),
                        unreadCount = 0,
                        isNew = true
                    )
                    _matchesState.update { state ->
                        state.copy(matches = (listOf(promotedMatch) + state.matches).sortedByLastMessage())
                    }
                    loadMatches()
                } else {
                    apiService.declineTreatInvite(invite.id)
                }
            }.onFailure { loadIncomingTreatInvites() }
        }
    }

    private fun loadIncomingTreatInvites() {
        viewModelScope.launch {
            runCatching { apiService.incomingTreatInvites() }
                .onSuccess { response ->
                    val latestByUserId = response.invites
                        .filter { it.profile != null }
                        .associateBy { it.profile!!.id }

                    // Drop invites no longer in server list
                    val toRemove = pendingTreatInvitesByUserId.keys - latestByUserId.keys.toSet()
                    toRemove.forEach { pendingTreatInvitesByUserId.remove(it) }

                    latestByUserId.values.forEach { invite ->
                        pendingTreatInvitesByUserId[invite.profile!!.id] = invite
                        upsertTreatInvite(invite)
                    }
                }
        }
    }

    private fun upsertTreatInvite(invite: com.clubmates.app.data.network.ApiTreatInvite) {
        val apiProfile = invite.profile ?: return
        val profile = apiProfile.toDomain()
        val treat = invite.treat ?: return
        val seededMatch = Match(
            id = invite.id,
            profile = profile,
            venueId = invite.venueId,
            lastMessage = "${treat.emoji} ${profile.name} wants to ${treat.notificationNoun}",
            lastMessageAt = invite.createdAt.ifBlank { System.currentTimeMillis().toString() },
            unreadCount = 0,
            isNew = true
        )
        _matchesState.update { state ->
            val withoutOld = state.matches.filter { it.profile.id != profile.id && it.id != invite.id }
            state.copy(matches = mergeWithPendingSwipeCards(withoutOld + seededMatch))
        }
    }

    fun clearMessageError() = _chatState.update { it.copy(messageError = null) }

    private fun reconcileSentMessage(matchId: String, tempId: String, body: String, errorMessage: String? = null) {
        viewModelScope.launch {
            runCatching { matchesRepository.refreshMessages(matchId) }
                .onSuccess { freshMessages ->
                    val nowMs = System.currentTimeMillis()
                    val arrived = freshMessages.find { msg ->
                        msg.isFromMe && msg.body == body && runCatching {
                            nowMs - msg.createdAt.toLong() < 10_000L
                        }.getOrDefault(true)
                    }
                    // If message arrived: it's in DB, DB Flow re-emits, optimistic removed
                    // If not arrived: remove the optimistic bubble
                    if (arrived == null) {
                        optimisticMessages.removeAll { it.tempId == tempId }
                        _chatState.update { it.copy(
                            messages = mergeWithOptimistic(it.messages.filter { m -> m.tempId == null }),
                            messageError = errorMessage ?: "Message not sent. Please try again."
                        )}
                    } else {
                        optimisticMessages.removeAll { it.tempId == tempId }
                    }
                }
                .onFailure {
                    optimisticMessages.removeAll { it.tempId == tempId }
                    _chatState.update { it.copy(
                        messages = mergeWithOptimistic(it.messages.filter { m -> m.tempId == null }),
                        messageError = errorMessage ?: "Message not sent. Please try again."
                    )}
                }
        }
    }

    private fun updateLastMessage(matchId: String, text: String) {
        _matchesState.update { state ->
            state.copy(
                matches = state.matches.map { m ->
                    if (m.id == matchId) m.copy(lastMessage = text, lastMessageAt = System.currentTimeMillis().toString()) else m
                }.sortedByLastMessage()
            )
        }
    }

    private fun observeWsEvents() {
        viewModelScope.launch {
            wsClient.events.collect { event ->
                when (event) {
                    is WsEvent.MessageNew -> {
                        val msg = event.message.toDomain()
                        // Persist to DB — observeMessages Flow re-emits for open chat
                        matchesRepository.persistMessage(msg)
                        if (_chatState.value.match?.id == event.matchId) {
                            runCatching { matchesRepository.markRead(event.matchId, msg.id) }
                        } else {
                            incrementUnread(event.matchId)
                        }
                        updateLastMessage(event.matchId, msg.body)
                    }
                    is WsEvent.MessageAck -> {
                        val matchId = _chatState.value.match?.id ?: return@collect
                        val optimistic = optimisticMessages.firstOrNull { it.tempId == event.tempId } ?: return@collect
                        val confirmed = optimistic.copy(id = event.serverId, createdAt = event.createdAt, tempId = null)
                        matchesRepository.persistMessage(confirmed)  // DB Flow re-emits
                        optimisticMessages.removeAll { it.tempId == event.tempId }
                    }
                    is WsEvent.TypingStart -> {
                        if (_chatState.value.match?.id == event.matchId) {
                            _chatState.update { it.copy(isTyping = true) }
                        }
                    }
                    is WsEvent.TypingStop -> {
                        if (_chatState.value.match?.id == event.matchId) {
                            _chatState.update { it.copy(isTyping = false) }
                        }
                    }
                    is WsEvent.MatchCreated -> addMatch(event.match.toDomain())
                    is WsEvent.PresenceSnapshot -> _onlineUserIds.update { event.userIds.toSet() }
                    is WsEvent.PresenceUpdate -> _onlineUserIds.update { current ->
                        if (event.online) current + event.userId else current - event.userId
                    }
                    is WsEvent.MatchUnmatched -> {
                        _matchesState.update { state ->
                            state.copy(matches = state.matches.filter { it.id != event.matchId })
                        }
                        if (_chatState.value.match?.id == event.matchId) closeChat()
                    }
                    is WsEvent.SafetyHiddenUsersUpdated -> syncHiddenUsersAndRefreshMatches()
                    is WsEvent.InviteReceived -> {
                        val profileId = event.invite.profile?.id ?: return@collect
                        pendingTreatInvitesByUserId[profileId] = event.invite
                        upsertTreatInvite(event.invite)
                    }
                    is WsEvent.InviteAccepted -> {
                        // Clear pending invite card instantly, then refresh matches
                        clearPendingInviteState(inviteId = event.inviteId, matchId = event.matchId)
                        loadMatches()
                    }
                    is WsEvent.SwipeReceived -> {
                        val profile = event.profile.toDomain()
                        upsertSwipeNotification(
                            profile = profile,
                            direction = event.direction,
                            isMatch = event.isMatch,
                            matchId = event.matchId,
                            venueId = event.venueId
                        )
                    }
                    is WsEvent.Ready -> {
                        // connection.ready — run one-time REST reconciliation per guide
                        // This recovers missed events while disconnected
                        viewModelScope.launch {
                            matchesRepository.refreshMatches()
                            loadIncomingSwipes()
                            loadIncomingTreatInvites()
                        }
                        _chatState.value.match?.let { match ->
                            viewModelScope.launch { matchesRepository.refreshMessages(match.id) }
                        }
                    }
                    is WsEvent.Connected -> Unit // handled by Ready now
                    is WsEvent.SwipeWithdrawn -> {
                        // Remove pending like card for this user
                        val userId = event.userId.lowercase()
                        pendingSwipeCardsByUserId.remove(userId)
                        announcedIncomingLikeUserIds.remove(userId)
                        _matchesState.update { state ->
                            state.copy(
                                matches = state.matches.filter { it.profile.id.lowercase() != userId || !it.isNew },
                                incomingLikeBanner = if (state.incomingLikeBanner?.profileId?.lowercase() == userId) null
                                                    else state.incomingLikeBanner
                            )
                        }
                    }
                    is WsEvent.VerificationUpdated -> Unit  // handled by ProfileViewModel
                    else -> Unit
                }
            }
        }
    }

    fun syncHiddenUsersAndRefreshMatches() {
        viewModelScope.launch {
            runCatching { safetyRepository.syncHiddenUsers() }
            val hidden = SafetyVisibilityStore.hiddenIds()
            _matchesState.update { state ->
                state.copy(matches = state.matches.filter { it.profile.id !in hidden })
            }
            if (_chatState.value.match?.let { it.profile.id in hidden } == true) closeChat()
            loadMatches()
        }
    }

    private fun incrementUnread(matchId: String) {
        _matchesState.update { state ->
            state.copy(matches = state.matches.map { m ->
                if (m.id == matchId) m.copy(unreadCount = m.unreadCount + 1) else m
            })
        }
    }

    private fun List<Match>.sortedByLastMessage(): List<Match> =
        sortedByDescending { it.lastMessageAt.toLongOrNull() ?: 0L }
}
