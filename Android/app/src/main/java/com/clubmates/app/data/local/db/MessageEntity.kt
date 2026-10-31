package com.clubmates.app.data.local.db

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(
    tableName = "messages",
    indices = [
        Index(value = ["matchId"]),
        Index(value = ["matchId", "createdAtMs"])
    ]
)
data class MessageEntity(
    @PrimaryKey val id: String,
    val matchId: String,
    val body: String,
    val isFromMe: Boolean,
    val senderId: String,
    val isRead: Boolean,
    val createdAt: String,      // raw ISO-8601 string from server, preserved for display
    val createdAtMs: Long       // epoch millis derived on insert, used for ORDER BY and cursor
)
