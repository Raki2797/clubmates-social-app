package com.clubmates.app.data.local.db

import androidx.room.*

@Dao
interface UserProfileDao {

    @Query("SELECT * FROM user_profile WHERE userId = :userId LIMIT 1")
    suspend fun get(userId: String): UserProfileEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(entity: UserProfileEntity)

    @Query("UPDATE user_profile SET isDirty = :dirty WHERE userId = :userId")
    suspend fun setDirty(userId: String, dirty: Boolean)

    @Query("UPDATE user_profile SET lastSyncedAt = :syncedAt, isDirty = 0 WHERE userId = :userId")
    suspend fun markSynced(userId: String, syncedAt: Long)

    @Query("DELETE FROM user_profile WHERE userId = :userId")
    suspend fun delete(userId: String)
}
