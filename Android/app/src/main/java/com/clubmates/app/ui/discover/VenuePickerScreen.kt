package com.clubmates.app.ui.discover

import android.Manifest
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ExitToApp
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Business
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Coffee
import androidx.compose.material.icons.filled.LocalBar
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material.icons.outlined.KeyboardArrowDown
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.clubmates.app.domain.model.Venue
import com.clubmates.app.ui.theme.CardBackground
import com.clubmates.app.ui.theme.Like
import com.clubmates.app.ui.theme.Nope
import com.clubmates.app.ui.theme.Primary
import com.clubmates.app.ui.theme.Surface as AppSurface
import com.clubmates.app.ui.theme.SurfaceVariant as AppSurfaceVariant
import com.clubmates.app.ui.theme.TextHint
import com.clubmates.app.ui.theme.TextPrimary
import com.clubmates.app.ui.theme.TextSecondary
import com.google.accompanist.permissions.ExperimentalPermissionsApi
import com.google.accompanist.permissions.isGranted
import com.google.accompanist.permissions.rememberPermissionState

private const val VenueFilterAll = "All"

@OptIn(ExperimentalPermissionsApi::class)
@Composable
fun VenuePickerScreen(
    venues: List<Venue>,
    onCheckIn: (Venue) -> Unit,
    isLoading: Boolean,
    selectedCity: String = "",
    onSelectCity: (String) -> Unit = {},
    activeVenueId: String? = null,
    onCheckOut: (() -> Unit)? = null,
    onDone: () -> Unit = {}
) {
    val locationPermission = rememberPermissionState(Manifest.permission.ACCESS_FINE_LOCATION)
    var pendingVenue by remember { mutableStateOf<Venue?>(null) }
    var selectedNeighborhood by remember(selectedCity) { mutableStateOf(VenueFilterAll) }
    var selectedMusic by remember(selectedCity) { mutableStateOf(VenueFilterAll) }
    var selectedVibe by remember(selectedCity) { mutableStateOf(VenueFilterAll) }
    var venueSearchText by remember { mutableStateOf("") }
    var cityMenuExpanded by remember { mutableStateOf(false) }
    var neighborhoodMenuExpanded by remember { mutableStateOf(false) }
    var musicMenuExpanded by remember { mutableStateOf(false) }
    var vibeMenuExpanded by remember { mutableStateOf(false) }

    val cities = remember(venues) {
        venues.map { it.city.ifBlank { "Other" } }.distinct().sorted()
    }
    val selectedCityVenues = remember(venues, selectedCity) {
        if (selectedCity.isBlank()) venues else venues.filter { it.city.ifBlank { "Other" } == selectedCity }
    }
    val neighborhoodOptions = remember(selectedCityVenues) {
        venueFilterValues(selectedCityVenues.map { it.neighborhood })
    }
    val musicOptions = remember(selectedCityVenues) {
        venueFilterValues(selectedCityVenues.flatMap { venueMusicTokens(it) })
    }
    val vibeOptions = remember(selectedCityVenues) {
        venueFilterValues(selectedCityVenues.map { venueVibeCategory(it) })
    }
    val searchQuery = venueSearchText.trim()
    val hasActiveFilters = selectedNeighborhood != VenueFilterAll ||
        selectedMusic != VenueFilterAll ||
        selectedVibe != VenueFilterAll
    val filteredVenues = remember(
        selectedCityVenues,
        selectedNeighborhood,
        selectedMusic,
        selectedVibe,
        searchQuery
    ) {
        selectedCityVenues.filter { venue ->
            val matchesNeighborhood = selectedNeighborhood == VenueFilterAll || venue.neighborhood == selectedNeighborhood
            val matchesMusic = selectedMusic == VenueFilterAll || venueMusicTokens(venue).contains(selectedMusic)
            val matchesVibe = selectedVibe == VenueFilterAll || venueVibeCategory(venue) == selectedVibe
            val matchesSearch = searchQuery.isBlank() || venue.name.contains(searchQuery, ignoreCase = true)
            matchesNeighborhood && matchesMusic && matchesVibe && matchesSearch
        }
    }

    LaunchedEffect(locationPermission.status) {
        if (locationPermission.status.isGranted) {
            pendingVenue?.let { venue ->
                onCheckIn(venue)
                pendingVenue = null
            }
        }
    }

    fun clearFilters() {
        selectedNeighborhood = VenueFilterAll
        selectedMusic = VenueFilterAll
        selectedVibe = VenueFilterAll
    }

    fun handleVenueTap(venue: Venue) {
        if (locationPermission.status.isGranted) {
            onCheckIn(venue)
        } else {
            pendingVenue = venue
            locationPermission.launchPermissionRequest()
        }
    }

    Box(modifier = Modifier.fillMaxSize()) {
        VenueScreenBackground(modifier = Modifier.fillMaxSize())

        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 20.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(
                        "Check in",
                        fontSize = 26.sp,
                        fontWeight = FontWeight.Bold,
                        color = TextPrimary
                    )
                    Text(
                        "Find the right spot before you start swiping.",
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Medium,
                        color = TextSecondary
                    )
                }

                TextButton(
                    onClick = onDone,
                    colors = ButtonDefaults.textButtonColors(contentColor = Color.White),
                    modifier = Modifier
                        .height(40.dp)
                        .clip(RoundedCornerShape(999.dp))
                        .background(Brush.horizontalGradient(listOf(Primary, Color(0xFFC44EFF))))
                ) {
                    Text(
                        "Done",
                        fontSize = 14.sp,
                        fontWeight = FontWeight.SemiBold,
                        modifier = Modifier.padding(horizontal = 6.dp)
                    )
                }
            }

            VenueSectionCard {
                Column(
                    modifier = Modifier.padding(14.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            "City",
                            fontSize = 13.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = TextSecondary
                        )
                        Text(
                            venueCountSummary(selectedCityVenues.size),
                            fontSize = 12.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = TextHint
                        )
                    }

                    Box {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(58.dp)
                                .background(AppSurface, RoundedCornerShape(14.dp))
                                .border(1.dp, Primary.copy(alpha = 0.18f), RoundedCornerShape(14.dp))
                                .clickable { cityMenuExpanded = true }
                                .padding(horizontal = 14.dp),
                            horizontalArrangement = Arrangement.spacedBy(10.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Icon(
                                Icons.Default.Business,
                                contentDescription = null,
                                tint = Primary,
                                modifier = Modifier.size(15.dp)
                            )

                            Column(
                                modifier = Modifier.weight(1f),
                                verticalArrangement = Arrangement.spacedBy(2.dp)
                            ) {
                                Text(
                                    selectedCity.ifBlank { "Select city" },
                                    fontSize = 17.sp,
                                    fontWeight = FontWeight.Bold,
                                    color = TextPrimary,
                                    maxLines = 1
                                )
                                Text(
                                    "${cities.size} cities available",
                                    fontSize = 12.sp,
                                    fontWeight = FontWeight.SemiBold,
                                    color = TextHint
                                )
                            }

                            Icon(
                                Icons.Default.Tune,
                                contentDescription = null,
                                tint = TextHint,
                                modifier = Modifier.size(12.dp)
                            )
                        }

                        DropdownMenu(
                            expanded = cityMenuExpanded,
                            onDismissRequest = { cityMenuExpanded = false }
                        ) {
                            cities.forEach { city ->
                                DropdownMenuItem(
                                    text = {
                                        Row(verticalAlignment = Alignment.CenterVertically) {
                                            Text(city)
                                            if (city == selectedCity) {
                                                Spacer(modifier = Modifier.width(8.dp))
                                                Icon(
                                                    Icons.Filled.CheckCircle,
                                                    contentDescription = null,
                                                    tint = Primary,
                                                    modifier = Modifier.size(16.dp)
                                                )
                                            }
                                        }
                                    },
                                    onClick = {
                                        clearFilters()
                                        venueSearchText = ""
                                        onSelectCity(city)
                                        cityMenuExpanded = false
                                    }
                                )
                            }
                        }
                    }
                }
            }

            VenueSectionCard {
                Column(
                    modifier = Modifier.padding(14.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            "Filters",
                            fontSize = 13.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = TextSecondary
                        )
                        if (hasActiveFilters) {
                            TextButton(onClick = { clearFilters() }) {
                                Text("Clear", color = Primary, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                            }
                        }
                    }

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        VenueFilterChip(
                            title = "Area",
                            icon = Icons.Default.LocationOn,
                            selection = selectedNeighborhood,
                            expanded = neighborhoodMenuExpanded,
                            onExpandedChange = { neighborhoodMenuExpanded = it },
                            options = neighborhoodOptions,
                            onSelect = { selectedNeighborhood = it },
                            modifier = Modifier.weight(1f)
                        )
                        VenueFilterChip(
                            title = "Music",
                            icon = Icons.Default.MusicNote,
                            selection = selectedMusic,
                            expanded = musicMenuExpanded,
                            onExpandedChange = { musicMenuExpanded = it },
                            options = musicOptions,
                            onSelect = { selectedMusic = it },
                            modifier = Modifier.weight(1f)
                        )
                        VenueFilterChip(
                            title = "Vibe",
                            icon = Icons.Default.AutoAwesome,
                            selection = selectedVibe,
                            expanded = vibeMenuExpanded,
                            onExpandedChange = { vibeMenuExpanded = it },
                            options = vibeOptions,
                            onSelect = { selectedVibe = it },
                            modifier = Modifier.weight(1f)
                        )
                    }
                }
            }

            VenueSearchField(
                value = venueSearchText,
                onValueChange = { venueSearchText = it },
                onClear = { venueSearchText = "" },
                hasQuery = searchQuery.isNotBlank()
            )

            when {
                isLoading -> Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = Primary)
                }

                filteredVenues.isEmpty() -> {
                    VenueEmptyState(
                        hasActiveFilters = hasActiveFilters,
                        searchQuery = searchQuery,
                        selectedCity = selectedCity,
                        onClear = {
                            clearFilters()
                            venueSearchText = ""
                        }
                    )
                }

                else -> {
                    LazyColumn(
                        verticalArrangement = Arrangement.spacedBy(10.dp),
                        modifier = Modifier.weight(1f, fill = true)
                    ) {
                        items(filteredVenues, key = { it.id }) { venue ->
                            VenueCard(
                                venue = venue,
                                isActive = venue.id == activeVenueId,
                                onClick = { handleVenueTap(venue) }
                            )
                        }

                        if (activeVenueId != null && onCheckOut != null) {
                            item {
                                TextButton(
                                    onClick = onCheckOut,
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .clip(RoundedCornerShape(14.dp))
                                        .background(AppSurface)
                                ) {
                                    Icon(
                                        Icons.AutoMirrored.Filled.ExitToApp,
                                        contentDescription = null,
                                        tint = Nope,
                                        modifier = Modifier.size(15.dp)
                                    )
                                    Spacer(modifier = Modifier.width(8.dp))
                                    Text(
                                        "Check out of venue",
                                        color = Nope,
                                        fontSize = 15.sp,
                                        fontWeight = FontWeight.SemiBold
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun VenueSectionCard(content: @Composable ColumnScope.() -> Unit) {
    Surface(
        color = CardBackground,
        shape = RoundedCornerShape(16.dp),
        tonalElevation = 0.dp,
        modifier = Modifier
            .fillMaxWidth()
            .border(1.dp, AppSurface, RoundedCornerShape(16.dp))
    ) {
        Column(content = content)
    }
}

@Composable
private fun VenueFilterChip(
    title: String,
    icon: ImageVector,
    selection: String,
    expanded: Boolean,
    onExpandedChange: (Boolean) -> Unit,
    options: List<String>,
    onSelect: (String) -> Unit,
    modifier: Modifier = Modifier
) {
    Box(modifier = modifier) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(36.dp)
                .clip(RoundedCornerShape(999.dp))
                .background(if (selection == VenueFilterAll) AppSurface else Primary.copy(alpha = 0.12f))
                .border(
                    1.dp,
                    if (selection == VenueFilterAll) AppSurfaceVariant.copy(alpha = 0.75f) else Primary.copy(alpha = 0.28f),
                    RoundedCornerShape(999.dp)
                )
                .clickable { onExpandedChange(true) }
                .padding(horizontal = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Icon(
                icon,
                contentDescription = null,
                modifier = Modifier.size(11.dp),
                tint = if (selection == VenueFilterAll) TextHint else Primary
            )
            Text(
                if (selection == VenueFilterAll) title else selection,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                fontSize = 12.sp,
                fontWeight = FontWeight.SemiBold,
                color = if (selection == VenueFilterAll) TextSecondary else TextPrimary,
                modifier = Modifier.weight(1f, fill = false)
            )
            Icon(
                Icons.Outlined.KeyboardArrowDown,
                contentDescription = null,
                modifier = Modifier.size(9.dp),
                tint = TextHint
            )
        }

        DropdownMenu(
            expanded = expanded,
            onDismissRequest = { onExpandedChange(false) }
        ) {
            options.forEach { option ->
                DropdownMenuItem(
                    text = { Text(option) },
                    onClick = {
                        onSelect(option)
                        onExpandedChange(false)
                    }
                )
            }
        }
    }
}

@Composable
private fun VenueSearchField(
    value: String,
    onValueChange: (String) -> Unit,
    onClear: () -> Unit,
    hasQuery: Boolean
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(46.dp)
            .background(CardBackground, RoundedCornerShape(16.dp))
            .border(
                1.dp,
                if (hasQuery) Primary.copy(alpha = 0.28f) else AppSurface,
                RoundedCornerShape(16.dp)
            )
            .padding(horizontal = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Icon(
            Icons.Default.Search,
            contentDescription = null,
            tint = TextHint,
            modifier = Modifier.size(14.dp)
        )
        BasicTextField(
            value = value,
            onValueChange = onValueChange,
            singleLine = true,
            textStyle = TextStyle(
                color = TextPrimary,
                fontSize = 14.sp,
                fontWeight = FontWeight.SemiBold
            ),
            modifier = Modifier.weight(1f),
            cursorBrush = SolidColor(Primary),
            decorationBox = { innerTextField ->
                Box(contentAlignment = Alignment.CenterStart) {
                    if (value.isBlank()) {
                        Text(
                            "Search venue name",
                            color = TextHint,
                            fontSize = 14.sp,
                            fontWeight = FontWeight.SemiBold
                        )
                    }
                    innerTextField()
                }
            }
        )
        if (hasQuery) {
            Icon(
                Icons.Filled.Cancel,
                contentDescription = "Clear search",
                tint = TextHint,
                modifier = Modifier
                    .size(15.dp)
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                        onClick = onClear
                    )
            )
        }
    }
}

@Composable
fun VenueCard(
    venue: Venue,
    onClick: () -> Unit,
    isActive: Boolean = false
) {
    Surface(
        onClick = onClick,
        color = CardBackground,
        shape = RoundedCornerShape(16.dp),
        modifier = Modifier.fillMaxWidth(),
        border = androidx.compose.foundation.BorderStroke(
            width = if (isActive) 2.dp else 1.dp,
            color = if (isActive) Primary.copy(alpha = 0.55f) else AppSurface
        )
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(14.dp),
            horizontalArrangement = Arrangement.spacedBy(14.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            VenueIconCircle(venue = venue)

            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        venue.name,
                        fontSize = 17.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = TextPrimary,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    if (isActive) {
                        Spacer(modifier = Modifier.width(6.dp))
                        Icon(
                            Icons.Filled.CheckCircle,
                            contentDescription = null,
                            tint = Like,
                            modifier = Modifier.size(14.dp)
                        )
                    }
                }

                Text(
                    "${venue.neighborhood} • ${venue.music}",
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Medium,
                    color = TextSecondary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Text(
                    venue.vibe,
                    fontSize = 12.sp,
                    color = TextHint,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )

                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    VenueCompactTag(venueVibeCategory(venue))
                    VenueCompactTag(venueMusicTokens(venue).firstOrNull() ?: venue.music)
                }
            }

            Column(
                horizontalAlignment = Alignment.End,
                verticalArrangement = Arrangement.spacedBy(2.dp)
            ) {
                Text(
                    venue.occupancy.toString(),
                    fontSize = 19.sp,
                    fontWeight = FontWeight.Bold,
                    color = TextPrimary
                )
                Text(
                    "here now",
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Medium,
                    color = TextHint
                )
            }
        }
    }
}

@Composable
private fun VenueIconCircle(venue: Venue) {
    val gradientColors = venue.gradientHex.mapNotNull { hex ->
        runCatching { Color(android.graphics.Color.parseColor(hex)) }.getOrNull()
    }.ifEmpty { listOf(Color(0xFF2A0A4A), Color(0xFF0A1A3A)) }

    Box(
        modifier = Modifier
            .size(48.dp)
            .background(Brush.linearGradient(gradientColors), CircleShape),
        contentAlignment = Alignment.Center
    ) {
        Icon(
            venueSymbolIcon(venue.symbolName),
            contentDescription = null,
            tint = Color.White,
            modifier = Modifier.size(20.dp)
        )
    }
}

@Composable
private fun VenueCompactTag(text: String) {
    Box(
        modifier = Modifier
            .clip(RoundedCornerShape(999.dp))
            .background(AppSurface.copy(alpha = 0.8f))
            .padding(horizontal = 7.dp, vertical = 4.dp)
    ) {
        Text(
            text,
            fontSize = 10.sp,
            fontWeight = FontWeight.SemiBold,
            color = TextHint,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}

@Composable
private fun VenueEmptyState(
    hasActiveFilters: Boolean,
    searchQuery: String,
    selectedCity: String,
    onClear: () -> Unit
) {
    val title = when {
        searchQuery.isNotBlank() -> "No venues named \"$searchQuery\""
        hasActiveFilters -> "No venues match these filters"
        selectedCity.isNotBlank() -> "No venues in $selectedCity yet"
        else -> "No venues available right now"
    }

    VenueSectionCard {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 30.dp, horizontal = 20.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Icon(
                if (hasActiveFilters || searchQuery.isNotBlank()) Icons.Default.Tune else Icons.Default.Business,
                contentDescription = null,
                tint = TextHint,
                modifier = Modifier.size(28.dp)
            )
            Text(
                title,
                fontSize = 14.sp,
                fontWeight = FontWeight.SemiBold,
                color = TextSecondary
            )
            if (hasActiveFilters || searchQuery.isNotBlank()) {
                TextButton(onClick = onClear) {
                    Text("Clear search and filters", color = Primary, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                }
            }
        }
    }
}

private fun venueCountSummary(count: Int): String {
    return if (count >= 30) "30+ venues" else "$count venues"
}

private fun venueFilterValues(values: List<String>): List<String> {
    return listOf(VenueFilterAll) + values
        .filter { it.isNotBlank() }
        .distinct()
        .sortedBy { it.lowercase() }
}

private fun venueMusicTokens(venue: Venue): List<String> {
    return venue.music
        .split("/", "&", ",")
        .map { it.trim() }
        .filter { it.isNotBlank() }
}

private fun venueVibeCategory(venue: Venue): String {
    val text = "${venue.vibe} ${venue.music} ${venue.name}".lowercase()
    return when {
        "brew" in text || "beer" in text -> "Brewery"
        "rooftop" in text || "sky" in text -> "Rooftop"
        "live" in text || "jazz" in text || "rock" in text -> "Live"
        "club" in text || "edm" in text || "dance" in text -> "Club"
        "cocktail" in text -> "Cocktails"
        "pub" in text -> "Pub"
        "lounge" in text -> "Lounge"
        else -> "Social"
    }
}

private fun venueSymbolIcon(symbolName: String): ImageVector {
    return when (symbolName.lowercase()) {
        "wineglass", "wineglass.fill" -> Icons.Default.LocalBar
        "mug", "mug.fill", "beer", "beer.fill" -> Icons.Default.LocalBar
        "cup.and.saucer", "cup.and.saucer.fill", "cup", "cup.fill" -> Icons.Default.Coffee
        "star", "star.fill" -> Icons.Default.Star
        else -> Icons.Default.LocationOn
    }
}
