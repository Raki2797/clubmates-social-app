package com.clubmates.app.data.local.db

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "user_profile")
data class UserProfileEntity(
    @PrimaryKey val userId: String,
    val profileJson: String,           // full UserProfile as JSON
    val lastSyncedAt: Long = 0L,       // epoch ms of last successful server sync
    val isDirty: Boolean = false       // true = local changes not yet synced to server
)
