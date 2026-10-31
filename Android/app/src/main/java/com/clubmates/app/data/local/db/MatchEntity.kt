package com.clubmates.app.data.local.db

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(
    tableName = "matches",
    indices = [Index(value = ["lastMessageAtMs"])]
)
data class MatchEntity(
    @PrimaryKey val id: String,
    val venueId: String?,
    val lastMessage: String,
    val lastMessageAt: String,      // raw string preserved for formatRelativeTime()
    val lastMessageAtMs: Long,      // epoch millis for ORDER BY DESC and cursor
    val unreadCount: Int,
    val isNew: Boolean,
    val profileJson: String         // UserProfile serialized as JSON — avoids join tables
)
