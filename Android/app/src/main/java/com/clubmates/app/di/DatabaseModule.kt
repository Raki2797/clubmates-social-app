package com.clubmates.app.di

import android.content.Context
import androidx.room.Room
import com.clubmates.app.data.local.db.AppDatabase
import com.clubmates.app.data.local.db.MatchDao
import com.clubmates.app.data.local.db.MessageDao
import com.clubmates.app.data.local.db.UserProfileDao
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object DatabaseModule {

    @Provides
    @Singleton
    fun provideDatabase(
        @ApplicationContext context: Context
    ): AppDatabase = Room.databaseBuilder(
        context,
        AppDatabase::class.java,
        "clubmates.db"
    )
        .fallbackToDestructiveMigration()   // safe for v1 — no prior DB to migrate from
        .build()

    @Provides
    @Singleton
    fun provideMessageDao(db: AppDatabase): MessageDao = db.messageDao()

    @Provides
    @Singleton
    fun provideMatchDao(db: AppDatabase): MatchDao = db.matchDao()

    @Provides
    @Singleton
    fun provideUserProfileDao(db: AppDatabase): UserProfileDao = db.userProfileDao()
}
