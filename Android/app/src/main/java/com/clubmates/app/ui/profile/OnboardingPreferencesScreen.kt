package com.clubmates.app.ui.profile

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.clubmates.app.domain.model.DatePreferences
import com.clubmates.app.ui.auth.AuthViewModel
import com.clubmates.app.ui.theme.*

private val lookingForOptions = listOf("Dating", "Something Casual", "Friendship", "Open to Anything")
private val genderOptions = listOf("Men", "Women", "Non-binary")

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun OnboardingPreferencesScreen(
    viewModel: AuthViewModel,
    onBack: () -> Unit,
    onFinish: () -> Unit
) {
    val uiState by viewModel.uiState.collectAsState()
    val draft = viewModel.onboardingDraft

    var lookingFor by remember { mutableStateOf(draft.lookingFor) }
    var preferences by remember { mutableStateOf(draft.preferences) }

    val pink = Color(0xFFFF6B9D)
    val purple = Color(0xFFC44EFF)
    val green = Color(0xFF00C853)

    Box(modifier = Modifier.fillMaxSize().background(Background)) {
        Column(modifier = Modifier.fillMaxSize()) {
            OnboardingHeader(step = 3, totalSteps = 3, onBack = onBack)

            Column(
                modifier = Modifier
                    .weight(1f)
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 20.dp),
                verticalArrangement = Arrangement.spacedBy(20.dp)
            ) {
                Spacer(modifier = Modifier.height(8.dp))

                // Intro card
                Column(
                    modifier = Modifier.fillMaxWidth().background(CardBackground, RoundedCornerShape(18.dp)).border(1.dp, green.copy(alpha = 0.2f), RoundedCornerShape(18.dp)).padding(18.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Text("Who do you want to meet?", fontSize = 22.sp, fontWeight = FontWeight.Black, color = TextPrimary)
                    Text("Set your preferences so ClubMates shows you the right people.", fontSize = 14.sp, color = TextSecondary, lineHeight = 20.sp)
                }

                // Looking For
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text("LOOKING FOR", fontSize = 11.sp, fontWeight = FontWeight.Bold, color = TextHint, letterSpacing = 1.sp)
                    androidx.compose.foundation.layout.FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        lookingForOptions.forEach { option ->
                            val selected = lookingFor == option
                            Box(
                                modifier = Modifier
                                    .background(if (selected) Brush.linearGradient(listOf(pink, purple)) else Brush.linearGradient(listOf(Surface, Surface)), RoundedCornerShape(50))
                                    .border(1.dp, if (selected) Color.Transparent else pink.copy(alpha = 0.2f), RoundedCornerShape(50))
                                    .clickable { lookingFor = if (selected) "" else option }
                                    .padding(horizontal = 14.dp, vertical = 9.dp)
                            ) {
                                Text(option, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = if (selected) Color.White else TextSecondary)
                            }
                        }
                    }
                }

                // Age Range
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        Text("AGE RANGE", fontSize = 11.sp, fontWeight = FontWeight.Bold, color = TextHint, letterSpacing = 1.sp)
                        Text("${preferences.ageMin} – ${preferences.ageMax}", fontSize = 13.sp, fontWeight = FontWeight.Bold,
                            style = androidx.compose.ui.text.TextStyle(brush = Brush.linearGradient(listOf(pink, purple))))
                    }
                    RangeSlider(
                        value = preferences.ageMin.toFloat()..preferences.ageMax.toFloat(),
                        onValueChange = { range -> preferences = preferences.copy(ageMin = range.start.toInt().coerceIn(18, preferences.ageMax - 1), ageMax = range.endInclusive.toInt().coerceIn(preferences.ageMin + 1, 60)) },
                        valueRange = 18f..60f, steps = 41,
                        colors = SliderDefaults.colors(thumbColor = pink, activeTrackColor = pink, inactiveTrackColor = Surface)
                    )
                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        Text("18", fontSize = 11.sp, color = TextHint); Text("60", fontSize = 11.sp, color = TextHint)
                    }
                }

                // Height Range
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        Text("HEIGHT RANGE", fontSize = 11.sp, fontWeight = FontWeight.Bold, color = TextHint, letterSpacing = 1.sp)
                        Text("${preferences.heightMin} – ${preferences.heightMax} cm", fontSize = 13.sp, fontWeight = FontWeight.Bold,
                            style = androidx.compose.ui.text.TextStyle(brush = Brush.linearGradient(listOf(pink, purple))))
                    }
                    RangeSlider(
                        value = preferences.heightMin.toFloat()..preferences.heightMax.toFloat(),
                        onValueChange = { range -> preferences = preferences.copy(heightMin = range.start.toInt().coerceIn(140, preferences.heightMax - 1), heightMax = range.endInclusive.toInt().coerceIn(preferences.heightMin + 1, 220)) },
                        valueRange = 140f..220f, steps = 79,
                        colors = SliderDefaults.colors(thumbColor = pink, activeTrackColor = pink, inactiveTrackColor = Surface)
                    )
                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        Text("140 cm", fontSize = 11.sp, color = TextHint); Text("220 cm", fontSize = 11.sp, color = TextHint)
                    }
                }

                // Show Me (gender)
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text("SHOW ME", fontSize = 11.sp, fontWeight = FontWeight.Bold, color = TextHint, letterSpacing = 1.sp)
                    androidx.compose.foundation.layout.FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        genderOptions.forEach { option ->
                            val selected = preferences.genders.contains(option)
                            Box(
                                modifier = Modifier
                                    .background(if (selected) Brush.linearGradient(listOf(pink, purple)) else Brush.linearGradient(listOf(Surface, Surface)), RoundedCornerShape(50))
                                    .border(1.dp, if (selected) Color.Transparent else pink.copy(alpha = 0.2f), RoundedCornerShape(50))
                                    .clickable { preferences = preferences.copy(genders = if (selected) preferences.genders - option else preferences.genders + option) }
                                    .padding(horizontal = 14.dp, vertical = 9.dp)
                            ) {
                                Text(option, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = if (selected) Color.White else TextSecondary)
                            }
                        }
                        // Everyone chip
                        val everyoneSelected = preferences.genders.isEmpty()
                        Box(
                            modifier = Modifier
                                .background(if (everyoneSelected) Brush.linearGradient(listOf(pink, purple)) else Brush.linearGradient(listOf(Surface, Surface)), RoundedCornerShape(50))
                                .border(1.dp, if (everyoneSelected) Color.Transparent else pink.copy(alpha = 0.2f), RoundedCornerShape(50))
                                .clickable { preferences = preferences.copy(genders = emptyList()) }
                                .padding(horizontal = 14.dp, vertical = 9.dp)
                        ) {
                            Text("Everyone", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = if (everyoneSelected) Color.White else TextSecondary)
                        }
                    }
                }

                // Verified Only
                Row(
                    modifier = Modifier.fillMaxWidth().background(CardBackground, RoundedCornerShape(16.dp)).border(1.dp, Color.White.copy(alpha = 0.06f), RoundedCornerShape(16.dp)).padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    Box(modifier = Modifier.size(36.dp).background(green.copy(alpha = 0.12f), CircleShape), contentAlignment = Alignment.Center) {
                        Icon(Icons.Default.VerifiedUser, contentDescription = null, tint = green, modifier = Modifier.size(16.dp))
                    }
                    Column(modifier = Modifier.weight(1f)) {
                        Text("Verified Profiles Only", fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = TextPrimary)
                        Text("Only show selfie-verified users", fontSize = 12.sp, color = TextSecondary)
                    }
                    Switch(checked = preferences.verifiedOnly, onCheckedChange = { preferences = preferences.copy(verifiedOnly = it) },
                        colors = SwitchDefaults.colors(checkedThumbColor = pink, checkedTrackColor = pink.copy(alpha = 0.4f)))
                }

                uiState.error?.let { Text(it, color = MaterialTheme.colorScheme.error, fontSize = 14.sp) }
                Spacer(modifier = Modifier.height(100.dp))
            }
        }

        OnboardingBottomBar(
            label = if (uiState.isLoading) "Creating profile..." else "Let's go 🎉",
            enabled = !uiState.isLoading,
            isLoading = uiState.isLoading,
            step = 3,
            totalSteps = 3,
            onClick = {
                val finalDraft = viewModel.onboardingDraft.copy(lookingFor = lookingFor, preferences = preferences)
                viewModel.saveProfile(finalDraft)
            },
            modifier = Modifier.align(Alignment.BottomCenter)
        )
    }

    // Navigate to main when profile saved
    LaunchedEffect(uiState.isAuthenticated) {
        if (uiState.isAuthenticated && !uiState.needsProfile) onFinish()
    }
}
