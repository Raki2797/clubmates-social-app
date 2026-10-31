package com.clubmates.app.ui.profile

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.clubmates.app.domain.model.UserProfile
import com.clubmates.app.ui.auth.AuthViewModel
import com.clubmates.app.ui.theme.*

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun OnboardingVibeScreen(
    viewModel: AuthViewModel,
    onBack: () -> Unit,
    onNext: () -> Unit
) {
    val uiState by viewModel.uiState.collectAsState()
    val draft = viewModel.onboardingDraft

    var prompts by remember { mutableStateOf(draft.prompts.toMutableList()) }
    var interests by remember { mutableStateOf(draft.interests.toMutableList()) }
    var editingPromptIndex by remember { mutableStateOf<Int?>(null) }
    var showInterestPicker by remember { mutableStateOf(false) }

    val pink = Color(0xFFFF6B9D)
    val purple = Color(0xFFC44EFF)

    Box(modifier = Modifier.fillMaxSize().background(Background)) {
        Column(modifier = Modifier.fillMaxSize()) {
            OnboardingHeader(step = 2, totalSteps = 3, onBack = onBack)

            Column(
                modifier = Modifier
                    .weight(1f)
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 20.dp),
                verticalArrangement = Arrangement.spacedBy(24.dp)
            ) {
                Spacer(modifier = Modifier.height(8.dp))

                // Intro card
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(CardBackground, RoundedCornerShape(18.dp))
                        .border(1.dp, purple.copy(alpha = 0.2f), RoundedCornerShape(18.dp))
                        .padding(18.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Text("Show your vibe", fontSize = 22.sp, fontWeight = FontWeight.Black, color = TextPrimary)
                    Text("Prompts and interests help people start a conversation with you.", fontSize = 14.sp, color = TextSecondary, lineHeight = 20.sp)
                }

                // Prompts section
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                        Text("GET TO KNOW ME", fontSize = 11.sp, fontWeight = FontWeight.Bold, color = TextHint, letterSpacing = 1.sp)
                        if (prompts.size < 3) {
                            TextButton(onClick = { prompts = prompts.toMutableList().also { it.add(UserProfile.Prompt(question = PROMPT_QUESTIONS.first(), answer = "")) }; editingPromptIndex = prompts.size - 1 }, contentPadding = PaddingValues(0.dp)) {
                                Icon(Icons.Default.Add, contentDescription = null, tint = pink, modifier = Modifier.size(14.dp))
                                Spacer(modifier = Modifier.width(4.dp))
                                Text("Add", color = pink, fontWeight = FontWeight.SemiBold, fontSize = 13.sp)
                            }
                        }
                    }
                    if (prompts.isEmpty()) {
                        Text("Add up to 3 prompts so people can see your personality.", fontSize = 14.sp, color = TextSecondary)
                    }
                    prompts.forEachIndexed { index, prompt ->
                        Column(
                            modifier = Modifier.fillMaxWidth().background(CardBackground, RoundedCornerShape(16.dp)).border(1.dp, pink.copy(alpha = 0.12f), RoundedCornerShape(16.dp)).padding(16.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            Text(prompt.question.uppercase().ifBlank { "TAP EDIT TO CHOOSE QUESTION" }, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = pink, letterSpacing = 0.6.sp)
                            Text(prompt.answer.ifBlank { "Tap to answer..." }, fontSize = 15.sp, color = if (prompt.answer.isBlank()) TextHint else TextPrimary)
                            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                                IconButton(onClick = { editingPromptIndex = index }, modifier = Modifier.size(32.dp)) {
                                    Icon(Icons.Default.Edit, contentDescription = "Edit", tint = TextHint, modifier = Modifier.size(14.dp))
                                }
                                IconButton(onClick = { prompts = prompts.toMutableList().also { it.removeAt(index) } }, modifier = Modifier.size(32.dp)) {
                                    Icon(Icons.Default.Delete, contentDescription = "Delete", tint = Nope.copy(alpha = 0.7f), modifier = Modifier.size(14.dp))
                                }
                            }
                        }
                    }
                }

                // Interests section
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                        Text("INTERESTS", fontSize = 11.sp, fontWeight = FontWeight.Bold, color = TextHint, letterSpacing = 1.sp)
                        TextButton(onClick = { showInterestPicker = true }, contentPadding = PaddingValues(0.dp)) {
                            Icon(Icons.Default.Edit, contentDescription = null, tint = pink, modifier = Modifier.size(12.dp))
                            Spacer(modifier = Modifier.width(4.dp))
                            Text("Edit", color = pink, fontWeight = FontWeight.SemiBold, fontSize = 13.sp)
                        }
                    }
                    if (interests.isEmpty()) {
                        Text("Add interests to find people who share your passions.", fontSize = 14.sp, color = TextSecondary)
                    } else {
                        androidx.compose.foundation.layout.FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            interests.forEach { interest ->
                                val (c1, c2) = interestGradientPair(interest)
                                Box(
                                    modifier = Modifier.background(SurfaceVariant, RoundedCornerShape(50)).border(1.dp, c1.copy(alpha = 0.3f), RoundedCornerShape(50)).padding(horizontal = 12.dp, vertical = 7.dp)
                                ) {
                                    Text(interest, fontSize = 13.sp, fontWeight = FontWeight.Medium,
                                        style = androidx.compose.ui.text.TextStyle(brush = Brush.linearGradient(listOf(c1, c2))))
                                }
                            }
                        }
                    }
                }

                uiState.error?.let { Text(it, color = MaterialTheme.colorScheme.error, fontSize = 14.sp) }
                Spacer(modifier = Modifier.height(100.dp))
            }
        }

        OnboardingBottomBar(
            label = "Next: Preferences →",
            enabled = true,
            isLoading = false,
            step = 2,
            totalSteps = 3,
            onClick = {
                viewModel.updateOnboardingDraft(viewModel.onboardingDraft.copy(prompts = prompts.toList(), interests = interests.toList()))
                onNext()
            },
            modifier = Modifier.align(Alignment.BottomCenter)
        )
    }

    if (showInterestPicker) {
        InterestPickerSheet(selected = interests.toSet(), onDismiss = { showInterestPicker = false }, onConfirm = { selected -> interests = selected.toMutableList(); showInterestPicker = false })
    }

    editingPromptIndex?.let { idx ->
        val prompt = prompts.getOrNull(idx) ?: UserProfile.Prompt(question = PROMPT_QUESTIONS.first(), answer = "")
        PromptEditorSheet(prompt = prompt, onDismiss = { editingPromptIndex = null }, onSave = { updated ->
            prompts = prompts.toMutableList().also { list -> if (idx < list.size) list[idx] = updated else list.add(updated) }
            editingPromptIndex = null
        })
    }
}

private fun interestGradientPair(interest: String): Pair<Color, Color> {
    val pairs = listOf(
        Color(0xFFFF6B9D) to Color(0xFFC44EFF),
        Color(0xFF00C8FF) to Color(0xFF0072FF),
        Color(0xFFFF8C42) to Color(0xFFFF3CAC),
        Color(0xFF00E5A0) to Color(0xFF00A6FF),
        Color(0xFFFFB800) to Color(0xFFFF6B9D),
    )
    return pairs[kotlin.math.abs(interest.hashCode()) % pairs.size]
}
