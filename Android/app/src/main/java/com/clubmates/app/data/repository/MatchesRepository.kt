package com.clubmates.app.data.repository

import com.clubmates.app.BuildConfig
import com.clubmates.app.data.local.db.MatchDao
import com.clubmates.app.data.local.db.MessageDao
import com.clubmates.app.data.local.db.toEntity
import com.clubmates.app.data.local.db.toDomain
import com.clubmates.app.data.network.ApiService
import com.clubmates.app.data.network.MarkReadRequest
import com.clubmates.app.data.network.SendMessageRequest
import com.clubmates.app.domain.model.ChatMessage
import com.clubmates.app.domain.model.Match
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.serialization.json.Json
import java.time.Instant
import javax.inject.Inject
import javax.inject.Singleton
import java.util.UUID

private val mockMatches = listOf(
    Match(id = "match_1", profile = mockDiscoverProfiles[0], venueId = "v1", lastMessage = "Hey! Great meeting you at Harbour Social 👋", lastMessageAt = "2025-05-20T20:30:00Z", unreadCount = 2, isNew = true),
    Match(id = "match_2", profile = mockDiscoverProfiles[2], venueId = "v2", lastMessage = "We should grab coffee sometime!", lastMessageAt = "2025-05-19T18:00:00Z", unreadCount = 0, isNew = false),
)

private val mockMessages = mapOf(
    "match_1" to listOf(
        ChatMessage(id = "msg_1", matchId = "match_1", body = "Hey! Great meeting you at Harbour Social 👋", isFromMe = false, senderId = "u2", isRead = true, createdAt = "2025-05-20T20:28:00Z"),
        ChatMessage(id = "msg_2", matchId = "match_1", body = "You too! That set was 🔥", isFromMe = true, senderId = "mock_user_1", isRead = true, createdAt = "2025-05-20T20:29:00Z"),
        ChatMessage(id = "msg_3", matchId = "match_1", body = "Are you coming back next weekend?", isFromMe = false, senderId = "u2", isRead = false, createdAt = "2025-05-20T20:30:00Z"),
    ),
    "match_2" to listOf(
        ChatMessage(id = "msg_4", matchId = "match_2", body = "We should grab coffee sometime!", isFromMe = false, senderId = "u4", isRead = true, createdAt = "2025-05-19T18:00:00Z"),
    )
)

@Singleton
class MatchesRepository @Inject constructor(
    private val api: ApiService,
    private val messageDao: MessageDao,
    private val matchDao: MatchDao,
    private val json: Json
) {
    private val localMessages = mockMessages.mapValues { it.value.toMutableList() }.toMutableMap()

    // ── Matches ──────────────────────────────────────────────────────────────────

    /** Observe matches from DB — drives MatchesUiState reactively */
    fun observeMatches(): Flow<List<Match>> =
        matchDao.observeMatches().map { entities -> entities.map { it.toDomain(json) } }

    /**
     * Fetch from network and write through to DB.
     * Phase 2: cursor-based delta sync.
     * - No cursor (empty DB / sign-in) → full sync, replaces all local matches not returned
     * - With cursor → delta sync, upserts changes + removes soft-deleted
     *
     * Pass [forceFullSync] = true to ignore the cursor and run a full sync.
     * Use on sign-in to guarantee stale local matches are cleaned up.
     */
    suspend fun refreshMatches(forceFullSync: Boolean = false): List<Match> {
        if (BuildConfig.MOCK_MODE) return mockMatches

        val cursor = if (forceFullSync) null else matchDao.getLatestTimestamp()
        val updatedSince = cursor?.let { msToIso(it) }
        val isDelta = updatedSince != null

        val response = api.getMatches(updatedSince = updatedSince, limit = 100)
        val fresh = response.matches

        // Remove soft-deleted matches from DB
        fresh.filter { it.deletedAt != null }.forEach { deleted ->
            matchDao.deleteMatch(deleted.id)
            messageDao.deleteByMatch(deleted.id)
        }

        // Upsert active matches
        val active = fresh.filter { it.deletedAt == null }
        matchDao.upsertMatches(active.map { it.toDomain().toEntity(json) })

        // Full sync: remove local matches no longer returned by server
        if (!isDelta) {
            val serverIds = active.map { it.id }.toSet()
            val localIds = matchDao.getMatchIds()
            val stale = localIds.filter { it !in serverIds }
            stale.forEach { id ->
                matchDao.deleteMatch(id)
                messageDao.deleteByMatch(id)
            }
        }

        return active.map { it.toDomain() }
    }

    // ── Messages ─────────────────────────────────────────────────────────────────

    /** Observe messages from DB — drives ChatUiState reactively */
    fun observeMessages(matchId: String): Flow<List<ChatMessage>> =
        messageDao.observeMessages(matchId).map { entities -> entities.map { it.toDomain() } }

    /**
     * Fetch from network and write through to DB.
     * Phase 2: cursor-based delta sync.
     * - No cursor → full sync, fetches latest 50 messages
     * - With cursor → delta sync, fetches only messages newer than cursor
     */
    suspend fun refreshMessages(matchId: String): List<ChatMessage> {
        if (BuildConfig.MOCK_MODE) return localMessages[matchId] ?: emptyList()

        val cursor = messageDao.getLatestTimestamp(matchId)
        val since = cursor?.let { msToIso(it) }

        val response = api.getMessages(matchId, since = since, limit = 50)
        val fresh = response.messages

        // Remove soft-deleted messages from DB
        fresh.filter { it.deletedAt != null }.forEach { deleted ->
            messageDao.deleteByMatch(deleted.id)
        }

        // Upsert active messages
        val active = fresh.filter { it.deletedAt == null }
        if (active.isNotEmpty()) {
            messageDao.upsertMessages(active.map { it.toDomain().toEntity() })
        }

        return active.map { it.toDomain() }
    }

    /**
     * Load older messages for scroll-up history (infinite scroll).
     * Uses ?before= cursor with the oldest createdAtMs in the current thread.
     */
    suspend fun loadOlderMessages(matchId: String): List<ChatMessage> {
        if (BuildConfig.MOCK_MODE) return emptyList()

        val oldest = messageDao.getMessages(matchId).firstOrNull()?.createdAtMs ?: return emptyList()
        val before = msToIso(oldest)

        val response = api.getMessages(matchId, before = before, limit = 20)
        val active = response.messages.filter { it.deletedAt == null }
        if (active.isNotEmpty()) {
            messageDao.upsertMessages(active.map { it.toDomain().toEntity() })
        }
        return active.map { it.toDomain() }
    }

    /** Persist a confirmed (non-optimistic) message to DB */
    suspend fun persistMessage(message: ChatMessage) {
        if (message.tempId != null) return  // never persist optimistic messages
        messageDao.upsertMessage(message.toEntity())
    }

    suspend fun sendMessage(matchId: String, body: String): ChatMessage {
        if (BuildConfig.MOCK_MODE) {
            val msg = ChatMessage(id = UUID.randomUUID().toString(), matchId = matchId, body = body, isFromMe = true, senderId = "mock_user_1", isRead = true, createdAt = System.currentTimeMillis().toString())
            localMessages.getOrPut(matchId) { mutableListOf() }.add(msg)
            return msg
        }
        val sent = api.sendMessage(matchId, SendMessageRequest(body)).message.toDomain()
        persistMessage(sent)
        return sent
    }

    suspend fun markRead(matchId: String, upToMessageId: String? = null) {
        if (BuildConfig.MOCK_MODE) return
        api.markRead(matchId, MarkReadRequest(upToMessageId))
        matchDao.markRead(matchId)
        val upToMs = if (upToMessageId != null) {
            messageDao.getMessages(matchId).firstOrNull { it.id == upToMessageId }?.createdAtMs ?: Long.MAX_VALUE
        } else {
            Long.MAX_VALUE
        }
        messageDao.markReadUpTo(matchId, upToMs)
    }

    suspend fun unmatch(matchId: String) {
        if (BuildConfig.MOCK_MODE) return
        api.unmatch(matchId)
        matchDao.deleteMatch(matchId)
        messageDao.deleteByMatch(matchId)
    }

    /** Called on sign-out — wipes all local chat data */
    suspend fun clearAll() {
        matchDao.deleteAll()
        messageDao.deleteAll()
    }

    // ── Helpers ──────────────────────────────────────────────────────────────────

    private fun msToIso(epochMs: Long): String =
        Instant.ofEpochMilli(epochMs).toString()   // ISO-8601, e.g. "2026-06-04T10:00:00Z"
}
