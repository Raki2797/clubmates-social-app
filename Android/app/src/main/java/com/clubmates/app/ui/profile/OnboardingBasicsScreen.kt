package com.clubmates.app.ui.profile

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.clubmates.app.domain.model.ProfilePhoto
import com.clubmates.app.domain.model.UserProfile
import com.clubmates.app.ui.auth.AuthViewModel
import com.clubmates.app.ui.components.ClubMatesTextField
import com.clubmates.app.ui.theme.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun OnboardingBasicsScreen(
    viewModel: AuthViewModel,
    onNext: () -> Unit
) {
    val uiState by viewModel.uiState.collectAsState()
    val draft = viewModel.onboardingDraft

    var name by remember { mutableStateOf(draft.name) }
    var age by remember { mutableFloatStateOf(draft.age.coerceIn(18, 60).toFloat()) }
    var bio by remember { mutableStateOf(draft.bio) }
    var profession by remember { mutableStateOf(draft.profession.ifBlank { "Student" }) }
    var gender by remember { mutableStateOf(draft.gender.ifBlank { "Male" }) }
    var height by remember { mutableFloatStateOf(draft.height.coerceIn(140, 220).toFloat()) }
    var photos by remember { mutableStateOf(draft.photos.toMutableList()) }
    var replacingPhotoIndex by remember { mutableStateOf<Int?>(null) }

    val photoPickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.GetContent()
    ) { uri: Uri? ->
        if (uri != null) {
            val newPhoto = ProfilePhoto(localUri = uri)
            val idx = replacingPhotoIndex
            photos = if (idx != null && idx < photos.size) {
                photos.toMutableList().also { it[idx] = newPhoto }
            } else {
                photos.toMutableList().also { if (photos.size < 6) it.add(newPhoto) }
            }
            replacingPhotoIndex = null
        }
    }

    val pink = Color(0xFFFF6B9D)
    val purple = Color(0xFFC44EFF)
    val gradient = Brush.linearGradient(listOf(pink, purple))

    val canProceed = name.trim().length >= 2 && bio.trim().length >= 10

    Box(modifier = Modifier.fillMaxSize().background(Background)) {
        Column(modifier = Modifier.fillMaxSize()) {
            // Header
            OnboardingHeader(step = 1, totalSteps = 3, onBack = null)

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
                        .border(1.dp, pink.copy(alpha = 0.2f), RoundedCornerShape(18.dp))
                        .padding(18.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Text("Let's start with the basics", fontSize = 22.sp, fontWeight = FontWeight.Black, color = TextPrimary)
                    Text("Add your photos and tell people a bit about yourself.", fontSize = 14.sp, color = TextSecondary, lineHeight = 20.sp)
                }

                // Photos grid
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text("PHOTOS", fontSize = 11.sp, fontWeight = FontWeight.Bold, color = TextHint, letterSpacing = 1.sp)
                    val rows = (0 until 6).chunked(3)
                    rows.forEach { rowIndices ->
                        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            rowIndices.forEach { index ->
                                Box(modifier = Modifier.weight(1f).aspectRatio(1f)) {
                                    PhotoSlot(
                                        index = index, photos = photos,
                                        onFillSlot = { replacingPhotoIndex = if (index < photos.size) index else null; photoPickerLauncher.launch("image/*") },
                                        onRemove = { photos = photos.toMutableList().also { it.removeAt(index) } },
                                        onMoveLeft = null, onMoveRight = null
                                    )
                                }
                            }
                        }
                    }
                    Text("Add up to 6 photos. Your first photo is the main one.", fontSize = 12.sp, color = TextHint)
                }

                // Basic info
                Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    Text("ABOUT YOU", fontSize = 11.sp, fontWeight = FontWeight.Bold, color = TextHint, letterSpacing = 1.sp)
                    ClubMatesTextField(value = name, onValueChange = { name = it }, label = "Name", accentColor = pink)
                    SliderCard(icon = Icons.Default.Cake, label = "Age", valueText = "${age.toInt()}", subText = null, minLabel = "18", maxLabel = "60", value = age, onValueChange = { age = it }, valueRange = 18f..60f, steps = 41)
                    ClubMatesTextField(value = bio, onValueChange = { bio = it.take(150) }, label = "Bio (${bio.length}/150)", singleLine = false, maxLines = 3, accentColor = pink)
                    ProfileDropdown(label = "Profession", selected = profession, options = PROFESSION_OPTIONS, onSelect = { profession = it })
                    ProfileDropdown(label = "Gender", selected = gender, options = GENDER_OPTIONS, onSelect = { gender = it })
                    SliderCard(icon = Icons.Default.Height, label = "Height", valueText = "${height.toInt()} cm", subText = cmToFeetInches(height.toInt()), minLabel = "140 cm", maxLabel = "220 cm", value = height, onValueChange = { height = it }, valueRange = 140f..220f, steps = 79)
                }

                uiState.error?.let { Text(it, color = MaterialTheme.colorScheme.error, fontSize = 14.sp) }
                Spacer(modifier = Modifier.height(100.dp))
            }
        }

        // Bottom bar
        OnboardingBottomBar(
            label = "Next: Your Vibe →",
            enabled = canProceed,
            isLoading = false,
            step = 1,
            totalSteps = 3,
            onClick = {
                viewModel.updateOnboardingDraft(
                    viewModel.onboardingDraft.copy(
                        name = name.trim(), age = age.toInt(), bio = bio.trim(),
                        profession = profession, gender = gender, height = height.toInt(),
                        photos = photos.toList()
                    )
                )
                onNext()
            },
            modifier = Modifier.align(Alignment.BottomCenter)
        )
    }
}
