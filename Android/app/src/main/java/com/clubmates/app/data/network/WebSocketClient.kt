package com.clubmates.app.data.network

import android.util.Log
import com.clubmates.app.data.local.TokenStore
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.serialization.json.Json
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.math.min

sealed class WsEvent {
    data class MessageNew(val matchId: String, val message: ApiMessage) : WsEvent()
    data class MessageAck(val tempId: String, val serverId: String, val createdAt: String) : WsEvent()
    data class MessageRead(val matchId: String, val upToMessageId: String) : WsEvent()
    data class TypingStart(val matchId: String, val userId: String) : WsEvent()
    data class TypingStop(val matchId: String, val userId: String) : WsEvent()
    data class MatchCreated(val match: ApiMatch) : WsEvent()
    data class PresenceJoin(val venueId: String, val userId: String, val name: String?, val photoUrl: String?) : WsEvent()
    data class PresenceLeave(val venueId: String, val userId: String) : WsEvent()
    data class PresenceSnapshot(val userIds: List<String>) : WsEvent()
    data class PresenceUpdate(val userId: String, val online: Boolean) : WsEvent()
    data class MatchUnmatched(val matchId: String) : WsEvent()
    data class InviteReceived(val invite: ApiTreatInvite) : WsEvent()
    data class InviteAccepted(val inviteId: String? = null, val matchId: String? = null) : WsEvent()
    data class SwipeReceived(
        val profile: ApiUserProfile,
        val direction: String,
        val isMatch: Boolean,
        val matchId: String?,
        val venueId: String?
    ) : WsEvent()
    data class SwipeWithdrawn(val userId: String, val venueId: String?) : WsEvent()
    data class VenuePresenceChanged(val venueId: String, val userId: String, val status: String) : WsEvent()
    data class VerificationUpdated(
        val verificationStatus: String,
        val mismatchedPhotoIds: List<String> = emptyList()
    ) : WsEvent()
    object SafetyHiddenUsersUpdated : WsEvent()
    object Ready : WsEvent()   // connection.ready — use this instead of Connected for reconciliation
    object Connected : WsEvent()
    object Disconnected : WsEvent()
}

@Singleton
class WebSocketClient @Inject constructor(
    private val okHttpClient: OkHttpClient,
    private val tokenStore: TokenStore,
    private val baseUrl: String
) {
    private val _events = MutableSharedFlow<WsEvent>(extraBufferCapacity = 64)
    val events: SharedFlow<WsEvent> = _events

    private var webSocket: WebSocket? = null
    private var reconnectJob: Job? = null
    private var handshakeTimeoutJob: Job? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var retryDelayMs = 1_000L

    private val json = Json { ignoreUnknownKeys = true }

    fun connect() {
        if (webSocket != null) return
        val token = tokenStore.accessToken ?: return
        // Never log the WS URL — it contains the JWT token
        val wsUrl = baseUrl.replace("https", "wss").replace("http", "ws") + "/v1/ws?token=$token"
        val request = Request.Builder().url(wsUrl).build()
        webSocket = okHttpClient.newWebSocket(request, listener)
        // 10-second handshake timeout — if connection.ready not received, reconnect
        handshakeTimeoutJob?.cancel()
        handshakeTimeoutJob = scope.launch {
            delay(10_000L)
            Log.w("WS", "Handshake timeout — reconnecting")
            webSocket?.cancel()
            webSocket = null
            scheduleReconnect()
        }
    }

    fun disconnect() {
        reconnectJob?.cancel()
        handshakeTimeoutJob?.cancel()
        webSocket?.close(1000, "User disconnected")
        webSocket = null
        retryDelayMs = 1_000L
    }

    fun send(envelope: WsSend) {
        val text = json.encodeToString(WsSend.serializer(), envelope)
        webSocket?.send(text)
    }

    private val listener = object : WebSocketListener() {
        override fun onOpen(ws: WebSocket, response: Response) {
            retryDelayMs = 1_000L
            scope.launch { _events.emit(WsEvent.Connected) }
        }

        override fun onMessage(ws: WebSocket, text: String) {
            scope.launch { handleMessage(text) }
        }

        override fun onFailure(ws: WebSocket, t: Throwable, response: Response?) {
            Log.w("WS", "WebSocket failure: ${t.message}")
            webSocket = null
            scope.launch { _events.emit(WsEvent.Disconnected) }
            scheduleReconnect()
        }

        override fun onClosed(ws: WebSocket, code: Int, reason: String) {
            webSocket = null
            scope.launch { _events.emit(WsEvent.Disconnected) }
            if (code != 1000) scheduleReconnect()
        }
    }

    private fun scheduleReconnect() {
        reconnectJob?.cancel()
        reconnectJob = scope.launch {
            delay(retryDelayMs)
            retryDelayMs = min(retryDelayMs * 2, 60_000L)
            connect()
        }
    }

    private suspend fun handleMessage(text: String) {
        val type = runCatching {
            json.decodeFromString(WsEnvelope.serializer(), text).type
        }.getOrNull() ?: return

        val event: WsEvent = when (type) {
            "connection.ready" -> {
                // Cancel handshake timeout — socket is authenticated and ready
                handshakeTimeoutJob?.cancel()
                retryDelayMs = 1_000L  // reset backoff on successful connection
                WsEvent.Ready
            }
            "message.new", "message.created" -> {
                val msg = json.decodeFromString(WsMessageNew.serializer(), text)
                // "message.created" puts matchId inside message.matchId
                // "message.new" puts it at top level — fall back to message.matchId
                val matchId = msg.matchId ?: msg.message.matchId
                WsEvent.MessageNew(matchId, msg.message)
            }
            "message.ack" -> {
                val ack = json.decodeFromString(WsMessageAck.serializer(), text)
                WsEvent.MessageAck(ack.tempId, ack.serverId, ack.createdAt)
            }
            "message.read" -> {
                val parsed = json.parseToJsonElement(text)
                val matchId = parsed.toString() // parse properly below
                val envelope = json.decodeFromString(kotlinx.serialization.json.JsonObject.serializer(), text)
                WsEvent.MessageRead(
                    envelope["matchId"].toString().trim('"'),
                    envelope["upToMessageId"].toString().trim('"')
                )
            }
            "typing.start" -> {
                val t = json.decodeFromString(WsTyping.serializer(), text)
                WsEvent.TypingStart(t.matchId, t.userId)
            }
            "typing.stop" -> {
                val t = json.decodeFromString(WsTyping.serializer(), text)
                WsEvent.TypingStop(t.matchId, t.userId)
            }
            "match.created" -> {
                val m = json.decodeFromString(WsMatchCreated.serializer(), text)
                WsEvent.MatchCreated(m.match)
            }
            "presence.join" -> {
                val p = json.decodeFromString(WsPresence.serializer(), text)
                WsEvent.PresenceJoin(p.venueId, p.userId, p.name, p.photoUrl)
            }
            "presence.leave" -> {
                val p = json.decodeFromString(WsPresence.serializer(), text)
                WsEvent.PresenceLeave(p.venueId, p.userId)
            }
            "presence.snapshot" -> {
                val p = json.decodeFromString(WsPresenceSnapshot.serializer(), text)
                // Normalize UUIDs to lowercase — JS Map keys are case-sensitive, UUIDs are not
                WsEvent.PresenceSnapshot(p.userIds.map { it.lowercase() })
            }
            "presence.update" -> {
                val p = json.decodeFromString(WsPresenceUpdate.serializer(), text)
                WsEvent.PresenceUpdate(p.userId.lowercase(), p.online)
            }
            "match.unmatched" -> {
                val envelope = json.decodeFromString(kotlinx.serialization.json.JsonObject.serializer(), text)
                val matchId = envelope["matchId"]?.toString()?.trim('"') ?: return
                WsEvent.MatchUnmatched(matchId)
            }
            "safety.hidden_users_updated" -> WsEvent.SafetyHiddenUsersUpdated
            "profile.verification_updated" -> {
                val payload = json.decodeFromString(WsVerificationUpdated.serializer(), text)
                WsEvent.VerificationUpdated(payload.verificationStatus, payload.mismatchedPhotoIds)
            }
            "invite.received" -> {
                val inv = json.decodeFromString(WsInviteReceived.serializer(), text)
                val invite = ApiTreatInvite(
                    id = inv.inviteId,
                    venueId = inv.venueId,
                    treatType = inv.treatType,
                    intent = inv.intent ?: "If we both meet and vibe, I'm open to this treat.",
                    createdAt = inv.createdAt,
                    profile = inv.profile
                )
                WsEvent.InviteReceived(invite)
            }
            "invite.accepted" -> {
                val envelope = json.decodeFromString(kotlinx.serialization.json.JsonObject.serializer(), text)
                val inviteId = envelope["inviteId"]?.toString()?.trim('"')
                val matchId = envelope["matchId"]?.toString()?.trim('"')
                WsEvent.InviteAccepted(inviteId = inviteId, matchId = matchId)
            }
            "swipe.received" -> {
                val s = json.decodeFromString(WsSwipeReceived.serializer(), text)
                WsEvent.SwipeReceived(s.profile, s.direction, s.isMatch, s.matchId, s.venueId)
            }
            "swipe.withdrawn" -> {
                val envelope = json.decodeFromString(kotlinx.serialization.json.JsonObject.serializer(), text)
                val userId = envelope["userId"]?.toString()?.trim('"')?.lowercase() ?: return
                val venueId = envelope["venueId"]?.toString()?.trim('"')
                WsEvent.SwipeWithdrawn(userId, venueId)
            }
            "venue.presence_changed" -> {
                val envelope = json.decodeFromString(kotlinx.serialization.json.JsonObject.serializer(), text)
                val venueId = envelope["venueId"]?.toString()?.trim('"') ?: return
                val userId = envelope["userId"]?.toString()?.trim('"')?.lowercase() ?: return
                val status = envelope["status"]?.toString()?.trim('"') ?: return
                WsEvent.VenuePresenceChanged(venueId, userId, status)
            }
            else -> return
        }
        _events.emit(event)
    }
}
