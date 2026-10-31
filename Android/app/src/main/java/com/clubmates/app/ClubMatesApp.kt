package com.clubmates.app

import android.app.Application
import com.clubmates.app.data.local.SafetyVisibilityStore
import dagger.hilt.android.HiltAndroidApp

@HiltAndroidApp
class ClubMatesApp : Application() {
    override fun onCreate() {
        super.onCreate()
        SafetyVisibilityStore.init(this)
    }
}
