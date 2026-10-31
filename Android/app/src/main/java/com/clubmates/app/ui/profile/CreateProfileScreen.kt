package com.clubmates.app.ui.profile

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.border
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Cake
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Height
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.graphics.Color
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.graphics.Brush
import com.clubmates.app.domain.model.UserProfile
import com.clubmates.app.ui.auth.AuthViewModel
import com.clubmates.app.ui.components.ClubMatesTextField
import com.clubmates.app.ui.theme.*

private val CREATE_PROFESSION_OPTIONS = listOf(
    "Student", "Engineer", "Doctor", "Designer", "Artist", "Chef", "Teacher",
    "Lawyer", "Entrepreneur", "Nurse", "Architect", "Photographer", "Writer",
    "Musician", "Athlete", "Marketing", "Finance", "Scientist", "Developer", "Other"
)
private val CREATE_GENDER_OPTIONS = listOf("Male", "Female", "Non-binary")

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun CreateProfileScreen(
    viewModel: AuthViewModel,
    onProfileCreated: () -> Unit
) {
    val uiState by viewModel.uiState.collectAsState()
    var name by remember { mutableStateOf("") }
    var age by remember { mutableFloatStateOf(21f) }
    var bio by remember { mutableStateOf("") }
    var profession by remember { mutableStateOf("Student") }
    var gender by remember { mutableStateOf("Male") }
    var height by remember { mutableFloatStateOf(170f) }
    var prompts by remember { mutableStateOf(listOf<UserProfile.Prompt>()) }
    var interests by remember { mutableStateOf(setOf<String>()) }
    var showInterestPicker by remember { mutableStateOf(false) }
    var editingPromptIndex by remember { mutableStateOf<Int?>(null) }
    val createPink = Color(0xFFFF6B9D)

    LaunchedEffect(uiState.isAuthenticated, uiState.needsProfile) {
        if (uiState.isAuthenticated && !uiState.needsProfile) onProfileCreated()
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Background)
            .imePadding()
    ) {
        Column(
            modifier = Modifier
                .weight(1f)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp, vertical = 24.dp),
            verticalArrangement = Arrangement.spacedBy(22.dp)
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(
                    "Create your profile",
                    fontSize = 30.sp,
                    fontWeight = FontWeight.Bold,
                    color = TextPrimary
                )
                Text(
                    "Finish the basics to unlock the app. Name, age, and bio are required. The rest helps your profile feel complete on day one.",
                    fontSize = 14.sp,
                    color = TextSecondary,
                    lineHeight = 20.sp
                )
            }

            Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                CreateProfileSectionLabel("About")
                ClubMatesTextField(value = name, onValueChange = { name = it }, label = "Name", accentColor = createPink)

                // Age slider
                CreateSliderCard(
                    icon = Icons.Default.Cake,
                    label = "Age",
                    valueText = "${age.toInt()}",
                    subText = null,
                    minLabel = "18",
                    maxLabel = "60",
                    value = age,
                    onValueChange = { age = it },
                    valueRange = 18f..60f,
                    steps = 41,
                    accentColor = createPink
                )

                ClubMatesTextField(
                    value = bio,
                    onValueChange = { bio = it.take(150) },
                    label = "Bio (${bio.length}/150)",
                    singleLine = false,
                    maxLines = 4,
                    accentColor = createPink
                )

                // Profession dropdown
                CreateProfileSectionLabel("Profession")
                CreateProfileDropdown(
                    label = "Profession",
                    selected = profession,
                    options = CREATE_PROFESSION_OPTIONS,
                    accentColor = createPink,
                    onSelect = { profession = it }
                )

                // Gender dropdown
                CreateProfileSectionLabel("Gender")
                CreateProfileDropdown(
                    label = "Gender",
                    selected = gender,
                    options = CREATE_GENDER_OPTIONS,
                    accentColor = createPink,
                    onSelect = { gender = it }
                )

                // Height slider
                CreateProfileSectionLabel("Height")
                CreateSliderCard(
                    icon = Icons.Default.Height,
                    label = "Height",
                    valueText = "${height.toInt()} cm",
                    subText = createCmToFeetInches(height.toInt()),
                    minLabel = "140 cm",
                    maxLabel = "220 cm",
                    value = height,
                    onValueChange = { height = it },
                    valueRange = 140f..220f,
                    steps = 79,
                    accentColor = createPink
                )
            }

            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    CreateProfileSectionLabel("Interests")
                    TextButton(onClick = { showInterestPicker = true }) {
                        Text("Edit", color = Primary)
                    }
                }

                if (interests.isEmpty()) {
                    Text(
                        "Add a few interests so people can start with something real.",
                        fontSize = 14.sp,
                        color = TextSecondary
                    )
                } else {
                    FlowRow(
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        interests.forEach { interest ->
                            Box(
                                modifier = Modifier
                                    .background(SurfaceVariant, RoundedCornerShape(20.dp))
                                    .padding(horizontal = 12.dp, vertical = 7.dp)
                            ) {
                                Text(interest, color = TextPrimary, fontSize = 13.sp)
                            }
                        }
                    }
                }
            }

            Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    CreateProfileSectionLabel("Get to Know Me")
                    if (prompts.size < 3) {
                        TextButton(onClick = {
                            val newPrompt = UserProfile.Prompt(question = PROMPT_QUESTIONS.first(), answer = "")
                            prompts = prompts + newPrompt
                            editingPromptIndex = prompts.size - 1
                        }) {
                            Icon(Icons.Default.Add, contentDescription = null, tint = createPink, modifier = Modifier.size(14.dp))
                            Spacer(modifier = Modifier.width(4.dp))
                            Text("Add", color = createPink)
                        }
                    }
                }

                if (prompts.isEmpty()) {
                    Text(
                        "Add up to three prompts to give matches an easy opener.",
                        fontSize = 14.sp,
                        color = TextSecondary
                    )
                } else {
                    prompts.forEachIndexed { index, prompt ->
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .background(CardBackground, RoundedCornerShape(16.dp))
                                .border(1.dp, createPink.copy(alpha = 0.12f), RoundedCornerShape(16.dp))
                                .padding(18.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            Text(
                                prompt.question.uppercase().ifBlank { "TAP TO CHOOSE QUESTION" },
                                fontSize = 12.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = createPink,
                                letterSpacing = 0.5.sp
                            )
                            Text(
                                prompt.answer.ifBlank { "Tap to answer..." },
                                fontSize = 16.sp,
                                fontWeight = FontWeight.Medium,
                                color = if (prompt.answer.isBlank()) TextHint else TextPrimary
                            )
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.End
                            ) {
                                IconButton(
                                    onClick = { editingPromptIndex = index },
                                    modifier = Modifier.size(32.dp)
                                ) {
                                    Icon(Icons.Default.Edit, contentDescription = "Edit", tint = TextHint, modifier = Modifier.size(16.dp))
                                }
                                IconButton(
                                    onClick = { prompts = prompts.toMutableList().also { it.removeAt(index) } },
                                    modifier = Modifier.size(32.dp)
                                ) {
                                    Icon(Icons.Default.Delete, contentDescription = "Remove", tint = Nope.copy(alpha = 0.8f), modifier = Modifier.size(16.dp))
                                }
                            }
                        }
                    }
                }
            }

            uiState.error?.let {
                Text(it, color = MaterialTheme.colorScheme.error, fontSize = 14.sp)
            }
        }

        Button(
            onClick = {
                val profile = UserProfile(
                    id = "",
                    name = name.trim(),
                    age = age.toInt(),
                    bio = bio.trim(),
                    profession = profession,
                    gender = gender,
                    height = height.toInt(),
                    interests = interests.toList(),
                    prompts = prompts.map {
                        it.copy(
                            question = it.question.trim(),
                            answer = it.answer.trim()
                        )
                    }.filter { it.question.isNotBlank() || it.answer.isNotBlank() },
                    photos = emptyList(),
                    isVerified = false
                )
                viewModel.saveProfile(profile)
            },
            enabled = canSubmitCreateProfile(
                name = name,
                bio = bio,
                isLoading = uiState.isLoading
            ),
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp, vertical = 16.dp)
                .height(56.dp),
            shape = RoundedCornerShape(18.dp),
            colors = ButtonDefaults.buttonColors(containerColor = Primary)
        ) {
            if (uiState.isLoading) {
                CircularProgressIndicator(
                    color = TextPrimary,
                    strokeWidth = 2.dp,
                    modifier = Modifier.size(22.dp)
                )
            } else {
                Text("Continue", fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
            }
        }
    }

    if (showInterestPicker) {
        InterestPickerSheet(
            selected = interests,
            onDismiss = { showInterestPicker = false },
            onConfirm = { selected ->
                interests = selected
                showInterestPicker = false
            }
        )
    }

    editingPromptIndex?.let { idx ->
        val prompt = prompts.getOrNull(idx) ?: UserProfile.Prompt(question = PROMPT_QUESTIONS.first(), answer = "")
        PromptEditorSheet(
            prompt = prompt,
            onDismiss = { editingPromptIndex = null },
            onSave = { updated ->
                prompts = prompts.toMutableList().also { list ->
                    if (idx < list.size) list[idx] = updated else list.add(updated)
                }
                editingPromptIndex = null
            }
        )
    }
}

@Composable
private fun CreateSliderCard(
    icon: ImageVector,
    label: String,
    valueText: String,
    subText: String?,
    minLabel: String,
    maxLabel: String,
    value: Float,
    onValueChange: (Float) -> Unit,
    valueRange: ClosedFloatingPointRange<Float>,
    steps: Int,
    accentColor: Color
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(CardBackground, RoundedCornerShape(16.dp))
            .border(1.dp, accentColor.copy(alpha = 0.12f), RoundedCornerShape(16.dp))
            .padding(horizontal = 16.dp)
            .padding(top = 14.dp, bottom = 10.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Box(
                    modifier = Modifier
                        .size(30.dp)
                        .background(accentColor.copy(alpha = 0.12f), CircleShape),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(icon, contentDescription = null, tint = accentColor, modifier = Modifier.size(15.dp))
                }
                Text(label, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = TextPrimary)
            }
            Row(
                modifier = Modifier
                    .background(accentColor.copy(alpha = 0.1f), RoundedCornerShape(50))
                    .border(1.dp, accentColor.copy(alpha = 0.25f), RoundedCornerShape(50))
                    .padding(horizontal = 12.dp, vertical = 5.dp),
                horizontalArrangement = Arrangement.spacedBy(4.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(valueText, fontSize = 15.sp, fontWeight = FontWeight.Bold, color = accentColor)
                if (subText != null) {
                    Text("· $subText", fontSize = 12.sp, color = TextSecondary)
                }
            }
        }

        Slider(
            value = value,
            onValueChange = onValueChange,
            valueRange = valueRange,
            steps = steps,
            modifier = Modifier.fillMaxWidth(),
            colors = SliderDefaults.colors(
                thumbColor = accentColor,
                activeTrackColor = accentColor,
                inactiveTrackColor = Surface
            )
        )

        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(minLabel, fontSize = 11.sp, color = TextHint)
            Text(maxLabel, fontSize = 11.sp, color = TextHint)
        }
    }
}

@Composable
private fun CreateProfileSectionLabel(label: String) {
    Text(label, fontSize = 13.sp, color = TextHint, fontWeight = FontWeight.Medium)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CreateProfileDropdown(
    label: String,
    selected: String,
    options: List<String>,
    accentColor: Color,
    onSelect: (String) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }
    ExposedDropdownMenuBox(expanded = expanded, onExpandedChange = { expanded = it }) {
        OutlinedTextField(
            value = selected,
            onValueChange = {},
            readOnly = true,
            label = { Text(label, color = TextHint) },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
            modifier = Modifier.fillMaxWidth().menuAnchor(),
            colors = OutlinedTextFieldDefaults.colors(
                focusedBorderColor = accentColor,
                unfocusedBorderColor = Surface,
                focusedTextColor = TextPrimary,
                unfocusedTextColor = TextPrimary,
                focusedContainerColor = CardBackground,
                unfocusedContainerColor = CardBackground
            )
        )
        ExposedDropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false },
            modifier = Modifier.background(CardBackground)
        ) {
            options.forEach { option ->
                DropdownMenuItem(
                    text = { Text(option, color = if (option == selected) accentColor else TextPrimary, fontSize = 14.sp) },
                    onClick = { onSelect(option); expanded = false }
                )
            }
        }
    }
}

private fun createCmToFeetInches(cm: Int): String {
    val totalInches = (cm / 2.54).toInt()
    val feet = totalInches / 12
    val inches = totalInches % 12
    return "$feet'$inches\""
}

private fun canSubmitCreateProfile(
    name: String,
    bio: String,
    isLoading: Boolean
): Boolean {
    return !isLoading &&
        name.trim().isNotEmpty() &&
        bio.trim().isNotEmpty()
}
