package com.clubmates.app.ui.profile

import android.app.Application
import android.content.Intent
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.clubmates.app.data.network.WebSocketClient
import com.clubmates.app.data.network.WsEvent
import com.clubmates.app.data.repository.AuthRepository
import com.clubmates.app.domain.model.UserProfile
import com.clubmates.app.ui.matches.MatchesViewModel
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import javax.inject.Inject

enum class SyncStatus { SYNCED, SYNCING, FAILED }

data class ProfileUiState(
    val profile: UserProfile? = null,
    val isLoading: Boolean = false,
    val isSaving: Boolean = false,
    val isDeleting: Boolean = false,
    val error: String? = null,
    val saveSuccess: Boolean = false,
    val deleteSuccess: Boolean = false,
    val syncStatus: SyncStatus = SyncStatus.SYNCED,
    val lastSyncedAt: Long = 0L,
    val uploadingPhotoIndex: Int? = null,
    val failedPhotoIndex: Int? = null,
    val verificationMismatchedPhotoIds: List<String> = emptyList()
)

@HiltViewModel
class ProfileViewModel @Inject constructor(
    application: Application,
    private val authRepository: AuthRepository,
    private val wsClient: WebSocketClient
) : AndroidViewModel(application) {

    private val _uiState = MutableStateFlow(ProfileUiState())
    val uiState: StateFlow<ProfileUiState> = _uiState.asStateFlow()

    init {
        loadProfile()
        observeVerificationEvents()
    }

    private fun observeVerificationEvents() {
        viewModelScope.launch {
            wsClient.events.collect { event ->
                if (event is WsEvent.VerificationUpdated) {
                    _uiState.update { state ->
                        state.copy(
                            profile = state.profile?.copy(
                                verificationStatus = event.verificationStatus,
                                isVerified = event.verificationStatus == "verified",
                                verificationMismatchedPhotoIds = event.mismatchedPhotoIds
                            ),
                            verificationMismatchedPhotoIds = event.mismatchedPhotoIds
                        )
                    }
                    // Refresh profile from server to get authoritative state
                    runCatching { authRepository.getMe() }
                        .onSuccess { profile -> _uiState.update { it.copy(profile = profile) } }
                }
            }
        }
    }

    fun loadProfile() {
        viewModelScope.launch {
            val cached = authRepository.getCachedProfile()
            if (cached != null) {
                _uiState.update { it.copy(profile = cached, isLoading = false) }
            } else {
                _uiState.update { it.copy(isLoading = true, error = null) }
            }
            _uiState.update { it.copy(syncStatus = SyncStatus.SYNCING) }
            runCatching { authRepository.getMe() }
                .onSuccess { profile ->
                    _uiState.update { it.copy(
                        profile = profile, isLoading = false,
                        syncStatus = SyncStatus.SYNCED,
                        lastSyncedAt = System.currentTimeMillis(),
                        verificationMismatchedPhotoIds = profile.verificationMismatchedPhotoIds
                    )}
                }
                .onFailure { e ->
                    _uiState.update { it.copy(
                        isLoading = false,
                        syncStatus = SyncStatus.FAILED,
                        error = if (cached == null) e.message else null
                    )}
                }
        }
    }

    fun saveProfile(profile: UserProfile) {
        viewModelScope.launch {
            _uiState.update { it.copy(isSaving = true, error = null, saveSuccess = false) }
            val previousPhotos = _uiState.value.profile?.photos ?: emptyList()
            runCatching { authRepository.updateProfile(profile, previousPhotos) }
                .onSuccess { saved -> _uiState.update { it.copy(profile = saved, isSaving = false, saveSuccess = true) } }
                .onFailure { e -> _uiState.update { it.copy(isSaving = false, error = e.message) } }
        }
    }

    // Set pending immediately after selfie upload — mirrors iOS isProfileVerificationPending = true
    fun markVerificationPending() {
        _uiState.update { state ->
            state.copy(
                profile = state.profile?.copy(verificationStatus = "pending", isVerified = false)
            )
        }
    }

    fun logout() {
        viewModelScope.launch {
            authRepository.logout()
            getApplication<Application>().sendBroadcast(
                Intent(MatchesViewModel.ACTION_SIGN_OUT)
            )
        }
    }

    fun deleteAccount() {
        viewModelScope.launch {
            _uiState.update { it.copy(isDeleting = true, error = null) }
            runCatching { authRepository.deleteAccount() }
                .onSuccess {
                    getApplication<Application>().sendBroadcast(
                        Intent(MatchesViewModel.ACTION_SIGN_OUT)
                    )
                    _uiState.update { it.copy(isDeleting = false, deleteSuccess = true) }
                }
                .onFailure { e -> _uiState.update { it.copy(isDeleting = false, error = e.message) } }
        }
    }

    fun patchProfile(request: com.clubmates.app.data.network.PatchProfileRequest) {
        viewModelScope.launch {
            _uiState.update { it.copy(isSaving = true, error = null) }
            runCatching { authRepository.patchProfile(request) }
                .onSuccess { updated -> _uiState.update { it.copy(profile = updated, isSaving = false, saveSuccess = true) } }
                .onFailure { e -> _uiState.update { it.copy(isSaving = false, error = e.message) } }
        }
    }

    fun reorderPhotos(photoIds: List<String>) {
        viewModelScope.launch {
            runCatching { authRepository.reorderPhotos(photoIds) }
        }
    }

    fun clearError() = _uiState.update { it.copy(error = null) }
    fun clearSaveSuccess() = _uiState.update { it.copy(saveSuccess = false) }
}
