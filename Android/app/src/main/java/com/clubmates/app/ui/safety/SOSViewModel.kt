package com.clubmates.app.ui.safety

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.clubmates.app.data.repository.SafetyRepository
import com.google.android.gms.location.LocationServices
import com.google.android.gms.tasks.Tasks
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class SOSUiState(
    val isTriggering: Boolean = false,
    val success: Boolean = false,
    val error: String? = null
)

@HiltViewModel
class SOSViewModel @Inject constructor(
    private val safetyRepository: SafetyRepository,
    @ApplicationContext private val context: Context
) : ViewModel() {

    private val _uiState = MutableStateFlow(SOSUiState())
    val uiState: StateFlow<SOSUiState> = _uiState.asStateFlow()

    fun triggerSOS(source: String, venueId: String? = null, matchId: String? = null) {
        if (_uiState.value.isTriggering) return
        viewModelScope.launch {
            _uiState.update { it.copy(isTriggering = true, error = null) }
            val fusedLocationClient = LocationServices.getFusedLocationProviderClient(context)
            val location = try { Tasks.await(fusedLocationClient.lastLocation) } catch (e: Exception) { null }
            runCatching {
                safetyRepository.triggerSOS(
                    source = source,
                    venueId = venueId,
                    matchId = matchId,
                    latitude = location?.latitude,
                    longitude = location?.longitude,
                    accuracyMeters = location?.accuracy?.toDouble()
                )
            }
                .onSuccess { _uiState.update { it.copy(isTriggering = false, success = true) } }
                .onFailure { e -> _uiState.update { it.copy(isTriggering = false, error = e.message) } }
        }
    }

    fun clearSuccess() = _uiState.update { it.copy(success = false) }
    fun clearError() = _uiState.update { it.copy(error = null) }
}
