package com.clubmates.app.data.local.db

import androidx.room.TypeConverter
import com.clubmates.app.domain.model.UserProfile
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

// Standalone Json instance for DB serialization only.
// Uses ignoreUnknownKeys so old DB rows survive model additions without migration.
private val dbJson = Json { ignoreUnknownKeys = true; encodeDefaults = true }

object Converters {

    @TypeConverter
    @JvmStatic
    fun profileToJson(profile: UserProfile): String = dbJson.encodeToString(profile)

    @TypeConverter
    @JvmStatic
    fun jsonToProfile(raw: String): UserProfile = dbJson.decodeFromString(raw)
}
