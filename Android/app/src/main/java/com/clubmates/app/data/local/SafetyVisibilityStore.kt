package com.clubmates.app.data.local

import android.content.Context
import android.content.SharedPreferences
import com.clubmates.app.domain.model.UserProfile
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.asSharedFlow

object SafetyVisibilityStore {
    private const val PREFS_NAME = "clubmates.safety"
    private const val KEY = "hidden_user_ids"

    private val _changes = MutableSharedFlow<Unit>(extraBufferCapacity = 1)
    val changes = _changes.asSharedFlow()

    private lateinit var prefs: SharedPreferences

    fun init(context: Context) {
        prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    fun hide(userId: String) {
        val ids = hiddenIds().toMutableSet()
        if (ids.add(userId)) {
            prefs.edit().putStringSet(KEY, ids).apply()
            _changes.tryEmit(Unit)
        }
    }

    fun hide(userIds: List<String>) {
        if (userIds.isEmpty()) return
        val ids = hiddenIds().toMutableSet()
        val added = ids.addAll(userIds)
        if (added) {
            prefs.edit().putStringSet(KEY, ids).apply()
            _changes.tryEmit(Unit)
        }
    }

    fun isHidden(userId: String): Boolean = hiddenIds().contains(userId)

    fun hiddenIds(): Set<String> = prefs.getStringSet(KEY, emptySet()) ?: emptySet()

    fun replace(with: List<String>) {
        prefs.edit().putStringSet(KEY, with.toSet()).apply()
        _changes.tryEmit(Unit)
    }

    fun visibleProfiles(profiles: List<UserProfile>): List<UserProfile> {
        val ids = hiddenIds()
        return profiles.filter { !ids.contains(it.id) }
    }
}
