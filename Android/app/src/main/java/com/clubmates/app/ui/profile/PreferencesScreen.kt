package com.clubmates.app.ui.profile

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.clubmates.app.domain.model.DatePreferences
import com.clubmates.app.ui.theme.*

private val prefPink = Color(0xFFFF6B9D)
private val prefPurple = Color(0xFFC44EFF)
private val prefGradient = Brush.linearGradient(listOf(prefPink, prefPurple))

private val lookingForOptions = listOf("Dating", "Something Casual", "Friendship", "Open to Anything")
private val genderOptions = listOf("Men", "Women", "Non-binary")

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun PreferencesScreen(
    onBack: () -> Unit,
    viewModel: ProfileViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    val profile = uiState.profile ?: return

    var lookingFor by remember { mutableStateOf(profile.lookingFor) }
    var preferences by remember { mutableStateOf(profile.preferences) }
    var isGhostMode by remember { mutableStateOf(profile.isGhostMode) }

    // Save on back
    val saveAndBack = {
        viewModel.patchProfile(
            com.clubmates.app.data.network.PatchProfileRequest(
                lookingFor = lookingFor.ifBlank { null },
                preferences = com.clubmates.app.data.network.ApiPreferences(
                    ageMin = preferences.ageMin, ageMax = preferences.ageMax,
                    genders = preferences.genders, heightMin = preferences.heightMin,
                    heightMax = preferences.heightMax, verifiedOnly = preferences.verifiedOnly
                ),
                isGhostMode = isGhostMode
            )
        )
        onBack()
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Background)
    ) {
        // Top bar
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 8.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            IconButton(onClick = onBack) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back", tint = TextPrimary)
            }
            Text("Dating Preferences", fontSize = 18.sp, fontWeight = FontWeight.SemiBold, color = TextPrimary)
            TextButton(onClick = saveAndBack, enabled = !uiState.isSaving) {
                if (uiState.isSaving) {
                    CircularProgressIndicator(color = prefPink, strokeWidth = 2.dp, modifier = Modifier.size(20.dp))
                } else {
                    Text("Done", color = prefPink, fontWeight = FontWeight.SemiBold)
                }
            }
        }

        HorizontalDivider(color = SurfaceVariant)

        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp, vertical = 16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            // Summary pills
            SummaryPillsRow(lookingFor = lookingFor, preferences = preferences)

            // Looking For
            PrefCard {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    PrefSectionHeader(icon = Icons.Default.Favorite, title = "Looking For")
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        lookingForOptions.forEach { option ->
                            val selected = lookingFor == option
                            PrefChip(
                                label = option,
                                selected = selected,
                                onClick = { lookingFor = if (selected) "" else option }
                            )
                        }
                    }
                }
            }

            // Age Range
            PrefCard {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        PrefSectionHeader(icon = Icons.Default.Cake, title = "Age Range")
                        Text(
                            "${preferences.ageMin} – ${preferences.ageMax}",
                            fontSize = 15.sp, fontWeight = FontWeight.Bold,
                            style = androidx.compose.ui.text.TextStyle(brush = prefGradient),
                            modifier = Modifier
                                .background(prefPink.copy(alpha = 0.1f), RoundedCornerShape(50))
                                .border(1.dp, prefPink.copy(alpha = 0.25f), RoundedCornerShape(50))
                                .padding(horizontal = 12.dp, vertical = 5.dp)
                        )
                    }
                    RangeSlider(
                        value = preferences.ageMin.toFloat()..preferences.ageMax.toFloat(),
                        onValueChange = { range ->
                            preferences = preferences.copy(
                                ageMin = range.start.toInt().coerceIn(18, preferences.ageMax - 1),
                                ageMax = range.endInclusive.toInt().coerceIn(preferences.ageMin + 1, 60)
                            )
                        },
                        valueRange = 18f..60f,
                        steps = 41,
                        colors = SliderDefaults.colors(
                            thumbColor = prefPink,
                            activeTrackColor = prefPink,
                            inactiveTrackColor = Surface
                        )
                    )
                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        Text("18", fontSize = 11.sp, color = TextHint)
                        Text("60", fontSize = 11.sp, color = TextHint)
                    }
                }
            }

            // Height Range
            PrefCard {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        PrefSectionHeader(icon = Icons.Default.Height, title = "Height Range")
                        Text(
                            "${preferences.heightMin} – ${preferences.heightMax} cm",
                            fontSize = 15.sp, fontWeight = FontWeight.Bold,
                            style = androidx.compose.ui.text.TextStyle(brush = prefGradient),
                            modifier = Modifier
                                .background(prefPink.copy(alpha = 0.1f), RoundedCornerShape(50))
                                .border(1.dp, prefPink.copy(alpha = 0.25f), RoundedCornerShape(50))
                                .padding(horizontal = 12.dp, vertical = 5.dp)
                        )
                    }
                    RangeSlider(
                        value = preferences.heightMin.toFloat()..preferences.heightMax.toFloat(),
                        onValueChange = { range ->
                            preferences = preferences.copy(
                                heightMin = range.start.toInt().coerceIn(140, preferences.heightMax - 1),
                                heightMax = range.endInclusive.toInt().coerceIn(preferences.heightMin + 1, 220)
                            )
                        },
                        valueRange = 140f..220f,
                        steps = 79,
                        colors = SliderDefaults.colors(
                            thumbColor = prefPink,
                            activeTrackColor = prefPink,
                            inactiveTrackColor = Surface
                        )
                    )
                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        Text("140 cm", fontSize = 11.sp, color = TextHint)
                        Text("220 cm", fontSize = 11.sp, color = TextHint)
                    }
                }
            }

            // Show Me (Gender)
            PrefCard {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    PrefSectionHeader(icon = Icons.Default.Person, title = "Show Me")
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        genderOptions.forEach { option ->
                            val selected = preferences.genders.contains(option)
                            PrefChip(
                                label = option,
                                selected = selected,
                                onClick = {
                                    preferences = preferences.copy(
                                        genders = if (selected) preferences.genders - option
                                        else preferences.genders + option
                                    )
                                }
                            )
                        }
                        // Everyone chip
                        PrefChip(
                            label = "Everyone",
                            selected = preferences.genders.isEmpty(),
                            onClick = { preferences = preferences.copy(genders = emptyList()) }
                        )
                    }
                }
            }

            // Verified Only
            PrefCard {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    PrefIconBox(icon = Icons.Default.CheckCircle)
                    Column(modifier = Modifier.weight(1f)) {
                        Text("Verified Profiles Only", fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = TextPrimary)
                        Text("Only show selfie-verified users", fontSize = 12.sp, color = TextSecondary)
                    }
                    Switch(
                        checked = preferences.verifiedOnly,
                        onCheckedChange = { preferences = preferences.copy(verifiedOnly = it) },
                        colors = SwitchDefaults.colors(checkedThumbColor = prefPink, checkedTrackColor = prefPink.copy(alpha = 0.4f))
                    )
                }
            }

            // Ghost Mode
            PrefCard {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    PrefIconBox(icon = Icons.Default.VisibilityOff)
                    Column(modifier = Modifier.weight(1f)) {
                        Text("Ghost Mode", fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = TextPrimary)
                        Text(
                            if (isGhostMode) "You're hidden from discovery" else "You appear in venue discovery",
                            fontSize = 12.sp, color = TextSecondary
                        )
                    }
                    Switch(
                        checked = isGhostMode,
                        onCheckedChange = { isGhostMode = it },
                        colors = SwitchDefaults.colors(checkedThumbColor = Color(0xFFFF6B9D), checkedTrackColor = Color(0xFFFF6B9D).copy(alpha = 0.4f))
                    )
                }
            }

            uiState.error?.let {
                Text(it, color = MaterialTheme.colorScheme.error, fontSize = 14.sp)
            }

            Spacer(modifier = Modifier.height(24.dp))
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
private fun SummaryPillsRow(lookingFor: String, preferences: DatePreferences) {
    FlowRow(
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
        modifier = Modifier.padding(horizontal = 4.dp)
    ) {
        SummaryPill(icon = "♥", text = if (lookingFor.isBlank()) "Open" else lookingFor)
        SummaryPill(icon = "🎂", text = "${preferences.ageMin}-${preferences.ageMax}")
        SummaryPill(icon = "📏", text = "${preferences.heightMin}-${preferences.heightMax} cm")
        SummaryPill(icon = "👥", text = if (preferences.genders.isEmpty()) "Everyone" else preferences.genders.joinToString(", "))
    }
}

@Composable
private fun SummaryPill(icon: String, text: String) {
    Row(
        modifier = Modifier
            .background(Background.copy(alpha = 0.62f), RoundedCornerShape(50))
            .border(1.dp, SurfaceVariant.copy(alpha = 0.75f), RoundedCornerShape(50))
            .padding(horizontal = 11.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Text(icon, fontSize = 11.sp)
        Text(text, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = TextPrimary, maxLines = 1)
    }
}

@Composable
private fun PrefCard(content: @Composable () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(CardBackground, RoundedCornerShape(16.dp))
            .border(1.dp, prefPink.copy(alpha = 0.12f), RoundedCornerShape(16.dp))
            .padding(16.dp)
    ) {
        content()
    }
}

@Composable
private fun PrefSectionHeader(icon: ImageVector, title: String) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        PrefIconBox(icon = icon)
        Text(title, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = TextPrimary)
    }
}

@Composable
private fun PrefIconBox(icon: ImageVector) {
    Box(
        modifier = Modifier
            .size(30.dp)
            .background(prefPink.copy(alpha = 0.12f), CircleShape),
        contentAlignment = Alignment.Center
    ) {
        Icon(icon, contentDescription = null, tint = prefPink, modifier = Modifier.size(15.dp))
    }
}

@Composable
private fun PrefChip(label: String, selected: Boolean, onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .background(
                if (selected) Brush.linearGradient(listOf(prefPink, prefPurple))
                else Brush.linearGradient(listOf(Surface, Surface)),
                RoundedCornerShape(50)
            )
            .border(
                1.dp,
                if (selected) Color.Transparent else prefPink.copy(alpha = 0.2f),
                RoundedCornerShape(50)
            )
            .clickable { onClick() }
            .padding(horizontal = 14.dp, vertical = 8.dp)
    ) {
        Text(
            label,
            fontSize = 13.sp,
            fontWeight = FontWeight.SemiBold,
            color = if (selected) Color.White else TextSecondary
        )
    }
}
