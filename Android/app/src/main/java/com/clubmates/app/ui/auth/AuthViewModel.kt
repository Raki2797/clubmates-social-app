package com.clubmates.app.ui.auth

import android.app.Application
import android.content.Intent
import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.clubmates.app.data.repository.AuthRepository
import com.clubmates.app.domain.model.UserProfile
import com.clubmates.app.ui.matches.MatchesViewModel
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

enum class OnboardingStep { BASICS, VIBE, PREFERENCES }

data class AuthUiState(
    val isLoading: Boolean = false,
    val error: String? = null,
    val otpSent: Boolean = false,
    val accountExistsForPhone: Boolean = false,
    val isAuthenticated: Boolean = false,
    val needsSelfie: Boolean = false,
    val needsProfile: Boolean = false,
    val currentProfile: UserProfile? = null,
    val onboardingStep: OnboardingStep = OnboardingStep.BASICS,
    // Account restore — non-null means account is pending deletion
    val deletionScheduledAt: String? = null,
    val isRestoreMode: Boolean = false
)

@HiltViewModel
class AuthViewModel @Inject constructor(
    application: Application,
    private val authRepository: AuthRepository
) : AndroidViewModel(application) {

    private val _uiState = MutableStateFlow(AuthUiState())
    val uiState: StateFlow<AuthUiState> = _uiState.asStateFlow()

    /** Synchronous token check — used by NavGraph to pick startDestination without a network call */
    val isLoggedIn: Boolean get() = authRepository.isLoggedIn

    /** Draft profile shared across 3 onboarding steps */
    var onboardingDraft by mutableStateOf(
        UserProfile(
            id = "", name = "", age = 21, bio = "",
            profession = "Student", gender = "Male", height = 170,
            interests = emptyList(), prompts = emptyList(), photos = emptyList(),
            isVerified = false, lookingFor = ""
        )
    )
        private set

    fun updateOnboardingDraft(draft: UserProfile) { onboardingDraft = draft }

    init {
        if (authRepository.isLoggedIn) {
            // Set authenticated immediately from stored tokens — mirrors iOS synchronous check.
            // loadCurrentUser() refreshes profile in background; TokenAuthenticator handles expiry.
            _uiState.update { it.copy(isAuthenticated = true) }
            loadCurrentUser()
        }
    }

    fun sendOtp(phone: String, intent: AuthIntent, restore: Boolean = false) {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null, accountExistsForPhone = false) }
            runCatching { authRepository.sendOtp(phone, restore) }
                .onSuccess { response ->
                    val existingAccount = intent == AuthIntent.CreateAccount && response.userExists == true
                    _uiState.update {
                        it.copy(
                            isLoading = false,
                            otpSent = !existingAccount,
                            accountExistsForPhone = existingAccount,
                            deletionScheduledAt = response.deletionScheduledAt,
                            isRestoreMode = restore
                        )
                    }
                }
                .onFailure { e ->
                    Log.e("ClubMates", "sendOtp VM error: ${e::class.simpleName}: ${e.message}")
                    _uiState.update { it.copy(isLoading = false, error = e.message) }
                }
        }
    }

    fun clearAccountExists() = _uiState.update { it.copy(accountExistsForPhone = false) }
    fun clearDeletion() = _uiState.update { it.copy(deletionScheduledAt = null, isRestoreMode = false) }

    fun verifyOtp(phone: String, code: String) {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }
            runCatching { authRepository.verifyOtp(phone, code, _uiState.value.isRestoreMode) }
                .onSuccess { response ->
                    if (response.user.profileCompleted) {
                        // Returning user with a complete profile — go straight to app
                        loadCurrentUser()
                    } else if (response.isNewUser == true) {
                        // Brand new user: tokens are stored, but we don't mark
                        // isAuthenticated yet. They must complete selfie + profile first.
                        _uiState.update {
                            it.copy(isLoading = false, needsSelfie = true, needsProfile = true)
                        }
                    } else {
                        // Existing user with incomplete profile (e.g. incomplete onboarding)
                        _uiState.update {
                            it.copy(isLoading = false, needsProfile = true)
                        }
                    }
                }
                .onFailure { e -> _uiState.update { it.copy(isLoading = false, error = e.message) } }
        }
    }

    // Called by SelfieVerificationScreen once the photo + blink is confirmed.
    // Uploads the JPEG bytes in the background and advances the flow.
    fun completeSelfieVerification(jpegBytes: ByteArray) {
        _uiState.update { it.copy(needsSelfie = false) }
        viewModelScope.launch {
            authRepository.uploadVerificationSelfie(jpegBytes)
        }
    }

    // Called when the user taps "Skip" on the selfie screen.
    fun skipSelfieVerification() {
        _uiState.update { it.copy(needsSelfie = false) }
    }

    fun saveProfile(profile: UserProfile) {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }
            runCatching { authRepository.updateProfile(profile) }
                .onSuccess { saved ->
                    // Profile is complete — now the user is fully authenticated into the app
                    _uiState.update {
                        it.copy(
                            isLoading = false,
                            isAuthenticated = true,
                            needsProfile = false,
                            currentProfile = saved
                        )
                    }
                }
                .onFailure { e -> _uiState.update { it.copy(isLoading = false, error = e.message) } }
        }
    }

    fun logout() {
        viewModelScope.launch {
            authRepository.logout()
            getApplication<Application>().sendBroadcast(
                Intent(MatchesViewModel.ACTION_SIGN_OUT)
            )
            _uiState.value = AuthUiState()
        }
    }

    // Call this when the user explicitly navigates into a login/create-account flow.
    // Clears isAuthenticated so OtpScreen doesn't skip verification if tokens already exist.
    fun startAuthFlow() {
        _uiState.update { it.copy(isAuthenticated = false, needsSelfie = false, needsProfile = false, error = null, otpSent = false) }
    }

    fun advanceOnboardingStep() {
        _uiState.update { state ->
            val next = when (state.onboardingStep) {
                OnboardingStep.BASICS -> OnboardingStep.VIBE
                OnboardingStep.VIBE -> OnboardingStep.PREFERENCES
                OnboardingStep.PREFERENCES -> OnboardingStep.PREFERENCES
            }
            state.copy(onboardingStep = next)
        }
    }

    fun rewindOnboardingStep() {
        _uiState.update { state ->
            val prev = when (state.onboardingStep) {
                OnboardingStep.BASICS -> OnboardingStep.BASICS
                OnboardingStep.VIBE -> OnboardingStep.BASICS
                OnboardingStep.PREFERENCES -> OnboardingStep.VIBE
            }
            state.copy(onboardingStep = prev)
        }
    }

    fun clearError() = _uiState.update { it.copy(error = null) }

    fun resetOtpSent() = _uiState.update { it.copy(otpSent = false) }

    private fun loadCurrentUser() {
        viewModelScope.launch {
            runCatching { authRepository.getMe() }
                .onSuccess { profile ->
                    _uiState.update {
                        it.copy(isLoading = false, isAuthenticated = true, needsProfile = false, currentProfile = profile)
                    }
                }
                .onFailure { e ->
                    _uiState.update { it.copy(isLoading = false, error = e.message) }
                }
        }
    }
}
