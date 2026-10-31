package com.clubmates.app.data.local.db

import androidx.room.*
import kotlinx.coroutines.flow.Flow

@Dao
interface MessageDao {

    @Query("SELECT * FROM messages WHERE matchId = :matchId ORDER BY createdAtMs ASC")
    fun observeMessages(matchId: String): Flow<List<MessageEntity>>

    @Query("SELECT * FROM messages WHERE matchId = :matchId ORDER BY createdAtMs ASC")
    suspend fun getMessages(matchId: String): List<MessageEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertMessages(messages: List<MessageEntity>)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertMessage(message: MessageEntity)

    @Query("UPDATE messages SET isRead = 1 WHERE matchId = :matchId AND createdAtMs <= :upToMs")
    suspend fun markReadUpTo(matchId: String, upToMs: Long)

    // Delta sync cursor — highest timestamp stored for this thread
    @Query("SELECT MAX(createdAtMs) FROM messages WHERE matchId = :matchId")
    suspend fun getLatestTimestamp(matchId: String): Long?

    // Full sync cleanup — remove messages server no longer returns
    @Query("DELETE FROM messages WHERE matchId = :matchId AND id NOT IN (:ids)")
    suspend fun deleteNotInIds(matchId: String, ids: List<String>)

    // Bulk read receipt across multiple threads (e.g. after foreground resume)
    @Query("UPDATE messages SET isRead = 1 WHERE matchId IN (:matchIds) AND isFromMe = 0")
    suspend fun bulkMarkRead(matchIds: List<String>)

    // Used by reconcileSentMessage — check if a sent message arrived within a time window
    @Query("""
        SELECT * FROM messages
        WHERE matchId = :matchId AND isFromMe = 1 AND body = :body AND createdAtMs >= :sinceMs
        LIMIT 1
    """)
    suspend fun findSentMessage(matchId: String, body: String, sinceMs: Long): MessageEntity?

    @Query("DELETE FROM messages WHERE matchId = :matchId")
    suspend fun deleteByMatch(matchId: String)

    @Query("DELETE FROM messages")
    suspend fun deleteAll()
}
