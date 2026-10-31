package com.clubmates.app.data.local.db

import com.clubmates.app.domain.model.ChatMessage
import com.clubmates.app.domain.model.Match
import com.clubmates.app.domain.model.UserProfile
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.time.Instant

fun ChatMessage.toEntity(): MessageEntity {
    val ms = runCatching { Instant.parse(createdAt).toEpochMilli() }
        .getOrElse { createdAt.toLongOrNull() ?: System.currentTimeMillis() }
    return MessageEntity(
        id = id,
        matchId = matchId,
        body = body,
        isFromMe = isFromMe,
        senderId = senderId,
        isRead = isRead,
        createdAt = createdAt,
        createdAtMs = ms
    )
}

fun MessageEntity.toDomain(): ChatMessage = ChatMessage(
    id = id,
    matchId = matchId,
    body = body,
    isFromMe = isFromMe,
    senderId = senderId,
    isRead = isRead,
    createdAt = createdAt,
    tempId = null       // tempId is never persisted
)

fun Match.toEntity(json: Json): MatchEntity {
    val ms = runCatching { Instant.parse(lastMessageAt).toEpochMilli() }
        .getOrElse { lastMessageAt.toLongOrNull() ?: 0L }
    return MatchEntity(
        id = id,
        venueId = venueId,
        lastMessage = lastMessage,
        lastMessageAt = lastMessageAt,
        lastMessageAtMs = ms,
        unreadCount = unreadCount,
        isNew = isNew,
        profileJson = json.encodeToString(profile)
    )
}

fun MatchEntity.toDomain(json: Json): Match = Match(
    id = id,
    profile = json.decodeFromString(profileJson),
    venueId = venueId,
    lastMessage = lastMessage,
    lastMessageAt = lastMessageAt,
    unreadCount = unreadCount,
    isNew = isNew
)
