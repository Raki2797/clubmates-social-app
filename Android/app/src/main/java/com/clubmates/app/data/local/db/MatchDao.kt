package com.clubmates.app.data.local.db

import androidx.room.*
import kotlinx.coroutines.flow.Flow

@Dao
interface MatchDao {

    @Query("SELECT * FROM matches ORDER BY lastMessageAtMs DESC")
    fun observeMatches(): Flow<List<MatchEntity>>

    @Query("SELECT * FROM matches ORDER BY lastMessageAtMs DESC")
    suspend fun getMatches(): List<MatchEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertMatches(matches: List<MatchEntity>)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertMatch(match: MatchEntity)

    @Query("UPDATE matches SET unreadCount = 0, isNew = 0 WHERE id = :matchId")
    suspend fun markRead(matchId: String)

    @Query("UPDATE matches SET lastMessage = :text, lastMessageAtMs = :atMs, lastMessageAt = :atStr WHERE id = :matchId")
    suspend fun updateLastMessage(matchId: String, text: String, atMs: Long, atStr: String)

    @Query("UPDATE matches SET unreadCount = unreadCount + 1 WHERE id = :matchId")
    suspend fun incrementUnread(matchId: String)

    // Delta sync cursor — highest lastMessageAtMs stored
    @Query("SELECT MAX(lastMessageAtMs) FROM matches")
    suspend fun getLatestTimestamp(): Long?

    // Full sync — return all stored match IDs to detect server-deleted matches
    @Query("SELECT id FROM matches")
    suspend fun getMatchIds(): List<String>

    // Full sync cleanup — remove matches server no longer returns
    @Query("DELETE FROM matches WHERE id NOT IN (:ids)")
    suspend fun deleteNotInIds(ids: List<String>)

    @Query("DELETE FROM matches WHERE id = :matchId")
    suspend fun deleteMatch(matchId: String)

    @Query("DELETE FROM matches")
    suspend fun deleteAll()
}
