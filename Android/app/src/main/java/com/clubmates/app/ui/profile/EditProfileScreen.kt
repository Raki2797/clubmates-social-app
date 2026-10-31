package com.clubmates.app.ui.profile

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.clubmates.app.domain.model.ProfilePhoto
import com.clubmates.app.domain.model.UserProfile
import com.clubmates.app.ui.theme.*

internal val PROFESSION_OPTIONS = listOf(
    "Student", "Engineer", "Doctor", "Designer", "Artist", "Chef", "Teacher",
    "Lawyer", "Entrepreneur", "Nurse", "Architect", "Photographer", "Writer",
    "Musician", "Athlete", "Marketing", "Finance", "Scientist", "Developer", "Other"
)
internal val GENDER_OPTIONS = listOf("Male", "Female", "Non-binary")

private val editPink = Color(0xFFFF6B9D)
private val editPurple = Color(0xFFC44EFF)
private val editGradient = Brush.linearGradient(listOf(editPink, editPurple))
private const val MAX_PHOTOS = 6

@OptIn(ExperimentalLayoutApi::class, ExperimentalMaterial3Api::class)
@Composable
fun EditProfileScreen(
    profile: UserProfile,
    viewModel: ProfileViewModel,
    onBack: () -> Unit
) {
    val uiState by viewModel.uiState.collectAsState()
    var name by remember { mutableStateOf(profile.name) }
    var age by remember { mutableFloatStateOf(profile.age.coerceIn(18, 60).toFloat()) }
    var bio by remember { mutableStateOf(profile.bio) }
    var profession by remember { mutableStateOf(profile.profession.ifBlank { "Student" }) }
    var gender by remember { mutableStateOf(profile.gender.ifBlank { "Male" }) }
    var height by remember { mutableFloatStateOf(profile.height.coerceIn(140, 220).toFloat()) }
    var photos by remember { mutableStateOf(profile.photos.toMutableList()) }
    var prompts by remember { mutableStateOf(profile.prompts.toMutableList()) }
    var showInterestPicker by remember { mutableStateOf(false) }
    var interests by remember { mutableStateOf(profile.interests.toMutableList()) }
    var editingPromptIndex by remember { mutableStateOf<Int?>(null) }
    var replacingPhotoIndex by remember { mutableStateOf<Int?>(null) }
    var lookingFor by remember { mutableStateOf(profile.lookingFor) }
    var preferences by remember { mutableStateOf(profile.preferences) }
    var isGhostMode by remember { mutableStateOf(profile.isGhostMode) }
    var showPreferences by remember { mutableStateOf(false) }

    LaunchedEffect(uiState.saveSuccess) {
        if (uiState.saveSuccess) {
            viewModel.clearSaveSuccess()
            onBack()
        }
    }

    // Photo picker launcher — replaces or appends
    val photoPickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.GetContent()
    ) { uri: Uri? ->
        if (uri != null) {
            val newPhoto = ProfilePhoto(localUri = uri)
            val idx = replacingPhotoIndex
            photos = if (idx != null && idx < photos.size) {
                photos.toMutableList().also { it[idx] = newPhoto }
            } else {
                photos.toMutableList().also { it.add(newPhoto) }
            }
            replacingPhotoIndex = null
        }
    }

    Column(modifier = Modifier.fillMaxSize().background(Background)) {
        // Top bar
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            TextButton(onClick = onBack) {
                Text("Cancel", color = TextSecondary, fontSize = 16.sp)
            }
            Text("Edit Profile", fontSize = 18.sp, fontWeight = FontWeight.SemiBold, color = TextPrimary)
            TextButton(
                onClick = {
                    val updated = profile.copy(
                        name = name, age = age.toInt(),
                        bio = bio, profession = profession, gender = gender,
                        height = height.toInt(), interests = interests.toList(),
                        prompts = prompts.filter { it.answer.trim().isNotBlank() },
                        photos = photos.toList(),
                        lookingFor = lookingFor,
                        preferences = preferences,
                        isGhostMode = isGhostMode,
                        notificationPreferences = profile.notificationPreferences
                    )
                    viewModel.saveProfile(updated)
                },
                enabled = !uiState.isSaving
            ) {
                if (uiState.isSaving) {
                    CircularProgressIndicator(color = editPink, strokeWidth = 2.dp, modifier = Modifier.size(20.dp))
                } else {
                    Text("Save", color = editPink, fontWeight = FontWeight.SemiBold)
                }
            }
        }

        HorizontalDivider(color = SurfaceVariant)

        Column(
            modifier = Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp),
            verticalArrangement = Arrangement.spacedBy(24.dp)
        ) {
            Spacer(modifier = Modifier.height(4.dp))

            // ── Mismatch banner — shown when verification flagged photos ────
            val mismatchedIds = profile.verificationMismatchedPhotoIds.toSet()
            val flaggedCount = photos.count { it.id in mismatchedIds }
            if (flaggedCount > 0) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(Color(0xFFFFB800).copy(alpha = 0.12f), RoundedCornerShape(12.dp))
                        .border(1.dp, Color(0xFFFFB800).copy(alpha = 0.5f), RoundedCornerShape(12.dp))
                        .padding(horizontal = 14.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    Icon(Icons.Default.Warning, null, tint = Color(0xFFB45309), modifier = Modifier.size(18.dp))
                    Text(
                        if (flaggedCount == 1) "1 photo didn't match your selfie. Replace it to re-verify."
                        else "$flaggedCount photos didn't match your selfie. Replace them to re-verify.",
                        fontSize = 13.sp,
                        color = Color(0xFF92400E),
                        lineHeight = 18.sp,
                        modifier = Modifier.weight(1f)
                    )
                }
            }

            // ── Photos ───────────────────────────────────────────────────────
            Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text("Photos", fontSize = 18.sp, fontWeight = FontWeight.SemiBold, color = TextPrimary)
                    Text(
                        "${photos.size}/$MAX_PHOTOS",
                        fontSize = 13.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = TextSecondary
                    )
                }

                // 3-column grid — 2 rows × 3 columns = 6 slots
                val rows = (0 until MAX_PHOTOS).chunked(3)
                rows.forEach { rowIndices ->
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        rowIndices.forEach { index ->
                            Box(modifier = Modifier.weight(1f)) {
                                PhotoSlot(
                                    index = index,
                                    photos = photos,
                                    onFillSlot = {
                                        replacingPhotoIndex = if (index < photos.size) index else null
                                        photoPickerLauncher.launch("image/*")
                                    },
                                    onRemove = {
                                        val list = photos.toMutableList().also { it.removeAt(index) }
                                        photos = list
                                        val newOrder = list.map { it.id }
                                        if (newOrder.isNotEmpty()) viewModel.reorderPhotos(newOrder)
                                    },
                                    onMoveLeft = if (index > 0 && index < photos.size) ({
                                        val list = photos.toMutableList()
                                        val tmp = list[index]; list[index] = list[index - 1]; list[index - 1] = tmp
                                        photos = list
                                        viewModel.reorderPhotos(list.map { it.id })
                                    }) else null,
                                    onMoveRight = if (index < photos.size - 1) ({
                                        val list = photos.toMutableList()
                                        val tmp = list[index]; list[index] = list[index + 1]; list[index + 1] = tmp
                                        photos = list
                                        viewModel.reorderPhotos(list.map { it.id })
                                    }) else null,
                                    // Show uploading overlay when saving and this photo has localUri (not yet uploaded)
                                    isUploading = uiState.isSaving && index < photos.size && photos[index].localUri != null,
                                    hasFailed = uiState.failedPhotoIndex == index,
                                    onRetry = { viewModel.saveProfile(profile.copy(photos = photos.toList())) },
                                    isMismatched = index < photos.size && photos[index].id in mismatchedIds
                                )
                            }
                        }
                    }
                }

                Text(
                    "Your first photo is the main one. Tap a filled slot to replace it, tap + to add, or × to remove.",
                    fontSize = 12.sp,
                    color = TextHint,
                    lineHeight = 16.sp
                )
            }

            // ── Basic Info ───────────────────────────────────────────────────
            Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                SectionLabel("About")
                BasicInfoTextRow(
                    label = "Name",
                    value = name,
                    placeholder = "Your name",
                    onValueChange = { name = it }
                )

                SliderCard(
                    icon = Icons.Default.Cake,
                    label = "Age",
                    valueText = "${age.toInt()}",
                    subText = null,
                    minLabel = "18",
                    maxLabel = "60",
                    value = age,
                    onValueChange = { age = it },
                    valueRange = 18f..60f,
                    steps = 41
                )

                BasicInfoMenuRow(
                    label = "Profession",
                    selected = profession,
                    options = PROFESSION_OPTIONS,
                    onSelect = { profession = it }
                )

                BasicInfoMenuRow(
                    label = "Gender",
                    selected = gender,
                    options = GENDER_OPTIONS,
                    onSelect = { gender = it }
                )

                SliderCard(
                    icon = Icons.Default.Straighten,
                    label = "Height",
                    valueText = "${height.toInt()} cm",
                    subText = cmToFeetInches(height.toInt()),
                    minLabel = "140 cm",
                    maxLabel = "220 cm",
                    value = height,
                    onValueChange = { height = it },
                    valueRange = 140f..220f,
                    steps = 79
                )

                BioEditorCard(
                    bio = bio,
                    onBioChange = { bio = it.take(150) }
                )
            }

            // ── Prompts ──────────────────────────────────────────────────────
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    SectionLabel("Get to Know Me")
                    if (prompts.size < 3) {
                        TextButton(
                            onClick = {
                                val newPrompt = UserProfile.Prompt(question = PROMPT_QUESTIONS.first(), answer = "")
                                prompts = prompts.toMutableList().also { it.add(newPrompt) }
                                editingPromptIndex = prompts.size - 1
                            },
                            contentPadding = PaddingValues(horizontal = 0.dp)
                        ) {
                            Icon(Icons.Default.Add, contentDescription = null, tint = editPink, modifier = Modifier.size(14.dp))
                            Spacer(modifier = Modifier.width(4.dp))
                            Text("Add", color = editPink, fontWeight = FontWeight.SemiBold, fontSize = 13.sp)
                        }
                    }
                }

                prompts.forEachIndexed { index, prompt ->
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .background(CardBackground, RoundedCornerShape(16.dp))
                            .border(1.dp, editPink.copy(alpha = 0.12f), RoundedCornerShape(16.dp))
                            .padding(18.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Text(
                            prompt.question.uppercase().ifBlank { "TAP TO CHOOSE QUESTION" },
                            fontSize = 11.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = editPink,
                            letterSpacing = 0.6.sp
                        )
                        Text(
                            prompt.answer.ifBlank { "Tap to answer..." },
                            fontSize = 16.sp,
                            fontWeight = FontWeight.Medium,
                            color = if (prompt.answer.isBlank()) TextHint else TextPrimary
                        )
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.End,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            IconButton(onClick = { editingPromptIndex = index }, modifier = Modifier.size(32.dp)) {
                                Icon(Icons.Default.Edit, contentDescription = "Edit", tint = TextHint, modifier = Modifier.size(16.dp))
                            }
                            IconButton(
                                onClick = { prompts = prompts.toMutableList().also { it.removeAt(index) } },
                                modifier = Modifier.size(32.dp)
                            ) {
                                Icon(Icons.Default.Delete, contentDescription = "Delete", tint = Nope.copy(alpha = 0.8f), modifier = Modifier.size(16.dp))
                            }
                        }
                    }
                }
            }

            // ── Interests ────────────────────────────────────────────────────
            Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    SectionLabel("Interests")
                    TextButton(
                        onClick = { showInterestPicker = true },
                        contentPadding = PaddingValues(horizontal = 0.dp)
                    ) {
                        Icon(Icons.Default.Edit, contentDescription = null, modifier = Modifier.size(12.dp), tint = editPink)
                        Spacer(modifier = Modifier.width(4.dp))
                        Text("Edit", color = editPink, fontWeight = FontWeight.SemiBold, fontSize = 13.sp)
                    }
                }

                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    interests.forEach { interest ->
                        Row(
                            modifier = Modifier
                                .background(Surface, RoundedCornerShape(50))
                                .padding(horizontal = 12.dp, vertical = 7.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(4.dp)
                        ) {
                            Text(interest, color = TextPrimary, fontSize = 13.sp, fontWeight = FontWeight.Medium)
                            Icon(
                                Icons.Default.Close,
                                contentDescription = "Remove",
                                tint = TextPrimary,
                                modifier = Modifier
                                    .size(12.dp)
                                    .clickable { interests = interests.toMutableList().also { it.remove(interest) } }
                            )
                        }
                    }
                }
            }

            PreferencesLinkCard(
                lookingFor = lookingFor,
                preferences = preferences,
                onClick = { showPreferences = true }
            )

            uiState.error?.let { Text(it, color = MaterialTheme.colorScheme.error, fontSize = 14.sp) }

            Spacer(modifier = Modifier.height(32.dp))
        }
    }

    if (showInterestPicker) {
        InterestPickerSheet(
            selected = interests.toSet(),
            onDismiss = { showInterestPicker = false },
            onConfirm = { selected -> interests = selected.toMutableList(); showInterestPicker = false }
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

    if (showPreferences) {
        ModalBottomSheet(
            onDismissRequest = { showPreferences = false },
            containerColor = Background
        ) {
            EditPreferencesSheet(
                lookingFor = lookingFor,
                preferences = preferences,
                isGhostMode = isGhostMode,
                onLookingForChange = { lookingFor = it },
                onPreferencesChange = { preferences = it },
                onGhostModeChange = { isGhostMode = it },
                onDone = { showPreferences = false }
            )
        }
    }
}

@Composable
private fun BasicInfoTextRow(
    label: String,
    value: String,
    placeholder: String,
    onValueChange: (String) -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(CardBackground, RoundedCornerShape(16.dp))
            .border(1.dp, editPink.copy(alpha = 0.12f), RoundedCornerShape(16.dp))
            .padding(horizontal = 16.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            label,
            color = TextSecondary,
            fontSize = 15.sp,
            modifier = Modifier.width(80.dp)
        )
        TextField(
            value = value,
            onValueChange = onValueChange,
            singleLine = true,
            placeholder = {
                Text(
                    placeholder,
                    color = TextHint,
                    fontSize = 15.sp,
                    textAlign = TextAlign.End,
                    modifier = Modifier.fillMaxWidth()
                )
            },
            textStyle = LocalTextStyle.current.copy(
                color = TextPrimary,
                fontSize = 15.sp,
                textAlign = TextAlign.End
            ),
            colors = TextFieldDefaults.colors(
                focusedContainerColor = Color.Transparent,
                unfocusedContainerColor = Color.Transparent,
                disabledContainerColor = Color.Transparent,
                focusedIndicatorColor = Color.Transparent,
                unfocusedIndicatorColor = Color.Transparent,
                disabledIndicatorColor = Color.Transparent,
                cursorColor = editPink
            ),
            modifier = Modifier.weight(1f)
        )
    }
}

@Composable
private fun BasicInfoMenuRow(
    label: String,
    selected: String,
    options: List<String>,
    onSelect: (String) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .background(CardBackground, RoundedCornerShape(16.dp))
                .border(1.dp, editPink.copy(alpha = 0.12f), RoundedCornerShape(16.dp))
                .clickable { expanded = true }
                .padding(horizontal = 16.dp, vertical = 16.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                label,
                color = TextSecondary,
                fontSize = 15.sp,
                modifier = Modifier.width(80.dp)
            )
            Spacer(modifier = Modifier.weight(1f))
            Text(
                selected,
                color = editPink,
                fontSize = 15.sp,
                textAlign = TextAlign.End
            )
            Spacer(modifier = Modifier.width(8.dp))
            Icon(
                Icons.Default.KeyboardArrowDown,
                contentDescription = null,
                tint = TextHint,
                modifier = Modifier.size(18.dp)
            )
        }

        DropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false },
            modifier = Modifier.background(CardBackground)
        ) {
            options.forEach { option ->
                DropdownMenuItem(
                    text = {
                        Text(
                            option,
                            color = if (option == selected) editPink else TextPrimary,
                            fontSize = 14.sp
                        )
                    },
                    onClick = {
                        onSelect(option)
                        expanded = false
                    }
                )
            }
        }
    }
}

@Composable
private fun BioEditorCard(
    bio: String,
    onBioChange: (String) -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .background(CardBackground, RoundedCornerShape(16.dp))
                .border(1.dp, editPink.copy(alpha = 0.12f), RoundedCornerShape(16.dp))
        ) {
            Column(
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                Text(
                    "Bio",
                    color = editPink,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold,
                    letterSpacing = 0.4.sp
                )
                TextField(
                    value = bio,
                    onValueChange = onBioChange,
                    minLines = 5,
                    maxLines = 6,
                    placeholder = {
                        Text(
                            "Write something about yourself...",
                            color = TextHint,
                            fontSize = 15.sp
                        )
                    },
                    textStyle = LocalTextStyle.current.copy(
                        color = TextPrimary,
                        fontSize = 15.sp
                    ),
                    colors = TextFieldDefaults.colors(
                        focusedContainerColor = Color.Transparent,
                        unfocusedContainerColor = Color.Transparent,
                        disabledContainerColor = Color.Transparent,
                        focusedIndicatorColor = Color.Transparent,
                        unfocusedIndicatorColor = Color.Transparent,
                        disabledIndicatorColor = Color.Transparent,
                        cursorColor = editPink
                    ),
                    modifier = Modifier.fillMaxWidth()
                )
            }
        }

        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
            Text(
                "${bio.length}/150",
                color = if (bio.length > 150) Nope else TextHint,
                fontSize = 11.sp
            )
        }
    }
}

@Composable
private fun PreferencesLinkCard(
    lookingFor: String,
    preferences: com.clubmates.app.domain.model.DatePreferences,
    onClick: () -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        SectionLabel("Dating Preferences")
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .background(CardBackground, RoundedCornerShape(16.dp))
                .border(1.dp, editPink.copy(alpha = 0.12f), RoundedCornerShape(16.dp))
                .clickable(onClick = onClick)
                .padding(horizontal = 16.dp, vertical = 14.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Box(
                modifier = Modifier
                    .size(30.dp)
                    .background(editPink.copy(alpha = 0.12f), CircleShape),
                contentAlignment = Alignment.Center
            ) {
                Icon(Icons.Default.Tune, contentDescription = null, tint = editPink, modifier = Modifier.size(15.dp))
            }
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text("Age, Height & Gender Filters", color = TextPrimary, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                Text(
                    buildList {
                        if (lookingFor.isNotBlank()) add(lookingFor)
                        add("Ages ${preferences.ageMin}-${preferences.ageMax}")
                        add(if (preferences.genders.isEmpty()) "Everyone" else preferences.genders.joinToString(", "))
                        if (preferences.verifiedOnly) add("Verified only")
                    }.joinToString(" · "),
                    color = TextSecondary,
                    fontSize = 12.sp,
                    maxLines = 1
                )
            }
            Icon(Icons.Default.ChevronRight, contentDescription = null, tint = TextHint, modifier = Modifier.size(16.dp))
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun EditPreferencesSheet(
    lookingFor: String,
    preferences: com.clubmates.app.domain.model.DatePreferences,
    isGhostMode: Boolean,
    onLookingForChange: (String) -> Unit,
    onPreferencesChange: (com.clubmates.app.domain.model.DatePreferences) -> Unit,
    onGhostModeChange: (Boolean) -> Unit,
    onDone: () -> Unit
) {
    val lookingForOptions = listOf("Dating", "Something Casual", "Friendship", "Open to Anything")
    val genderOptions = listOf("Men", "Women", "Non-binary", "Everyone")

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .navigationBarsPadding()
            .padding(horizontal = 20.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text("Dating Preferences", color = TextPrimary, fontSize = 20.sp, fontWeight = FontWeight.Bold)
            TextButton(onClick = onDone) {
                Text("Done", color = editPink, fontWeight = FontWeight.SemiBold)
            }
        }

        PreferenceSheetCard(icon = Icons.Default.Favorite, title = "Looking For") {
            FlowRow(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                lookingForOptions.forEach { option ->
                    val selected = lookingFor == option
                    PreferenceChip(
                        label = option,
                        selected = selected,
                        onClick = { onLookingForChange(if (selected) "" else option) }
                    )
                }
            }
        }

        PreferenceSheetCard(
            icon = Icons.Default.Cake,
            title = "Age Range",
            trailing = "${preferences.ageMin} – ${preferences.ageMax}"
        ) {
            RangeSlider(
                value = preferences.ageMin.toFloat()..preferences.ageMax.toFloat(),
                onValueChange = { range ->
                    onPreferencesChange(
                        preferences.copy(
                            ageMin = range.start.toInt().coerceIn(18, preferences.ageMax - 1),
                            ageMax = range.endInclusive.toInt().coerceIn(preferences.ageMin + 1, 60)
                        )
                    )
                },
                valueRange = 18f..60f,
                steps = 41,
                colors = SliderDefaults.colors(
                    thumbColor = editPink,
                    activeTrackColor = editPink,
                    inactiveTrackColor = Surface
                )
            )
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text("18", fontSize = 11.sp, color = TextHint)
                Text("60", fontSize = 11.sp, color = TextHint)
            }
        }

        PreferenceSheetCard(
            icon = Icons.Default.Straighten,
            title = "Height Range",
            trailing = "${preferences.heightMin} – ${preferences.heightMax} cm"
        ) {
            RangeSlider(
                value = preferences.heightMin.toFloat()..preferences.heightMax.toFloat(),
                onValueChange = { range ->
                    onPreferencesChange(
                        preferences.copy(
                            heightMin = range.start.toInt().coerceIn(140, preferences.heightMax - 1),
                            heightMax = range.endInclusive.toInt().coerceIn(preferences.heightMin + 1, 220)
                        )
                    )
                },
                valueRange = 140f..220f,
                steps = 79,
                colors = SliderDefaults.colors(
                    thumbColor = editPink,
                    activeTrackColor = editPink,
                    inactiveTrackColor = Surface
                )
            )
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text("140 cm", fontSize = 11.sp, color = TextHint)
                Text("220 cm", fontSize = 11.sp, color = TextHint)
            }
        }

        PreferenceSheetCard(icon = Icons.Default.People, title = "Show Me") {
            FlowRow(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                genderOptions.forEach { option ->
                    val selected = if (option == "Everyone") preferences.genders.isEmpty() else preferences.genders.contains(option)
                    PreferenceChip(
                        label = option,
                        selected = selected,
                        onClick = {
                            onPreferencesChange(
                                preferences.copy(
                                    genders = when {
                                        option == "Everyone" -> emptyList()
                                        preferences.genders.contains(option) -> preferences.genders - option
                                        else -> preferences.genders + option
                                    }
                                )
                            )
                        }
                    )
                }
            }
        }

        PreferenceToggleCard(
            icon = Icons.Default.CheckCircle,
            title = "Verified Profiles Only",
            subtitle = "Only show selfie-verified users",
            checked = preferences.verifiedOnly,
            onCheckedChange = { onPreferencesChange(preferences.copy(verifiedOnly = it)) }
        )

        PreferenceToggleCard(
            icon = Icons.Default.VisibilityOff,
            title = "Ghost Mode",
            subtitle = if (isGhostMode) "You're hidden from discovery" else "You appear in venue discovery",
            checked = isGhostMode,
            onCheckedChange = onGhostModeChange
        )

        Spacer(modifier = Modifier.height(12.dp))
    }
}

@Composable
private fun PreferenceSheetCard(
    icon: ImageVector,
    title: String,
    trailing: String? = null,
    content: @Composable ColumnScope.() -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(CardBackground, RoundedCornerShape(16.dp))
            .border(1.dp, editPink.copy(alpha = 0.12f), RoundedCornerShape(16.dp))
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
        content = {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Box(
                    modifier = Modifier
                        .size(30.dp)
                        .background(editPink.copy(alpha = 0.12f), CircleShape),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(icon, contentDescription = null, tint = editPink, modifier = Modifier.size(15.dp))
                }
                Text(title, color = TextPrimary, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                Spacer(modifier = Modifier.weight(1f))
                trailing?.let {
                    Text(
                        it,
                        color = editPink,
                        fontSize = 15.sp,
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier
                            .background(editPink.copy(alpha = 0.1f), RoundedCornerShape(50))
                            .border(1.dp, editPink.copy(alpha = 0.25f), RoundedCornerShape(50))
                            .padding(horizontal = 12.dp, vertical = 5.dp)
                    )
                }
            }
            content()
        }
    )
}

@Composable
private fun PreferenceChip(
    label: String,
    selected: Boolean,
    onClick: () -> Unit
) {
    Box(
        modifier = Modifier
            .background(
                if (selected) editGradient else Brush.linearGradient(listOf(Surface, Surface)),
                RoundedCornerShape(50)
            )
            .border(1.dp, if (selected) Color.Transparent else editPink.copy(alpha = 0.2f), RoundedCornerShape(50))
            .clickable(onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 8.dp)
    ) {
        Text(label, color = if (selected) Color.White else TextSecondary, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
private fun PreferenceToggleCard(
    icon: ImageVector,
    title: String,
    subtitle: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(CardBackground, RoundedCornerShape(16.dp))
            .border(1.dp, editPink.copy(alpha = 0.12f), RoundedCornerShape(16.dp))
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Box(
            modifier = Modifier
                .size(30.dp)
                .background(editPink.copy(alpha = 0.12f), CircleShape),
            contentAlignment = Alignment.Center
        ) {
            Icon(icon, contentDescription = null, tint = editPink, modifier = Modifier.size(15.dp))
        }
        Column(modifier = Modifier.weight(1f)) {
            Text(title, color = TextPrimary, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
            Text(subtitle, color = TextSecondary, fontSize = 12.sp)
        }
        Switch(
            checked = checked,
            onCheckedChange = onCheckedChange,
            colors = SwitchDefaults.colors(
                checkedThumbColor = editPink,
                checkedTrackColor = editPink.copy(alpha = 0.4f)
            )
        )
    }
}

@Composable
internal fun PhotoSlot(
    index: Int,
    photos: List<ProfilePhoto>,
    onFillSlot: () -> Unit,
    onRemove: () -> Unit,
    onMoveLeft: (() -> Unit)? = null,
    onMoveRight: (() -> Unit)? = null,
    isUploading: Boolean = false,
    hasFailed: Boolean = false,
    onRetry: (() -> Unit)? = null,
    isMismatched: Boolean = false
) {
    val aspectRatio = 1f
    val cornerRadius = 16.dp

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .aspectRatio(aspectRatio)
    ) {
        when {
            index < photos.size -> {
                // Filled slot
                val photo = photos[index]
                val photoModel = photo.localUri ?: photo.cdnUrl
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .clip(RoundedCornerShape(cornerRadius))
                        .background(CardBackground)
                        .then(
                            if (isMismatched) Modifier.border(2.dp, Color(0xFFFF4757), RoundedCornerShape(cornerRadius))
                            else Modifier
                        )
                        .clickable(onClick = onFillSlot)
                ) {
                    if (photoModel != null) {
                        AsyncImage(
                            model = photoModel,
                            contentDescription = "Photo ${index + 1}",
                            contentScale = ContentScale.Crop,
                            modifier = Modifier.fillMaxSize()
                        )
                    }
                    // Gradient scrim
                    Box(
                        modifier = Modifier.fillMaxSize().background(
                            Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.42f)))
                        )
                    )
                    // Label
                    Box(
                        modifier = Modifier.align(Alignment.BottomStart).padding(8.dp)
                    ) {
                        if (index == 0) {
                            Box(
                                modifier = Modifier
                                    .background(editGradient, RoundedCornerShape(50))
                                    .padding(horizontal = 7.dp, vertical = 3.dp)
                            ) {
                                Text("Main", fontSize = 9.sp, fontWeight = FontWeight.Bold, color = Color.White)
                            }
                        } else {
                            Text("Photo ${index + 1}", fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = Color.White)
                        }
                    }
                    // Mismatch warning badge (top-left)
                    if (isMismatched) {
                        Box(
                            modifier = Modifier
                                .align(Alignment.TopStart)
                                .padding(6.dp)
                                .size(20.dp)
                                .background(Color(0xFFFF4757), CircleShape),
                            contentAlignment = Alignment.Center
                        ) {
                            Icon(Icons.Default.Warning, contentDescription = null, tint = Color.White, modifier = Modifier.size(10.dp))
                        }
                    }
                    // × remove badge
                    Box(
                        modifier = Modifier
                            .align(Alignment.TopEnd)
                            .padding(6.dp)
                            .size(24.dp)
                            .background(Color.Black.copy(alpha = 0.65f), CircleShape)
                            .clickable(onClick = onRemove),
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(Icons.Default.Close, contentDescription = "Remove", tint = Color.White, modifier = Modifier.size(12.dp))
                    }
                    // Reorder arrows
                    if (onMoveLeft != null || onMoveRight != null) {
                        Row(
                            modifier = Modifier
                                .align(Alignment.BottomEnd)
                                .padding(4.dp),
                            horizontalArrangement = Arrangement.spacedBy(2.dp)
                        ) {
                            if (onMoveLeft != null) {
                                Box(
                                    modifier = Modifier
                                        .size(22.dp)
                                        .background(Color.Black.copy(alpha = 0.65f), CircleShape)
                                        .clickable(onClick = onMoveLeft),
                                    contentAlignment = Alignment.Center
                                ) {
                                    Icon(Icons.Default.ChevronLeft, contentDescription = "Move left", tint = Color.White, modifier = Modifier.size(14.dp))
                                }
                            }
                            if (onMoveRight != null) {
                                Box(
                                    modifier = Modifier
                                        .size(22.dp)
                                        .background(Color.Black.copy(alpha = 0.65f), CircleShape)
                                        .clickable(onClick = onMoveRight),
                                    contentAlignment = Alignment.Center
                                ) {
                                    Icon(Icons.Default.ChevronRight, contentDescription = "Move right", tint = Color.White, modifier = Modifier.size(14.dp))
                                }
                            }
                        }
                    }
                    // Upload progress overlay
                    if (isUploading) {
                        Box(
                            modifier = Modifier.fillMaxSize().clip(RoundedCornerShape(cornerRadius)).background(Color.Black.copy(alpha = 0.55f)),
                            contentAlignment = Alignment.Center
                        ) {
                            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                CircularProgressIndicator(modifier = Modifier.size(24.dp), color = Color.White, strokeWidth = 2.dp)
                                Text("Uploading", fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = Color.White)
                            }
                        }
                    } else if (hasFailed) {
                        Box(
                            modifier = Modifier.fillMaxSize().clip(RoundedCornerShape(cornerRadius)).background(Color.Black.copy(alpha = 0.55f)).clickable { onRetry?.invoke() },
                            contentAlignment = Alignment.Center
                        ) {
                            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                Icon(Icons.Default.Warning, contentDescription = null, tint = Color(0xFFFF6B9D), modifier = Modifier.size(22.dp))
                                Text("Upload failed", fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = Color.White)
                                Text("Tap to retry", fontSize = 10.sp, color = Color.White.copy(alpha = 0.7f))
                            }
                        }
                    }
                }
            }

            index == photos.size -> {
                // Add slot
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .clip(RoundedCornerShape(cornerRadius))
                        .background(Surface)
                        .border(
                            width = 1.5.dp,
                            color = TextHint.copy(alpha = 0.5f),
                            shape = RoundedCornerShape(cornerRadius)
                        )
                        .clickable(onClick = onFillSlot),
                    contentAlignment = Alignment.Center
                ) {
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        Icon(
                            Icons.Default.Add,
                            contentDescription = "Add photo",
                            tint = editPink,
                            modifier = Modifier.size(24.dp)
                        )
                        Text("Add Photo", fontSize = 11.sp, fontWeight = FontWeight.Medium, color = TextSecondary)
                    }
                }
            }

            else -> {
                // Empty placeholder
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .clip(RoundedCornerShape(cornerRadius))
                        .background(Surface.copy(alpha = 0.55f))
                        .border(1.dp, TextHint.copy(alpha = 0.18f), RoundedCornerShape(cornerRadius)),
                    contentAlignment = Alignment.Center
                ) {
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(4.dp)
                    ) {
                        Icon(Icons.Default.Photo, contentDescription = null, tint = TextHint.copy(alpha = 0.55f), modifier = Modifier.size(18.dp))
                        Text("Photo ${index + 1}", fontSize = 10.sp, fontWeight = FontWeight.Medium, color = TextHint)
                    }
                }
            }
        }
    }
}

internal fun cmToFeetInches(cm: Int): String {
    val totalInches = (cm / 2.54).toInt()
    val feet = totalInches / 12
    val inches = totalInches % 12
    return "$feet'$inches\""
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ProfileDropdown(
    label: String,
    selected: String,
    options: List<String>,
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
            modifier = Modifier.fillMaxWidth().menuAnchor(MenuAnchorType.PrimaryNotEditable),
            colors = OutlinedTextFieldDefaults.colors(
                focusedBorderColor = editPink,
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
                    text = { Text(option, color = if (option == selected) editPink else TextPrimary, fontSize = 14.sp) },
                    onClick = { onSelect(option); expanded = false }
                )
            }
        }
    }
}

@Composable
internal fun SliderCard(
    icon: ImageVector,
    label: String,
    valueText: String,
    subText: String?,
    minLabel: String,
    maxLabel: String,
    value: Float,
    onValueChange: (Float) -> Unit,
    valueRange: ClosedFloatingPointRange<Float>,
    steps: Int
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(CardBackground, RoundedCornerShape(16.dp))
            .border(1.dp, editPink.copy(alpha = 0.12f), RoundedCornerShape(16.dp))
            .padding(horizontal = 16.dp)
            .padding(top = 14.dp, bottom = 10.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        // Header row
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Box(
                    modifier = Modifier
                        .size(30.dp)
                        .background(editPink.copy(alpha = 0.12f), CircleShape),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(icon, contentDescription = null, tint = editPink, modifier = Modifier.size(15.dp))
                }
                Text(label, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = TextPrimary)
            }
            // Value badge
            Row(
                modifier = Modifier
                    .background(editPink.copy(alpha = 0.1f), RoundedCornerShape(50))
                    .border(1.dp, editPink.copy(alpha = 0.25f), RoundedCornerShape(50))
                    .padding(horizontal = 12.dp, vertical = 5.dp),
                horizontalArrangement = Arrangement.spacedBy(4.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(valueText, fontSize = 15.sp, fontWeight = FontWeight.Bold, color = editPink)
                if (subText != null) {
                    Text("· $subText", fontSize = 12.sp, color = TextSecondary)
                }
            }
        }

        // Slider
        Slider(
            value = value,
            onValueChange = onValueChange,
            valueRange = valueRange,
            steps = steps,
            modifier = Modifier.fillMaxWidth(),
            colors = SliderDefaults.colors(
                thumbColor = editPink,
                activeTrackColor = editPink,
                inactiveTrackColor = Surface
            )
        )

        // Range labels
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(minLabel, fontSize = 11.sp, color = TextHint)
            Text(maxLabel, fontSize = 11.sp, color = TextHint)
        }
    }
}

@Composable
private fun SectionLabel(label: String) {
    Text(
        label,
        fontSize = 18.sp,
        color = TextPrimary,
        fontWeight = FontWeight.SemiBold
    )
}
