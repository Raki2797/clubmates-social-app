package com.clubmates.app.ui.discover

import android.Manifest
import android.content.Context
import androidx.annotation.RequiresPermission
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.clubmates.app.data.local.SafetyVisibilityStore
import com.clubmates.app.data.network.ApiService
import com.clubmates.app.debug.DebugOverrideStore
import com.clubmates.app.data.network.WebSocketClient
import com.clubmates.app.data.network.WsEvent
import com.clubmates.app.data.network.WsSend
import com.clubmates.app.data.repository.DiscoverRepository
import com.clubmates.app.data.repository.SafetyRepository
import com.clubmates.app.data.repository.VenueRepository
import com.clubmates.app.domain.model.Match
import com.clubmates.app.domain.model.SwipeDirection
import com.clubmates.app.domain.model.UserProfile
import com.clubmates.app.domain.model.Venue
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.google.android.gms.tasks.CancellationTokenSource
import kotlinx.coroutines.tasks.await
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import kotlin.math.*
import javax.inject.Inject

data class DiscoverUiState(
    val venues: List<Venue> = emptyList(),
    val activeVenue: Venue? = null,
    val profiles: List<UserProfile> = emptyList(),
    val roster: List<UserProfile> = emptyList(),
    val canUndo: Boolean = false,
    val isLoading: Boolean = false,
    val error: String? = null,
    val matchResult: MatchResult? = null,
    val venueEvent: String = "",
    val selectedRosterProfile: UserProfile? = null,
    val isLoadingRosterProfile: Boolean = false,
    val selectedCity: String = "",
    val inviteError: String? = null,
    val isCheckingIn: Boolean = false,
    val checkInError: String? = null
) {
    val isCheckedIn: Boolean get() = activeVenue != null
    val occupancy: Int get() = roster.size + if (activeVenue != null) 1 else 0
    val availableCities: List<String> get() = venues.map { it.city.ifBlank { "Other" } }.distinct().sorted()
    val venuesForSelectedCity: List<Venue> get() = if (selectedCity.isEmpty()) venues
        else venues.filter { it.city.ifBlank { "Other" } == selectedCity }
}

data class MatchResult(val profile: UserProfile, val matchId: String)

@HiltViewModel
class DiscoverViewModel @Inject constructor(
    private val venueRepository: VenueRepository,
    private val discoverRepository: DiscoverRepository,
    private val safetyRepository: SafetyRepository,
    private val apiService: ApiService,
    private val wsClient: WebSocketClient,
    @ApplicationContext private val context: Context
) : ViewModel() {

    private val _uiState = MutableStateFlow(DiscoverUiState())
    val uiState: StateFlow<DiscoverUiState> = _uiState.asStateFlow()

    private val swipeHistory = mutableListOf<UserProfile>()
    private val swipedIds = mutableSetOf<String>()
    private var heartbeatJob: Job? = null
    private var autoCheckoutJob: Job? = null
    private var venueRefreshJob: Job? = null

    init {
        loadVenues()
        observeWsEvents()
        refreshSafetyFilters()
        viewModelScope.launch {
            SafetyVisibilityStore.changes.collect {
                filterHiddenUsersFromCurrentState()
            }
        }
    }

    fun loadVenues() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true) }
            runCatching { venueRepository.getVenues() }
                .onSuccess { venues ->
                    _uiState.update { state ->
                        val cities = venues.map { it.city.ifBlank { "Other" } }.distinct().sorted()
                        val city = if (state.selectedCity.isEmpty() || state.selectedCity !in cities)
                            cities.firstOrNull() ?: "" else state.selectedCity
                        state.copy(venues = venues, isLoading = false, selectedCity = city)
                    }
                }
                .onFailure { e -> _uiState.update { it.copy(isLoading = false, error = e.message) } }
        }
    }

    fun refreshVenuesForPicker() {
        loadVenues()
    }

    fun selectCity(city: String) = _uiState.update { it.copy(selectedCity = city) }

    fun checkIn(venue: Venue) {
        viewModelScope.launch {
            _uiState.update { it.copy(isCheckingIn = true, checkInError = null) }
            val overrideLat = DebugOverrideStore.get(context, DebugOverrideStore.Keys.OverrideLocationLat)
            val overrideLng = DebugOverrideStore.get(context, DebugOverrideStore.Keys.OverrideLocationLng)

            val lat: Double
            val lng: Double
            if (overrideLat != null && overrideLng != null) {
                lat = overrideLat
                lng = overrideLng
            } else {
                val fusedLocationClient = LocationServices.getFusedLocationProviderClient(context)
                val cts = CancellationTokenSource()
                val location = try {
                    fusedLocationClient.getCurrentLocation(Priority.PRIORITY_BALANCED_POWER_ACCURACY, cts.token).await()
                        ?: fusedLocationClient.lastLocation.await()
                } catch (e: Exception) { null }
                lat = location?.latitude ?: 0.0
                lng = location?.longitude ?: 0.0
            }

            runCatching { venueRepository.checkIn(venue.id, lat, lng) }
                .onSuccess {
                    _uiState.update {
                        it.copy(
                            activeVenue = venue,
                            venueEvent = "Checked in at ${venue.name}",
                            isCheckingIn = false,
                            checkInError = null
                        )
                    }
                    clearVenueEventAfterDelay()
                    loadRosterAndQueue(venue.id)
                    startHeartbeat(venue.id)
                    startAutoCheckoutMonitoring()
                    startVenueRealtimeRefresh(venue.id)
                }
                .onFailure { error ->
                    _uiState.update {
                        it.copy(
                            isCheckingIn = false,
                            checkInError = error.message ?: "Could not verify your location for this venue."
                        )
                    }
                }
        }
    }

    fun checkOut() {
        performCheckOut(event = "You checked out")
    }

    private fun performCheckOut(event: String) {
        val venue = _uiState.value.activeVenue ?: return
        viewModelScope.launch {
            runCatching { venueRepository.checkOut(venue.id) }
            heartbeatJob?.cancel()
            autoCheckoutJob?.cancel()
            venueRefreshJob?.cancel()
            swipeHistory.clear()
            swipedIds.clear()
            _uiState.update {
                it.copy(
                    activeVenue = null,
                    profiles = emptyList(),
                    roster = emptyList(),
                    canUndo = false,
                    venueEvent = event,
                    isCheckingIn = false,
                    checkInError = null
                )
            }
            clearVenueEventAfterDelay()
            loadVenues()
        }
    }

    fun swipe(profile: UserProfile, direction: SwipeDirection) {
        val venue = _uiState.value.activeVenue ?: return
        swipedIds.add(profile.id)
        swipeHistory.add(profile)
        _uiState.update { state ->
            state.copy(
                profiles = state.profiles.filter { it.id != profile.id },
                canUndo = swipeHistory.isNotEmpty()
            )
        }
        if (_uiState.value.profiles.size < 3) loadMoreProfiles(venue.id)

        viewModelScope.launch {
            runCatching { discoverRepository.swipe(profile.id, venue.id, direction) }
                .onSuccess { response ->
                    if (response.isMatch && response.matchId != null) {
                        _uiState.update { it.copy(matchResult = MatchResult(profile, response.matchId)) }
                    }
                }
        }
    }

    fun undo() {
        val venue = _uiState.value.activeVenue ?: return
        val restored = swipeHistory.removeLastOrNull() ?: return
        swipedIds.remove(restored.id)
        _uiState.update { state ->
            state.copy(
                profiles = listOf(restored) + state.profiles,
                canUndo = swipeHistory.isNotEmpty()
            )
        }
        viewModelScope.launch {
            runCatching { discoverRepository.undoSwipe(restored.id, venue.id) }
        }
    }

    fun dismissMatch() = _uiState.update { it.copy(matchResult = null) }

    fun clearError() = _uiState.update { it.copy(error = null) }

    fun refreshSafetyFilters() {
        viewModelScope.launch {
            safetyRepository.syncHiddenUsers()
            filterHiddenUsersFromCurrentState()
            val venue = _uiState.value.activeVenue ?: return@launch
            loadRosterAndQueue(venue.id)
        }
    }

    private fun filterHiddenUsersFromCurrentState() {
        _uiState.update { state ->
            state.copy(
                profiles = SafetyVisibilityStore.visibleProfiles(state.profiles),
                roster = SafetyVisibilityStore.visibleProfiles(state.roster)
            )
        }
    }

    private fun loadRosterAndQueue(venueId: String) {
        viewModelScope.launch {
            val roster = runCatching { venueRepository.getRoster(venueId) }.getOrElse { emptyList() }
            val queue = runCatching { discoverRepository.discover(venueId) }.getOrElse { emptyList() }
            val visibleRoster = SafetyVisibilityStore.visibleProfiles(roster)
            val visibleQueue = SafetyVisibilityStore.visibleProfiles(queue)
            _uiState.update { state ->
                // Only replace roster/profiles if ids or photo urls changed — prevents
                // Coil from reloading images on every 5s refresh when nothing changed.
                val newRoster = if (visibleRoster.map { it.id to it.photos.firstOrNull()?.cdnUrl } ==
                    state.roster.map { it.id to it.photos.firstOrNull()?.cdnUrl }) state.roster else visibleRoster
                val newProfiles = if (visibleQueue.map { it.id } == state.profiles.map { it.id }) state.profiles else visibleQueue
                val occupancy = visibleRoster.size + if (state.activeVenue?.id == venueId) 1 else 0
                val updatedVenues = state.venues.map { venue ->
                    if (venue.id == venueId) venue.copy(occupancy = occupancy) else venue
                }
                val updatedActiveVenue = state.activeVenue?.let { activeVenue ->
                    if (activeVenue.id == venueId) activeVenue.copy(occupancy = occupancy) else activeVenue
                }
                state.copy(
                    venues = updatedVenues,
                    activeVenue = updatedActiveVenue,
                    roster = newRoster,
                    profiles = newProfiles
                )
            }
        }
    }

    private fun loadMoreProfiles(venueId: String) {
        viewModelScope.launch {
            runCatching { discoverRepository.discover(venueId) }
                .onSuccess { newProfiles ->
                    val existing = _uiState.value.profiles.map { it.id }.toSet()
                    val fresh = newProfiles.filter { it.id !in existing && it.id !in swipedIds }
                    if (fresh.isNotEmpty()) {
                        _uiState.update { it.copy(profiles = it.profiles + fresh) }
                    }
                }
        }
    }

    private fun startHeartbeat(venueId: String) {
        heartbeatJob?.cancel()
        heartbeatJob = viewModelScope.launch {
            while (isActive) {
                delay(90_000L)
                wsClient.send(WsSend(type = "presence.ping", venueId = venueId))
            }
        }
    }

    // Single-flight flag — prevents overlapping roster/discover refreshes
    private var venueRefreshPending = false

    private fun observeWsEvents() {
        viewModelScope.launch {
            wsClient.events.collect { event ->
                when (event) {
                    is WsEvent.VenuePresenceChanged -> {
                        val activeVenueId = _uiState.value.activeVenue?.id ?: return@collect
                        if (event.venueId != activeVenueId) return@collect
                        // Single-flight: if already refreshing, set pending flag
                        if (venueRefreshPending) return@collect
                        venueRefreshPending = true
                        loadRosterAndQueue(activeVenueId)
                        venueRefreshPending = false
                    }
                    // Keep legacy presence events as fallback
                    is WsEvent.PresenceJoin -> {
                        val venueId = _uiState.value.activeVenue?.id ?: return@collect
                        if (event.venueId == venueId && !venueRefreshPending) {
                            venueRefreshPending = true
                            loadRosterAndQueue(venueId)
                            venueRefreshPending = false
                        }
                    }
                    is WsEvent.PresenceLeave -> {
                        _uiState.update { state ->
                            val updatedRoster = state.roster.filter { it.id.lowercase() != event.userId.lowercase() }
                            val venueId = state.activeVenue?.id
                            val occupancy = updatedRoster.size + if (venueId != null) 1 else 0
                            val updatedVenues = state.venues.map { venue ->
                                if (venue.id == venueId) venue.copy(occupancy = occupancy) else venue
                            }
                            val updatedActiveVenue = state.activeVenue?.copy(occupancy = occupancy)
                            state.copy(
                                venues = updatedVenues,
                                activeVenue = updatedActiveVenue,
                                roster = updatedRoster
                            )
                        }
                    }
                    else -> Unit
                }
            }
        }
    }

    private fun startAutoCheckoutMonitoring() {
        autoCheckoutJob?.cancel()
        autoCheckoutJob = viewModelScope.launch {
            while (isActive) {
                delay(30_000L)
                if (!isActive) break
                evaluateAutoCheckout()
            }
        }
    }

    @RequiresPermission(allOf = [Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION])
    private suspend fun evaluateAutoCheckout() {
        val venue = _uiState.value.activeVenue ?: return
        val venueLat = venue.latitude ?: return
        val venueLng = venue.longitude ?: return

        val overrideLat = DebugOverrideStore.get(context, DebugOverrideStore.Keys.OverrideLocationLat)
        val overrideLng = DebugOverrideStore.get(context, DebugOverrideStore.Keys.OverrideLocationLng)

        val userLat: Double
        val userLng: Double
        if (overrideLat != null && overrideLng != null) {
            userLat = overrideLat
            userLng = overrideLng
        } else {
            val fusedLocationClient = LocationServices.getFusedLocationProviderClient(context)
            val location = try {
                fusedLocationClient.lastLocation.await()
            } catch (e: Exception) { return } ?: return
            userLat = location.latitude
            userLng = location.longitude
        }

        val distanceMeters = haversineMeters(userLat, userLng, venueLat, venueLng)
        val allowedRadius = maxOf(25.0, venue.checkinRadiusMeters.toDouble())
        if (distanceMeters > allowedRadius + AUTO_CHECKOUT_BUFFER_METERS) {
            performCheckOut(event = "Auto checked out — you moved away from ${venue.name}")
        }
    }

    private fun haversineMeters(lat1: Double, lng1: Double, lat2: Double, lng2: Double): Double {
        val r = 6_371_000.0
        val dLat = Math.toRadians(lat2 - lat1)
        val dLng = Math.toRadians(lng2 - lng1)
        val a = sin(dLat / 2).pow(2) + cos(Math.toRadians(lat1)) * cos(Math.toRadians(lat2)) * sin(dLng / 2).pow(2)
        return r * 2 * atan2(sqrt(a), sqrt(1 - a))
    }

    fun openRosterProfile(profile: UserProfile) {
        if (_uiState.value.isLoadingRosterProfile) return
        viewModelScope.launch {
            // Clear first so repeat taps on the same person can reopen the sheet
            _uiState.update { it.copy(isLoadingRosterProfile = true, selectedRosterProfile = null) }
            val full = runCatching { apiService.getUserProfile(profile.id).user.toDomain() }
                .getOrDefault(profile)
            _uiState.update { it.copy(selectedRosterProfile = full, isLoadingRosterProfile = false) }
        }
    }

    fun dismissRosterProfile() = _uiState.update { it.copy(selectedRosterProfile = null) }

    fun sendInvite(targetUserId: String, treat: com.clubmates.app.data.network.TreatType) {
        val venueId = _uiState.value.activeVenue?.id ?: return
        viewModelScope.launch {
            runCatching {
                apiService.sendTreatInvite(
                    com.clubmates.app.data.network.SendTreatInviteRequest(
                        targetUserId = targetUserId,
                        venueId = venueId,
                        treatType = treat.value
                    )
                )
            }
                .onSuccess { response ->
                    _uiState.update { it.copy(inviteError = null) }
                    if (response.isMatch && response.matchId != null) {
                        // Invite immediately created a match (other person already liked/invited us)
                        // Find the profile from current swipe stack and show match alert
                        val profile = _uiState.value.profiles.firstOrNull { it.id == targetUserId }
                        if (profile != null) {
                            _uiState.update { it.copy(matchResult = MatchResult(profile, response.matchId)) }
                        } else {
                            // Profile not in current stack — show venue event instead
                            _uiState.update { it.copy(venueEvent = "It's a match!") }
                            clearVenueEventAfterDelay()
                        }
                    } else {
                        _uiState.update { it.copy(venueEvent = "Invite sent!") }
                        clearVenueEventAfterDelay()
                    }
                }
                .onFailure { e -> _uiState.update { it.copy(inviteError = e.message) } }
        }
    }

    fun clearInviteError() = _uiState.update { it.copy(inviteError = null) }

    private fun startVenueRealtimeRefresh(venueId: String) {
        // Venue presence now driven by venue.presence_changed WS event — no polling loop
        // This method kept for compatibility but does nothing
        venueRefreshJob?.cancel()
    }

    private fun clearVenueEventAfterDelay() {
        viewModelScope.launch {
            delay(3_000)
            _uiState.update { it.copy(venueEvent = "") }
        }
    }

    companion object {
        private const val AUTO_CHECKOUT_BUFFER_METERS = 35.0
    }
}
