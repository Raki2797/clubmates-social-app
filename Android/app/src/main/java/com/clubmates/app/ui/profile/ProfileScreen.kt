package com.clubmates.app.ui.profile

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.*
import androidx.compose.animation.core.*
import androidx.compose.animation.core.animateIntAsState
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ExitToApp
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.*
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import coil.compose.AsyncImage
import coil.request.ImageRequest
import com.clubmates.app.BuildConfig
import com.clubmates.app.domain.model.ProfilePhoto
import com.clubmates.app.domain.model.UserProfile
import com.clubmates.app.ui.components.AvatarImage
import com.clubmates.app.ui.theme.*
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin
import kotlinx.coroutines.launch

// ── Theme constants (mirrors iOS AppTheme exactly) ────────────────────────────
private val Pink    = Color(0xFFFF6B9D)
private val Purple  = Color(0xFFC44EFF)
private val Green   = Color(0xFF00E5A0)
private val Gold    = Color(0xFFFFB800)
private val Red     = Color(0xFFFF4757)
private val DeepPurple = Color(0xFF7C3AED)
private val profileGradient = Brush.linearGradient(listOf(Pink, Purple))

// ── Profile screen ────────────────────────────────────────────────────────────

@OptIn(ExperimentalFoundationApi::class, ExperimentalLayoutApi::class)
@Composable
fun ProfileScreen(
    onLogout: () -> Unit,
    onEngineeringMenu: () -> Unit = {},
    onPreferences: () -> Unit = {},
    onNotifications: () -> Unit = {},
    onPrivacy: () -> Unit = {},
    onHelpSupport: () -> Unit = {},
    onVerify: () -> Unit = {},
    viewModel: ProfileViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    var isViewMode by remember { mutableStateOf(false) }  // iOS default is .manage
    var showEdit by remember { mutableStateOf(false) }
    var showDeleteConfirm by remember { mutableStateOf(false) }
    var editingPrompt by remember { mutableStateOf<UserProfile.Prompt?>(null) }
    var showAddPrompt by remember { mutableStateOf(false) }
    var showInterestPicker by remember { mutableStateOf(false) }
    var replacingPhotoIndex by remember { mutableStateOf<Int?>(null) }

    LaunchedEffect(Unit) { viewModel.loadProfile() }
    LaunchedEffect(uiState.deleteSuccess) { if (uiState.deleteSuccess) onLogout() }
    LaunchedEffect(uiState.saveSuccess) { if (uiState.saveSuccess) { viewModel.clearSaveSuccess(); showEdit = false } }

    // Edit Profile sheet — mirrors iOS sheet(isPresented: $showEditSheet) { EditProfileView }
    if (showEdit && uiState.profile != null) {
        EditProfileScreen(
            profile = uiState.profile!!,
            viewModel = viewModel,
            onBack = { showEdit = false }
        )
        return
    }

    val photoPickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.GetContent()
    ) { uri: Uri? ->
        val profile = uiState.profile ?: return@rememberLauncherForActivityResult
        if (uri != null) {
            val newPhoto = ProfilePhoto(localUri = uri)
            val photos = profile.photos.toMutableList()
            val idx = replacingPhotoIndex
            if (idx != null && idx < photos.size) photos[idx] = newPhoto
            else if (photos.size < 6) photos.add(newPhoto)
            viewModel.saveProfile(profile.copy(photos = photos))
        }
        replacingPhotoIndex = null
    }

    if (showDeleteConfirm) {
        AlertDialog(
            onDismissRequest = { if (!uiState.isDeleting) showDeleteConfirm = false },
            title = { Text("Delete Account", color = TextPrimary) },
            text = {
                Text(
                    "Your account will be deactivated now and permanently deleted after 24 hours.",
                    color = TextSecondary
                )
            },
            confirmButton = {
                TextButton(onClick = { viewModel.deleteAccount() }, enabled = !uiState.isDeleting) {
                    if (uiState.isDeleting) CircularProgressIndicator(Modifier.size(16.dp), color = Red)
                    else Text("Delete", color = Red)
                }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteConfirm = false }, enabled = !uiState.isDeleting) {
                    Text("Cancel", color = TextSecondary)
                }
            },
            containerColor = SurfaceVariant
        )
    }

    // Prompt editor sheet
    val promptToEdit = editingPrompt
    if (promptToEdit != null || showAddPrompt) {
        val prompt = promptToEdit ?: UserProfile.Prompt(question = "", answer = "")
        PromptEditorSheet(
            prompt = prompt,
            onSave = { updated ->
                val profile = uiState.profile ?: return@PromptEditorSheet
                val prompts = profile.prompts.toMutableList()
                val existingIdx = prompts.indexOfFirst { it.id == updated.id }
                if (existingIdx >= 0) prompts[existingIdx] = updated else prompts.add(updated)
                viewModel.saveProfile(profile.copy(prompts = prompts))
                editingPrompt = null; showAddPrompt = false
            },
            onDismiss = { editingPrompt = null; showAddPrompt = false }
        )
    }

    // Interest picker sheet
    if (showInterestPicker) {
        val profile = uiState.profile
        if (profile != null) {
            InterestPickerSheet(
                selected = profile.interests.toSet(),
                onConfirm = { updated ->
                    viewModel.saveProfile(profile.copy(interests = updated.toList()))
                    showInterestPicker = false
                },
                onDismiss = { showInterestPicker = false }
            )
        }
    }

    Column(
        // consumeWindowInsets: the header draws into the status bar region intentionally
        // and manages its own statusBarsPadding() internally, so we consume the top inset
        // here to prevent the NavHost's safeDrawing from double-padding the header.
        modifier = Modifier.fillMaxSize().background(Background).verticalScroll(rememberScrollState())
            .consumeWindowInsets(WindowInsets.statusBars)
    ) {
        when {
            uiState.isLoading -> ProfileShimmer()
            uiState.profile == null -> Box(
                modifier = Modifier.fillMaxWidth().padding(40.dp),
                contentAlignment = Alignment.Center
            ) { Text("Could not load profile", color = TextSecondary) }

            else -> {
                val profile = uiState.profile!!

                // ── Header (orbital avatar) ───────────────────────────────────
                ProfileHeader(
                    profile = profile,
                    onEditClick = { showEdit = true },  // opens EditProfileScreen sheet, mirrors iOS openEditProfile()
                    onEngineeringMenu = onEngineeringMenu
                )

                // ── Mode picker ───────────────────────────────────────────────
                ProfileModePicker(
                    isViewMode = isViewMode,
                    onModeChange = { isViewMode = it },
                    modifier = Modifier
                        .padding(horizontal = 20.dp)
                        .offset(y = (-6).dp)
                        .padding(bottom = 14.dp)
                )

                if (isViewMode) {
                    ViewModeContent(profile = profile)
                } else {
                    ManageModeContent(
                        profile = profile,
                        uiState = uiState,
                        onAddPhoto = { replacingPhotoIndex = null; photoPickerLauncher.launch("image/*") },
                        onReplacePhoto = { idx -> replacingPhotoIndex = idx; photoPickerLauncher.launch("image/*") },
                        onDeletePhoto = { idx ->
                            val photos = profile.photos.toMutableList().also { it.removeAt(idx) }
                            viewModel.saveProfile(profile.copy(photos = photos))
                        },
                        onAddPrompt = { showAddPrompt = true },
                        onEditPrompt = { editingPrompt = it },
                        onDeletePrompt = { prompt ->
                            viewModel.saveProfile(profile.copy(prompts = profile.prompts.filter { it.id != prompt.id }))
                        },
                        onEditInterests = { showInterestPicker = true },
                        onVerify = onVerify,
                        onLogout = onLogout,
                        onDeleteAccount = { showDeleteConfirm = true },
                        onPreferences = onPreferences,
                        onNotifications = onNotifications,
                        onPrivacy = onPrivacy,
                        onHelpSupport = onHelpSupport
                    )
                }
            }
        }
    }
}

// ── View Mode ─────────────────────────────────────────────────────────────────
// Mirrors iOS exactly: hero card + discovery prefs only in scroll.
// Bento, bio, prompts, gallery, interests are inside ProfileFullDetailSheet
// which opens when the chevron button is tapped.

@OptIn(ExperimentalFoundationApi::class, ExperimentalLayoutApi::class)
@Composable
private fun ViewModeContent(profile: UserProfile) {
    var appeared by remember { mutableStateOf(false) }
    var showFullDetail by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { appeared = true }

    if (showFullDetail) {
        com.clubmates.app.ui.discover.ProfileFullDetailSheet(
            profile = profile,
            onDismiss = { showFullDetail = false }
        )
    }

    Column(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp),
        verticalArrangement = Arrangement.spacedBy(24.dp)
    ) {
        // 1. Hero card (chevron opens full detail overlay)
        StaggeredItem(appeared, 0) {
            ProfileHeroCard(profile, onChevronClick = { showFullDetail = true })
        }

        // 2. Discovery preferences (only other section in View mode, mirrors iOS publicDatingIntent)
        StaggeredItem(appeared, 1) { DiscoveryPreferencesCard(profile) }

        Spacer(Modifier.height(100.dp))
    }
}

// ── Manage Mode ───────────────────────────────────────────────────────────────

@OptIn(ExperimentalLayoutApi::class, ExperimentalFoundationApi::class)
@Composable
private fun ManageModeContent(
    profile: UserProfile,
    uiState: ProfileUiState,
    onAddPhoto: () -> Unit,
    onReplacePhoto: (Int) -> Unit,
    onDeletePhoto: (Int) -> Unit,
    onAddPrompt: () -> Unit,
    onEditPrompt: (UserProfile.Prompt) -> Unit,
    onDeletePrompt: (UserProfile.Prompt) -> Unit,
    onEditInterests: () -> Unit,
    onVerify: () -> Unit,
    onLogout: () -> Unit,
    onDeleteAccount: () -> Unit,
    onPreferences: () -> Unit,
    onNotifications: () -> Unit,
    onPrivacy: () -> Unit,
    onHelpSupport: () -> Unit
) {
    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(0.dp)
    ) {
        // 1. Profile strength strip
        ProfileStrengthCard(
            profile = profile,
            modifier = Modifier.padding(horizontal = 20.dp).padding(top = 4.dp)
        )

        Spacer(Modifier.height(12.dp))

        // 2. Verification card
        VerificationCard(
            profile = profile,
            onVerifyClick = onVerify,
            modifier = Modifier.padding(horizontal = 20.dp)
        )

        Spacer(Modifier.height(12.dp))

        // 3. Stats strip
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            StatCard("98", "Likes", Icons.Default.Favorite, Pink,
                Brush.linearGradient(listOf(Pink, Color(0xFFFF4499))), Modifier.weight(1f))
            StatCard("0", "Matches", Icons.Default.CheckCircle, Green,
                Brush.linearGradient(listOf(Green, Color(0xFF00B4D8))), Modifier.weight(1f))
            StatCard("0", "Chats", Icons.Default.Chat, Purple,
                Brush.linearGradient(listOf(Purple, DeepPurple)), Modifier.weight(1f))
        }

        Spacer(Modifier.height(24.dp))

        // 4. Bio card (rotating border)
        if (profile.bio.isNotBlank()) {
            BioCard(bio = profile.bio, modifier = Modifier.padding(horizontal = 20.dp))
            Spacer(Modifier.height(24.dp))
        }

        // 5. Photo strip (horizontal scroll, iOS style)
        ManagePhotoStrip(
            photos = profile.photos,
            isSaving = uiState.isSaving,
            failedPhotoIndex = uiState.failedPhotoIndex,
            mismatchedPhotoIds = uiState.verificationMismatchedPhotoIds.toSet(),
            onAdd = onAddPhoto,
            onReplace = onReplacePhoto,
            onDelete = onDeletePhoto
        )

        Spacer(Modifier.height(24.dp))

        // 6. Prompts
        ManagePromptsSection(
            prompts = profile.prompts,
            onAdd = onAddPrompt,
            onEdit = onEditPrompt,
            onDelete = onDeletePrompt,
            modifier = Modifier.padding(horizontal = 20.dp)
        )

        Spacer(Modifier.height(24.dp))

        // 7. Interests
        ManageInterestsSection(
            interests = profile.interests,
            onEdit = onEditInterests,
            modifier = Modifier.padding(horizontal = 20.dp)
        )

        uiState.error?.let {
            Text(it, color = MaterialTheme.colorScheme.error, fontSize = 14.sp,
                modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp))
        }

        // 8. Settings
        SettingsSection(
            onLogout = onLogout,
            onDeleteAccount = onDeleteAccount,
            onPreferences = onPreferences,
            onNotifications = onNotifications,
            onPrivacy = onPrivacy,
            onHelpSupport = onHelpSupport,
            isDeleting = uiState.isDeleting,
            modifier = Modifier.padding(top = 32.dp)
        )
    }
}

// ── Profile header (orbital avatar) ──────────────────────────────────────────

@Composable
private fun ProfileHeader(
    profile: UserProfile,
    onEditClick: () -> Unit,
    onEngineeringMenu: () -> Unit = {}
) {
    val infiniteTransition = rememberInfiniteTransition(label = "orbital")
    val ringBase by infiniteTransition.animateFloat(
        initialValue = 0f, targetValue = 360f,
        animationSpec = infiniteRepeatable(tween(9000, easing = LinearEasing)), label = "ring"
    )
    val orbit1Base by infiniteTransition.animateFloat(
        initialValue = 0f, targetValue = 360f,
        animationSpec = infiniteRepeatable(tween(4500, easing = LinearEasing)), label = "o1"
    )
    val orbit2Base by infiniteTransition.animateFloat(
        initialValue = 0f, targetValue = -360f,
        animationSpec = infiniteRepeatable(tween(6200, easing = LinearEasing)), label = "o2"
    )
    val orbit3Base by infiniteTransition.animateFloat(
        initialValue = 0f, targetValue = 360f,
        animationSpec = infiniteRepeatable(tween(8800, easing = LinearEasing)), label = "o3"
    )
    val orbit4Base by infiniteTransition.animateFloat(
        initialValue = 0f, targetValue = -360f,
        animationSpec = infiniteRepeatable(tween(3400, easing = LinearEasing)), label = "o4"
    )
    val pulse by infiniteTransition.animateFloat(
        initialValue = 0.88f, targetValue = 1.08f,
        animationSpec = infiniteRepeatable(tween(1800, easing = FastOutSlowInEasing), RepeatMode.Reverse), label = "pulse"
    )
    val orbit1Angle = orbit1Base + 0f
    val orbit2Angle = orbit2Base + 90f
    val orbit3Angle = orbit3Base + 180f
    val orbit4Angle = orbit4Base + 270f

    var avatarTapCount by remember { mutableIntStateOf(0) }
    if (BuildConfig.DEBUG) {
        LaunchedEffect(avatarTapCount) {
            if (avatarTapCount >= 5) { avatarTapCount = 0; onEngineeringMenu() }
        }
    }

    Box(modifier = Modifier.fillMaxWidth()) {
        // Mesh background
        Box(modifier = Modifier.matchParentSize().background(
            Brush.verticalGradient(listOf(Color(0xFF0D0B1E), Color(0xFF1A0D2E), Color(0xFF0D0D0F)))
        ))
        Box(modifier = Modifier.size(220.dp).offset(x = (-80).dp, y = (-60).dp)
            .background(Brush.radialGradient(
                listOf(Color(0xFF7C3AED).copy(0.35f), Color(0xFF7C3AED).copy(0.10f), Color.Transparent)
            ), CircleShape))
        Box(modifier = Modifier.size(180.dp).align(Alignment.TopEnd).offset(x = 100.dp, y = 20.dp)
            .background(Brush.radialGradient(
                listOf(Pink.copy(0.25f), Pink.copy(0.08f), Color.Transparent)
            ), CircleShape))
        Box(modifier = Modifier.size(140.dp).align(Alignment.TopCenter).offset(x = 20.dp, y = 80.dp)
            .background(Brush.radialGradient(
                listOf(Purple.copy(0.18f), Purple.copy(0.05f), Color.Transparent)
            ), CircleShape))
        Box(modifier = Modifier.matchParentSize().background(
            Brush.verticalGradient(colorStops = arrayOf(0.0f to Color.Transparent, 0.55f to Color.Transparent, 1.0f to Background))
        ))

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .statusBarsPadding()
                .padding(top = 52.dp, bottom = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            val containerDp = 252.dp
            val r1 = 66f; val r2 = 82f; val r3 = 96f; val r4 = 110f

            Box(
                modifier = Modifier.size(containerDp)
                    .then(if (BuildConfig.DEBUG) Modifier.pointerInput(Unit) {
                        detectTapGestures { avatarTapCount++ }
                    } else Modifier),
                contentAlignment = Alignment.Center
            ) {
                Box(modifier = Modifier.size(260.dp).graphicsLayer { scaleX = pulse; scaleY = pulse; alpha = pulse * 0.6f }
                    .background(Brush.radialGradient(listOf(Pink.copy(0.28f), Pink.copy(0.08f), Color.Transparent), radius = 400f), CircleShape))
                Box(modifier = Modifier.size(300.dp).graphicsLayer { scaleX = pulse * 0.9f; scaleY = pulse * 0.9f; alpha = pulse * 0.45f }
                    .background(Brush.radialGradient(listOf(Purple.copy(0.20f), Purple.copy(0.05f), Color.Transparent), radius = 480f), CircleShape))

                Canvas(modifier = Modifier.size(containerDp)) {
                    val cx = size.width / 2f; val cy = size.height / 2f
                    drawOrbitalRing(cx, cy, r1, ringBase, listOf(Pink, Purple, Color(0xFFC44EFF), Color(0xFF00E5A0), Pink.copy(0.4f), Pink), 2.5f, 0f, 0f)
                    drawOrbitalRing(cx, cy, r2, ringBase * 0.5f, listOf(Purple.copy(0.70f), Purple.copy(0.15f), Purple.copy(0.60f), Purple.copy(0.10f), Purple.copy(0.70f)), 1.5f, 6f, 5f)
                    drawOrbitalRing(cx, cy, r3, -ringBase * 0.3f, listOf(Green.copy(0.65f), Green.copy(0.12f), Green.copy(0.55f), Green.copy(0.08f), Green.copy(0.65f)), 1.5f, 5f, 7f)
                    drawOrbitalRing(cx, cy, r4, ringBase * 0.4f, listOf(Purple.copy(0.6f), Purple.copy(0.15f), Purple.copy(0.55f), Purple.copy(0.10f), Purple.copy(0.6f)), 1.5f, 4f, 6f)
                    drawOrbitBall(cx, cy, r4, orbit4Angle, Purple, 10f, 4f)
                    drawOrbitBall(cx, cy, r3, orbit3Angle, Green, 9f, 3f)
                    drawOrbitBall(cx, cy, r2, orbit2Angle, Purple, 11f, 5f)
                    drawOrbitBall(cx, cy, r1, orbit1Angle, Pink, 12f, 6f)
                }

                // Central avatar — 112dp matches iOS
                val photoModel = profile.photos.firstOrNull()?.let { it.localUri ?: it.cdnUrl }
                Box(
                    modifier = Modifier.size(112.dp)
                        .graphicsLayer { shadowElevation = 24.dp.toPx(); shape = CircleShape; clip = true }
                        .border(1.5.dp, Brush.linearGradient(listOf(Color.White.copy(0.25f), Color.White.copy(0.05f))), CircleShape),
                    contentAlignment = Alignment.Center
                ) {
                    if (photoModel != null) {
                        val ctx = LocalContext.current
                        AsyncImage(
                            model = remember(photoModel) { ImageRequest.Builder(ctx).data(photoModel).crossfade(false).build() },
                            contentDescription = profile.name,
                            contentScale = ContentScale.Crop,
                            modifier = Modifier.size(112.dp).clip(CircleShape)
                        )
                    } else {
                        AvatarImage(photoUrl = null, size = 112.dp)
                    }
                }
            }

            Spacer(Modifier.height(16.dp))

            // Name + age + verified
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(profile.name, fontSize = 26.sp, fontWeight = FontWeight.Bold, color = Color.White)
                Text("${profile.age}", fontSize = 24.sp, fontWeight = FontWeight.Light, color = Color.White.copy(0.72f))
                if (profile.isVerified) {
                    Icon(
                        Icons.Default.CheckCircle,
                        contentDescription = "Verified",
                        tint = Green,
                        modifier = Modifier.size(17.dp)
                    )
                }
            }

            cleanedProfession(profile)?.let { profession ->
                Spacer(Modifier.height(4.dp))
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(5.dp)
                ) {
                    Icon(
                        iconForProfession(profession),
                        contentDescription = null,
                        tint = Purple.copy(alpha = 0.8f),
                        modifier = Modifier.size(11.dp)
                    )
                    Text(
                        profession,
                        fontSize = 13.sp,
                        color = Color.White.copy(alpha = 0.55f)
                    )
                }
            }

            Spacer(Modifier.height(14.dp))

            // "Edit Profile" button
            OutlinedButton(
                onClick = onEditClick,
                shape = RoundedCornerShape(50),
                border = androidx.compose.foundation.BorderStroke(
                    1.2.dp,
                    Brush.linearGradient(listOf(Pink.copy(0.5f), Purple.copy(0.3f)))
                ),
                colors = ButtonDefaults.outlinedButtonColors(containerColor = Pink.copy(0.10f)),
                contentPadding = PaddingValues(horizontal = 22.dp, vertical = 10.dp)
            ) {
                Icon(Icons.Default.Edit, null, tint = Pink, modifier = Modifier.size(12.dp))
                Spacer(Modifier.width(6.dp))
                Text("Edit Profile", fontSize = 14.sp, fontWeight = FontWeight.Black,
                    style = androidx.compose.ui.text.TextStyle(brush = profileGradient))
            }
        }
    }
}

// ── Hero card (View mode) ─────────────────────────────────────────────────────

@Composable
private fun ProfileHeroCard(profile: UserProfile, onChevronClick: () -> Unit = {}) {
    val photoUrl = profile.photos.firstOrNull()?.cdnUrl
    val ctx = LocalContext.current

    Box(
        modifier = Modifier.fillMaxWidth().height(460.dp)
            .clip(RoundedCornerShape(28.dp))
            .border(1.dp, Brush.linearGradient(listOf(Color.White.copy(0.14f), Pink.copy(0.22f), Color.White.copy(0.06f))), RoundedCornerShape(28.dp))
    ) {
        // Photo or fallback gradient
        if (photoUrl != null) {
            AsyncImage(
                model = remember(photoUrl) { ImageRequest.Builder(ctx).data(photoUrl).crossfade(false).build() },
                contentDescription = profile.name,
                contentScale = ContentScale.Crop,
                alignment = Alignment.TopCenter,
                modifier = Modifier.fillMaxSize()
            )
        } else {
            Box(modifier = Modifier.fillMaxSize().background(
                Brush.verticalGradient(listOf(Color(0xFF111827), Color(0xFF4A1259)))
            ))
        }

        // Top gradient
        Box(modifier = Modifier.fillMaxWidth().height(130.dp)
            .background(Brush.verticalGradient(listOf(Color.Black.copy(0.45f), Color.Transparent))))

        // Bottom gradient
        Box(modifier = Modifier.fillMaxWidth().fillMaxHeight(0.65f).align(Alignment.BottomCenter)
            .background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(0.28f), Color.Black.copy(0.82f)))))

        // Content overlay
        Column(
            modifier = Modifier.align(Alignment.BottomStart).fillMaxWidth().padding(22.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            // Pills row
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                HeroPill(Icons.Default.Visibility, "Public preview", Color.White, Color.White.copy(0.22f), Color.White.copy(0.45f))
                if (profile.isVerified) {
                    HeroPill(Icons.Default.CheckCircle, "Verified", Green, Green.copy(0.18f), Green.copy(0.65f))
                }
            }

            // Name + age
            Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(profile.name, fontSize = 36.sp, fontWeight = FontWeight.Black, color = Color.White, maxLines = 1)
                Text("${profile.age}", fontSize = 24.sp, fontWeight = FontWeight.Black, color = Color.White.copy(0.72f))
            }

            // Profession + height row + chevron
            Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.Bottom) {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp), modifier = Modifier.weight(1f)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                        cleanedProfession(profile)?.let { prof ->
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                                Icon(iconForProfession(prof), null, tint = Color.White.copy(0.82f), modifier = Modifier.size(12.dp))
                                Text(prof, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = Color.White.copy(0.82f))
                            }
                        }
                        if (profile.height > 0) {
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                                Icon(Icons.Default.Height, null, tint = Color.White.copy(0.82f), modifier = Modifier.size(12.dp))
                                Text("${profile.height} cm", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = Color.White.copy(0.82f))
                            }
                        }
                    }
                }
                // Chevron button — opens full profile detail (mirrors iOS showFullProfileDetail)
                Box(
                    modifier = Modifier.size(44.dp)
                        .background(Color.White.copy(0.15f), CircleShape)
                        .border(1.dp, Color.White.copy(0.18f), CircleShape)
                        .clickable { onChevronClick() },
                    contentAlignment = Alignment.Center
                ) {
                    Icon(Icons.Default.KeyboardArrowDown, null, tint = Color.White, modifier = Modifier.size(20.dp))
                }
            }
        }
    }
}

@Composable
private fun HeroPill(icon: ImageVector, text: String, textColor: Color, bg: Color, border: Color) {
    Row(
        modifier = Modifier.background(bg, RoundedCornerShape(50))
            .border(1.dp, border, RoundedCornerShape(50))
            .padding(horizontal = 10.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        Icon(icon, null, tint = textColor, modifier = Modifier.size(11.dp))
        Text(text, fontSize = 11.sp, fontWeight = FontWeight.Bold, color = textColor)
    }
}

// ── Bento grid (View mode) ────────────────────────────────────────────────────

@Composable
private fun PublicBentoGrid(profile: UserProfile, appeared: Boolean) {
    val profession = cleanedProfession(profile)
    val lookingFor = cleanedLookingFor(profile)
    val gender = cleanedGender(profile)

    Column(modifier = Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        // Row 1: profession (wide) + height (square)
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            if (profession != null) {
                BentoCellWide(iconForProfession(profession), "Job", profession, Purple, 0, appeared, Modifier.weight(1f))
            }
            if (profile.height > 0) {
                BentoCellSquare(Icons.Default.Height, "Height", "${profile.height}", "cm", Green, 1, appeared)
            }
        }
        // Row 2: gender (square) + looking for (wide)
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            if (gender != null) {
                BentoCellSquare(Icons.Default.Person, "Gender", gender, null, Purple, 2, appeared)
            }
            if (lookingFor != null) {
                BentoCellWide(Icons.Default.Favorite, "Here for", lookingFor, Pink, 3, appeared, Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun BentoCellWide(
    icon: ImageVector, label: String, value: String, accent: Color,
    delayIndex: Int, appeared: Boolean, modifier: Modifier = Modifier
) {
    val scale by animateFloatAsState(if (appeared) 1f else 0.9f,
        animationSpec = tween(300, delayMillis = delayIndex * 40), label = "scale$delayIndex")
    val alpha by animateFloatAsState(if (appeared) 1f else 0f,
        animationSpec = tween(300, delayMillis = delayIndex * 40), label = "alpha$delayIndex")

    Box(
        modifier = modifier.height(IntrinsicSize.Min)
            .graphicsLayer { scaleX = scale; scaleY = scale; this.alpha = alpha }
            .background(Color(0xFF232328), RoundedCornerShape(18.dp))
            .drawBehind {
                drawRoundRect(
                    brush = Brush.radialGradient(listOf(accent.copy(0.15f), Color.Transparent),
                        center = Offset(0f, 0f), radius = size.minDimension * 1.5f),
                    cornerRadius = androidx.compose.ui.geometry.CornerRadius(18.dp.toPx())
                )
            }
            .border(1.dp, accent.copy(0.28f), RoundedCornerShape(18.dp))
            .padding(14.dp)
    ) {
        Column(modifier = Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Icon(icon, null, tint = accent, modifier = Modifier.size(11.dp))
                Text(label.uppercase(), fontSize = 10.sp, fontWeight = FontWeight.Black, color = TextHint, letterSpacing = 1.sp)
            }
            Text(value, fontSize = 17.sp, fontWeight = FontWeight.Black, color = TextPrimary, maxLines = 2)
        }
    }
}

@Composable
private fun BentoCellSquare(
    icon: ImageVector, label: String, value: String, unit: String?,
    accent: Color, delayIndex: Int, appeared: Boolean
) {
    val scale by animateFloatAsState(if (appeared) 1f else 0.9f,
        animationSpec = tween(300, delayMillis = delayIndex * 40), label = "sq_scale$delayIndex")
    val alpha by animateFloatAsState(if (appeared) 1f else 0f,
        animationSpec = tween(300, delayMillis = delayIndex * 40), label = "sq_alpha$delayIndex")

    Box(
        modifier = Modifier.width(100.dp)
            .graphicsLayer { scaleX = scale; scaleY = scale; this.alpha = alpha }
            .background(Color(0xFF232328), RoundedCornerShape(18.dp))
            .drawBehind {
                drawRoundRect(
                    brush = Brush.radialGradient(listOf(accent.copy(0.18f), Color.Transparent),
                        center = Offset(0f, 0f), radius = size.minDimension * 1.5f),
                    cornerRadius = androidx.compose.ui.geometry.CornerRadius(18.dp.toPx())
                )
            }
            .border(1.dp, accent.copy(0.28f), RoundedCornerShape(18.dp))
            .padding(14.dp)
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Icon(icon, null, tint = accent, modifier = Modifier.size(18.dp))
            Spacer(Modifier.height(4.dp))
            Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(value, fontSize = 22.sp, fontWeight = FontWeight.Black, color = TextPrimary)
                if (unit != null) Text(unit, fontSize = 11.sp, fontWeight = FontWeight.Bold, color = TextHint, modifier = Modifier.padding(bottom = 3.dp))
            }
            Text(label.uppercase(), fontSize = 9.sp, fontWeight = FontWeight.Black, color = TextHint, letterSpacing = 1.sp)
        }
    }
}

// ── Bio card (rotating border) ────────────────────────────────────────────────

@Composable
private fun BioCard(bio: String, modifier: Modifier = Modifier) {
    val infiniteTransition = rememberInfiniteTransition(label = "bio_border")
    val rotation by infiniteTransition.animateFloat(
        initialValue = 0f, targetValue = 360f,
        animationSpec = infiniteRepeatable(tween(6000, easing = LinearEasing), RepeatMode.Restart),
        label = "rotation"
    )

    Column(
        modifier = modifier.fillMaxWidth()
            .background(Color(0xFF232328), RoundedCornerShape(18.dp))
            .drawWithContent {
                drawContent()
                val strokePx = 1.5.dp.toPx()
                val corner = 18.dp.toPx()
                val cx = size.width / 2f
                val cy = size.height / 2f
                val r = kotlin.math.sqrt(cx * cx + cy * cy)
                val centerX = cx + r * cos(Math.toRadians(rotation.toDouble())).toFloat()
                val centerY = cy + r * sin(Math.toRadians(rotation.toDouble())).toFloat()
                drawRoundRect(
                    brush = Brush.sweepGradient(
                        colors = listOf(Pink, Purple, Color(0xFFC44EFF), Pink.copy(0.2f), Pink),
                        center = Offset(centerX, centerY)
                    ),
                    cornerRadius = androidx.compose.ui.geometry.CornerRadius(corner),
                    style = Stroke(width = strokePx)
                )
            }
            .padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(7.dp)) {
            Icon(Icons.Default.FormatQuote, null, tint = Pink, modifier = Modifier.size(14.dp))
            Text("About", fontSize = 17.sp, fontWeight = FontWeight.Bold, color = TextPrimary)
        }
        Text(bio, fontSize = 15.sp, color = TextSecondary, lineHeight = 22.sp)
    }
}

// ── Public prompts (View mode) ────────────────────────────────────────────────

@Composable
private fun PublicPromptsSection(prompts: List<UserProfile.Prompt>) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        SectionLabel("Get to Know Me", Icons.Default.Chat)
        prompts.forEach { prompt ->
            Row(
                modifier = Modifier.fillMaxWidth()
                    .background(Color(0xFF232328).copy(0.88f), RoundedCornerShape(18.dp))
                    .border(1.dp, Pink.copy(0.16f), RoundedCornerShape(18.dp))
                    .padding(16.dp),
                verticalAlignment = Alignment.Top,
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Box(
                    modifier = Modifier.size(34.dp).background(profileGradient, CircleShape),
                    contentAlignment = Alignment.Center
                ) { Text("\"", fontSize = 16.sp, fontWeight = FontWeight.Black, color = Color.White) }
                Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(prompt.question.uppercase(), fontSize = 11.sp, fontWeight = FontWeight.Black, color = Pink, letterSpacing = 0.8.sp)
                    Text(prompt.answer, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = TextPrimary, lineHeight = 21.sp)
                }
            }
        }
    }
}

// ── Public photo gallery (View mode, swipeable) ───────────────────────────────

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun PublicPhotoGallery(profile: UserProfile) {
    val pagerState = rememberPagerState { profile.photos.size }
    val ctx = LocalContext.current

    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        // Header row
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
            SectionLabel("Photo Story", Icons.Default.PhotoLibrary)
            Row(
                modifier = Modifier.background(Color(0xFF232328), RoundedCornerShape(50)).padding(horizontal = 10.dp, vertical = 5.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                Icon(Icons.Default.SwipeLeft, null, tint = TextHint, modifier = Modifier.size(11.dp))
                Text("Swipe", fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = TextHint)
            }
        }

        // Pager
        Box(modifier = Modifier.fillMaxWidth()) {
            HorizontalPager(
                state = pagerState,
                modifier = Modifier.fillMaxWidth().height(440.dp).clip(RoundedCornerShape(20.dp))
            ) { page ->
                val photo = profile.photos[page]
                val model = photo.cdnUrl ?: photo.localUri
                Box(modifier = Modifier.fillMaxSize().background(SurfaceVariant)) {
                    if (model != null) {
                        AsyncImage(
                            model = remember(model) { ImageRequest.Builder(ctx).data(model).crossfade(false).build() },
                            contentDescription = null,
                            contentScale = ContentScale.Crop,
                            modifier = Modifier.fillMaxSize()
                        )
                    }
                    Box(modifier = Modifier.fillMaxWidth().fillMaxHeight(0.45f).align(Alignment.BottomCenter)
                        .background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(0.75f)))))
                }
            }
        }

        // Dot indicators
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                repeat(profile.photos.size) { i ->
                    val isActive = i == pagerState.currentPage
                    val width by animateDpAsState(if (isActive) 22.dp else 6.dp, spring(dampingRatio = 0.7f), label = "dot$i")
                    Box(
                        modifier = Modifier.height(6.dp).width(width)
                            .background(
                                if (isActive) profileGradient else Brush.linearGradient(listOf(Color.White.copy(0.25f), Color.White.copy(0.25f))),
                                RoundedCornerShape(50)
                            )
                    )
                }
            }
        }
    }
}

// ── Public interests (View mode) ──────────────────────────────────────────────

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun PublicInterestsSection(interests: List<String>) {
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        SectionLabel("Interests", Icons.Default.AutoAwesome)
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            interests.forEachIndexed { idx, interest ->
                val (c1, c2) = interestGradientPair(interest)
                var visible by remember { mutableStateOf(false) }
                LaunchedEffect(Unit) { kotlinx.coroutines.delay(idx * 55L); visible = true }
                AnimatedVisibility(visible, enter = scaleIn(spring(dampingRatio = 0.65f)) + fadeIn()) {
                    Row(
                        modifier = Modifier
                            .background(c1.copy(0.10f), RoundedCornerShape(50))
                            .border(1.dp, c1.copy(0.28f), RoundedCornerShape(50))
                            .padding(horizontal = 14.dp, vertical = 8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        Icon(interestIcon(interest), null, tint = c1, modifier = Modifier.size(13.dp))
                        Text(interest, fontSize = 13.sp, fontWeight = FontWeight.Medium,
                            style = androidx.compose.ui.text.TextStyle(brush = Brush.linearGradient(listOf(c1, c2))))
                    }
                }
            }
        }
    }
}

// ── Discovery preferences (View mode) ────────────────────────────────────────

@Composable
private fun DiscoveryPreferencesCard(profile: UserProfile) {
    Column(
        modifier = Modifier.fillMaxWidth()
            .background(CardBackground, RoundedCornerShape(18.dp))
            .border(1.dp, Green.copy(0.2f), RoundedCornerShape(18.dp))
            .padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        SectionLabel("Discovery Preferences", Icons.Default.Tune)
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            PreferencePill(Icons.Default.Cake, "${profile.preferences.ageMin}–${profile.preferences.ageMax}", Modifier.weight(1f))
            PreferencePill(Icons.Default.People,
                if (profile.preferences.genders.isEmpty()) "Everyone" else profile.preferences.genders.joinToString(", "),
                Modifier.weight(1f))
        }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            PreferencePill(Icons.Default.Height, "${profile.preferences.heightMin}–${profile.preferences.heightMax} cm", Modifier.weight(1f))
            PreferencePill(Icons.Default.CheckCircle,
                if (profile.preferences.verifiedOnly) "Verified only" else "All welcome",
                Modifier.weight(1f))
        }
    }
}

@Composable
private fun PreferencePill(icon: ImageVector, value: String, modifier: Modifier = Modifier) {
    Row(
        modifier = modifier.background(Color(0xFF232328), RoundedCornerShape(12.dp))
            .border(1.dp, Color.White.copy(0.08f), RoundedCornerShape(12.dp))
            .padding(horizontal = 12.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Icon(icon, null, tint = Green, modifier = Modifier.size(14.dp))
        Text(value, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = TextPrimary, maxLines = 1)
    }
}

// ── Profile strength card (Manage mode) ──────────────────────────────────────

@Composable
private fun ProfileStrengthCard(profile: UserProfile, modifier: Modifier = Modifier) {
    var score = 20
    if (profile.bio.isNotBlank()) score += 15
    score += profile.photos.size.coerceAtMost(6) * 6
    score += profile.prompts.count { it.answer.isNotBlank() }.coerceAtMost(3) * 8
    score += profile.interests.size.coerceAtMost(6) * 3
    if (cleanedProfession(profile) != null) score += 5
    if (cleanedLookingFor(profile) != null) score += 4
    if (profile.isVerified) score += 6
    score = score.coerceAtMost(100)

    val animatedScore by animateIntAsState(score, tween(800), label = "strength")
    val animatedArc by animateFloatAsState(score / 100f, tween(800), label = "arc")
    val strengthLabel = when { score >= 85 -> "Excellent"; score >= 60 -> "Good"; else -> "Getting started" }
    val strengthColor = when { score >= 85 -> Green; score >= 60 -> Gold; else -> Pink }

    Column(
        modifier = modifier.fillMaxWidth()
            .background(CardBackground, RoundedCornerShape(20.dp))
            .border(1.dp, strengthColor.copy(0.2f), RoundedCornerShape(20.dp))
            .drawBehind {
                drawRoundRect(
                    brush = Brush.radialGradient(
                        listOf(strengthColor.copy(0.12f), Color.Transparent),
                        center = Offset(size.width, 0f), radius = size.minDimension * 1.5f
                    ),
                    cornerRadius = androidx.compose.ui.geometry.CornerRadius(20.dp.toPx())
                )
            }
            .padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
            Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Icon(if (score >= 85) Icons.Default.AutoAwesome else Icons.Default.DialerSip,
                        null, tint = TextSecondary, modifier = Modifier.size(13.dp))
                    Text("Profile Strength", fontSize = 13.sp, fontWeight = FontWeight.Bold, color = TextSecondary)
                }
                Text(strengthLabel, fontSize = 18.sp, fontWeight = FontWeight.Black, color = TextPrimary)
            }

            // Circular arc ring (52dp, matches iOS)
            Box(contentAlignment = Alignment.Center) {
                Canvas(modifier = Modifier.size(52.dp)) {
                    val stroke = Stroke(width = 5.dp.toPx(), cap = StrokeCap.Round)
                    // Background arc
                    drawArc(Color(0xFF232328), startAngle = -90f, sweepAngle = 360f, useCenter = false, style = stroke)
                    // Foreground arc
                    drawArc(strengthColor, startAngle = -90f, sweepAngle = animatedArc * 360f, useCenter = false, style = stroke)
                }
                Text("$animatedScore%", fontSize = 11.sp, fontWeight = FontWeight.Black, color = strengthColor)
            }
        }

        // Linear bar
        Box(modifier = Modifier.fillMaxWidth().height(6.dp).background(Color(0xFF232328), RoundedCornerShape(3.dp))) {
            Box(modifier = Modifier.fillMaxWidth(animatedScore / 100f).fillMaxHeight()
                .background(Brush.linearGradient(listOf(strengthColor, strengthColor.copy(0.7f))), RoundedCornerShape(3.dp)))
        }

        // Hint
        val hint = profileCompletenessHint(profile)
        Text(hint, fontSize = 12.sp, color = TextSecondary, lineHeight = 16.sp)
    }
}

// ── Verification card (Manage mode) — 4 states matching iOS ──────────────────

@Composable
private fun VerificationCard(
    profile: UserProfile,
    onVerifyClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    // iOS priority: pending > verified > failed (non-spoof) > unverified
    data class CardConfig(
        val accent: Color,
        val iconBg: Brush,
        val icon: ImageVector,
        val title: String,
        val subtitle: String,
        val showButton: Boolean
    )

    val state = when {
        profile.verificationStatus == "pending" -> "pending"
        profile.isVerified || profile.verificationStatus == "verified" -> "verified"
        profile.verificationStatus == "failed" -> "failed"
        else -> "unverified"
    }

    val cfg = when (state) {
        "pending" -> CardConfig(
            Gold,
            Brush.linearGradient(listOf(Gold, Color(0xFFFFD93D))),
            Icons.Default.HourglassTop,
            "Verification Pending",
            "We're reviewing your profile.",
            false
        )
        "verified" -> CardConfig(
            Green, Brush.linearGradient(listOf(Green, Color(0xFF00B4D8))),
            Icons.Default.VerifiedUser,
            "Identity Verified", "Your blue badge is visible to others.",
            false
        )
        "failed" -> {
            val isPhotoMismatch = profile.verificationMismatchedPhotoIds.isNotEmpty()
            CardConfig(
                Red,
                Brush.linearGradient(listOf(Red, Color(0xFFFF6B6B))),
                Icons.Default.Warning,
                if (isPhotoMismatch) "Photos Don't Match" else "Verification Failed",
                if (isPhotoMismatch) {
                    "Some photos didn't match your selfie — replace them or re-verify."
                } else {
                    "Something went wrong. Tap Verify to try again."
                },
                true
            )
        }
        else -> CardConfig(
            Pink, profileGradient,
            Icons.Default.Shield,
            "Not Verified", "Verify with a selfie to get a blue badge.",
            true
        )
    }

    Row(
        modifier = modifier.fillMaxWidth()
            .background(CardBackground, RoundedCornerShape(16.dp))
            .border(1.dp, cfg.accent.copy(0.3f), RoundedCornerShape(16.dp))
            .padding(14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        Box(
            modifier = Modifier.size(42.dp).background(cfg.iconBg, RoundedCornerShape(10.dp)),
            contentAlignment = Alignment.Center
        ) {
            Icon(cfg.icon, null, tint = Color.White, modifier = Modifier.size(18.dp))
        }
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(cfg.title, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = TextPrimary)
            Text(cfg.subtitle, fontSize = 12.sp, color = TextSecondary)
        }
        if (cfg.showButton) {
            Box(
                modifier = Modifier.background(profileGradient, RoundedCornerShape(50))
                    .clickable { onVerifyClick() }
                    .padding(horizontal = 14.dp, vertical = 8.dp)
            ) {
                Text("Verify", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = Color.White)
            }
        }
    }
}

// ── Stat card (Manage mode) ───────────────────────────────────────────────────

@Composable
private fun StatCard(value: String, label: String, icon: ImageVector, color: Color, gradient: Brush, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier
            .background(Color(0xFF232328), RoundedCornerShape(20.dp))
            .drawBehind {
                // Radial gradient from top (mirrors iOS RadialGradient center: .top)
                drawRoundRect(
                    brush = Brush.radialGradient(
                        listOf(color.copy(0.12f), Color.Transparent),
                        center = Offset(size.width / 2f, 0f),
                        radius = size.height * 1.1f
                    ),
                    cornerRadius = androidx.compose.ui.geometry.CornerRadius(20.dp.toPx())
                )
            }
            .border(
                1.dp,
                Brush.linearGradient(listOf(color.copy(0.4f), color.copy(0.1f))),
                RoundedCornerShape(20.dp)
            )
            .padding(vertical = 18.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        // Double circle (46dp inner + 56dp blurred outer, mirrors iOS ZStack)
        Box(contentAlignment = Alignment.Center, modifier = Modifier.size(56.dp)) {
            // Outer blurred glow
            Box(modifier = Modifier.size(56.dp).background(color.copy(0.08f), CircleShape)
                .graphicsLayer { renderEffect = null; alpha = 0.8f })
            // Inner solid circle
            Box(modifier = Modifier.size(46.dp).background(color.copy(0.18f), CircleShape),
                contentAlignment = Alignment.Center) {
                Icon(icon, null, tint = color, modifier = Modifier.size(19.dp))
            }
        }
        Text(value, fontSize = 24.sp, fontWeight = FontWeight.Black,
            style = androidx.compose.ui.text.TextStyle(brush = gradient))
        Text(label.uppercase(), fontSize = 11.sp, fontWeight = FontWeight.Bold,
            color = TextSecondary, letterSpacing = 0.6.sp)
    }
}

// ── Photo strip (Manage mode, iOS horizontal scroll) ─────────────────────────

@Composable
private fun ManagePhotoStrip(
    photos: List<ProfilePhoto>,
    isSaving: Boolean,
    failedPhotoIndex: Int?,
    mismatchedPhotoIds: Set<String> = emptySet(),
    onAdd: () -> Unit,
    onReplace: (Int) -> Unit,
    onDelete: (Int) -> Unit
) {
    val ctx = LocalContext.current

    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        SectionLabel("Photos", Icons.Default.PhotoLibrary, modifier = Modifier.padding(horizontal = 20.dp))

        LazyRow(
            contentPadding = PaddingValues(horizontal = 20.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            itemsIndexed(photos) { index, photo ->
                val model = photo.localUri ?: photo.cdnUrl
                val cardShape = RoundedCornerShape(20.dp)
                val isMismatched = photo.id in mismatchedPhotoIds
                Box(modifier = Modifier.width(176.dp).height(214.dp)) {
                    // Photo card
                    Box(
                        modifier = Modifier.fillMaxSize()
                            .clip(cardShape)
                            .background(Color(0xFF2C2C33))
                            .border(
                                if (isMismatched || index == 0) 1.5.dp else 1.dp,
                                when {
                                    isMismatched -> Brush.linearGradient(listOf(Red, Red.copy(0.6f)))
                                    index == 0   -> Brush.linearGradient(listOf(Pink.copy(0.6f), Purple.copy(0.3f)))
                                    else         -> Brush.linearGradient(listOf(Color.White.copy(0.08f), Color.White.copy(0.08f)))
                                },
                                cardShape
                            )
                            .clickable { onReplace(index) }
                    ) {
                        if (model != null) {
                            AsyncImage(
                                model = remember(model) { ImageRequest.Builder(ctx).data(model).crossfade(false).build() },
                                contentDescription = null,
                                contentScale = ContentScale.Crop,
                                alignment = Alignment.TopCenter,
                                modifier = Modifier.fillMaxSize()
                            )
                        }
                        // Bottom scrim (for cover photo)
                        if (index == 0) {
                            Box(modifier = Modifier.fillMaxWidth().fillMaxHeight(0.55f).align(Alignment.BottomCenter)
                                .background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(0.48f)))))
                            // Cover badge — star icon + "Cover" text, ultraThin blur bg (mirrors iOS)
                            Box(modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 10.dp)
                                .background(Color.White.copy(0.18f), RoundedCornerShape(50))
                                .border(1.dp, Color.White.copy(0.25f), RoundedCornerShape(50))
                                .padding(horizontal = 10.dp, vertical = 5.dp)) {
                                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                                    Icon(Icons.Default.Star, null, tint = Color.White, modifier = Modifier.size(9.dp))
                                    Text("Cover", fontSize = 11.sp, fontWeight = FontWeight.Black, color = Color.White, letterSpacing = 0.3.sp)
                                }
                            }
                        }
                        // Upload overlay
                        if (isSaving && photo.localUri != null) {
                            Box(modifier = Modifier.fillMaxSize().clip(cardShape).background(Color.Black.copy(0.58f)),
                                contentAlignment = Alignment.Center) {
                                Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                    CircularProgressIndicator(Modifier.size(24.dp), color = Color.White, strokeWidth = 2.dp)
                                    Text("Uploading", fontSize = 12.sp, fontWeight = FontWeight.Bold, color = Color.White)
                                }
                            }
                        } else if (failedPhotoIndex == index) {
                            Box(modifier = Modifier.fillMaxSize().clip(cardShape).background(Color.Black.copy(0.58f)).clickable { onReplace(index) },
                                contentAlignment = Alignment.Center) {
                                Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                    Icon(Icons.Default.Warning, null, tint = Pink, modifier = Modifier.size(22.dp))
                                    Text("Upload failed", fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = Color.White)
                                    Text("Tap to retry", fontSize = 10.sp, color = Color.White.copy(0.7f))
                                }
                            }
                        }
                    }
                    // Mismatch warning badge (top-left, mirrors iOS warning triangle)
                    if (isMismatched) {
                        Box(
                            modifier = Modifier.align(Alignment.TopStart).padding(8.dp)
                                .size(22.dp).background(Red, CircleShape),
                            contentAlignment = Alignment.Center
                        ) {
                            Icon(Icons.Default.Warning, null, tint = Color.White, modifier = Modifier.size(11.dp))
                        }
                    }
                    // X delete button
                    Box(
                        modifier = Modifier.align(Alignment.TopEnd).padding(8.dp)
                            .size(24.dp).background(Color.Black.copy(0.65f), CircleShape)
                            .clickable { onDelete(index) },
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(Icons.Default.Close, null, tint = Color.White, modifier = Modifier.size(12.dp))
                    }
                }
            }

            // Add photo card
            if (photos.size < 6) {
                item {
                    Box(
                        modifier = Modifier.width(176.dp).height(214.dp)
                            .clip(RoundedCornerShape(18.dp))
                            .background(Surface)
                            .border(
                                1.5.dp,
                                Pink.copy(alpha = 0.22f),
                                RoundedCornerShape(18.dp)
                            )
                            .clickable { onAdd() },
                        contentAlignment = Alignment.Center
                    ) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Box(modifier = Modifier.size(44.dp).background(Pink.copy(0.12f), CircleShape),
                                contentAlignment = Alignment.Center) {
                                Icon(Icons.Default.Add, null, tint = Pink, modifier = Modifier.size(22.dp))
                            }
                            Text("Add Photo", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = TextSecondary)
                        }
                    }
                }
            }
        }
    }
}

// ── Prompts (Manage mode) ─────────────────────────────────────────────────────

@Composable
private fun ManagePromptsSection(
    prompts: List<UserProfile.Prompt>,
    onAdd: () -> Unit,
    onEdit: (UserProfile.Prompt) -> Unit,
    onDelete: (UserProfile.Prompt) -> Unit,
    modifier: Modifier = Modifier
) {
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
            SectionLabel("Get to Know Me", Icons.Default.Chat)
            if (prompts.size < 3) {
                TextButton(onClick = onAdd, contentPadding = PaddingValues(0.dp)) {
                    Icon(Icons.Default.Add, null, modifier = Modifier.size(13.dp), tint = Pink)
                    Spacer(Modifier.width(4.dp))
                    Text("Add", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = Pink)
                }
            }
        }

        if (prompts.isEmpty()) {
            // Empty state dashed card
            Box(
                modifier = Modifier.fillMaxWidth()
                    .background(Surface, RoundedCornerShape(18.dp))
                    .border(1.5.dp, Purple.copy(0.25f), RoundedCornerShape(18.dp))
                    .clickable { onAdd() }
                    .padding(vertical = 24.dp),
                contentAlignment = Alignment.Center
            ) {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Icon(Icons.Default.Chat, null, tint = Pink, modifier = Modifier.size(22.dp))
                    Text("Answer a prompt", fontSize = 15.sp, fontWeight = FontWeight.Bold, color = TextPrimary)
                    Text(
                        "Give people an easy way to start a conversation.",
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Medium,
                        color = TextSecondary,
                        textAlign = TextAlign.Center
                    )
                }
            }
        }

        prompts.forEach { prompt ->
            Row(
                modifier = Modifier.fillMaxWidth()
                    .background(Surface, RoundedCornerShape(18.dp))
                    .border(1.dp, Purple.copy(0.22f), RoundedCornerShape(18.dp))
                    .padding(start = 4.dp, end = 16.dp, top = 14.dp, bottom = 14.dp),
                verticalAlignment = Alignment.Top
            ) {
                Text(
                    "\u201C",
                    fontSize = 52.sp,
                    fontWeight = FontWeight.Black,
                    style = androidx.compose.ui.text.TextStyle(brush = profileGradient),
                    modifier = Modifier
                        .width(36.dp)
                        .offset(y = (-8).dp)
                )
                Column(modifier = Modifier.weight(1f).padding(top = 6.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(prompt.question.uppercase(), fontSize = 11.sp, fontWeight = FontWeight.Bold, color = Pink, letterSpacing = 0.8.sp)
                    Text(prompt.answer.ifBlank { "Tap to answer..." }, fontSize = 16.sp, fontWeight = FontWeight.Medium,
                        color = if (prompt.answer.isBlank()) TextHint else TextPrimary, lineHeight = 22.sp)
                }
                Column(modifier = Modifier.padding(top = 8.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    IconButton(onClick = { onEdit(prompt) }, modifier = Modifier.size(28.dp)) {
                        Icon(Icons.Default.Edit, null, tint = TextHint, modifier = Modifier.size(13.dp))
                    }
                    IconButton(onClick = { onDelete(prompt) }, modifier = Modifier.size(28.dp)) {
                        Icon(Icons.Default.Delete, null, tint = Red.copy(0.7f), modifier = Modifier.size(13.dp))
                    }
                }
            }
        }
    }
}

// ── Interests (Manage mode) ───────────────────────────────────────────────────

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ManageInterestsSection(interests: List<String>, onEdit: () -> Unit, modifier: Modifier = Modifier) {
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
            SectionLabel("Interests", Icons.Default.AutoAwesome)
            TextButton(onClick = onEdit, contentPadding = PaddingValues(0.dp)) {
                Icon(Icons.Default.Edit, null, modifier = Modifier.size(12.dp), tint = Pink)
                Spacer(Modifier.width(4.dp))
                Text("Edit", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = Pink)
            }
        }
        if (interests.isEmpty()) {
            Box(modifier = Modifier.fillMaxWidth().background(SurfaceVariant, RoundedCornerShape(18.dp))
                .border(1.dp, Pink.copy(0.2f), RoundedCornerShape(18.dp))
                .clickable { onEdit() }.padding(vertical = 20.dp), contentAlignment = Alignment.Center) {
                Text("Add your interests", fontSize = 14.sp, color = TextSecondary)
            }
        } else {
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                interests.forEach { interest ->
                    val (c1, c2) = interestGradientPair(interest)
                    Row(
                        modifier = Modifier.background(c1.copy(0.10f), RoundedCornerShape(50))
                            .border(1.dp, c1.copy(0.28f), RoundedCornerShape(50))
                            .padding(horizontal = 14.dp, vertical = 8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        Icon(interestIcon(interest), null, tint = c1, modifier = Modifier.size(13.dp))
                        Text(interest, fontSize = 13.sp, fontWeight = FontWeight.Medium,
                            style = androidx.compose.ui.text.TextStyle(brush = Brush.linearGradient(listOf(c1, c2))))
                    }
                }
            }
        }
    }
}

// ── Settings ──────────────────────────────────────────────────────────────────

@Composable
private fun SettingsSection(
    onLogout: () -> Unit, onDeleteAccount: () -> Unit,
    onPreferences: () -> Unit, onNotifications: () -> Unit,
    onPrivacy: () -> Unit, onHelpSupport: () -> Unit,
    isDeleting: Boolean, modifier: Modifier = Modifier
) {
    Column(modifier = modifier.fillMaxWidth().padding(bottom = 40.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Column(modifier = Modifier.padding(horizontal = 20.dp)
            .background(Surface, RoundedCornerShape(18.dp))
            .border(1.dp, Color.White.copy(0.05f), RoundedCornerShape(18.dp))) {
            SettingsRow(Icons.Default.Notifications, "Notifications", Purple, onNotifications)
            HorizontalDivider(Modifier.padding(start = 60.dp), color = Color.White.copy(0.06f))
            SettingsRow(Icons.Default.Tune, "Dating Preferences", Green, onPreferences)
            HorizontalDivider(Modifier.padding(start = 60.dp), color = Color.White.copy(0.06f))
            SettingsRow(Icons.Default.Lock, "Privacy", Pink, onPrivacy)
            HorizontalDivider(Modifier.padding(start = 60.dp), color = Color.White.copy(0.06f))
            SettingsRow(Icons.Default.HelpOutline, "Help & Support", Purple, onHelpSupport)
        }
        Column(modifier = Modifier.padding(horizontal = 20.dp)
            .background(Surface, RoundedCornerShape(18.dp))
            .border(1.dp, Red.copy(0.12f), RoundedCornerShape(18.dp))) {
            Row(modifier = Modifier.fillMaxWidth().padding(horizontal = 18.dp, vertical = 14.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                Box(modifier = Modifier.size(36.dp).background(Red.copy(0.12f), RoundedCornerShape(10.dp)),
                    contentAlignment = Alignment.Center) {
                    Icon(Icons.AutoMirrored.Filled.ExitToApp, null, tint = Red, modifier = Modifier.size(17.dp))
                }
                TextButton(onClick = onLogout, contentPadding = PaddingValues(0.dp)) {
                    Text("Sign Out", fontSize = 16.sp, fontWeight = FontWeight.Medium, color = Red)
                }
            }
            HorizontalDivider(Modifier.padding(start = 68.dp), color = Color.White.copy(0.06f))
            Row(modifier = Modifier.fillMaxWidth().padding(horizontal = 18.dp, vertical = 14.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                Box(modifier = Modifier.size(36.dp).background(Red.copy(0.12f), RoundedCornerShape(10.dp)),
                    contentAlignment = Alignment.Center) {
                    Icon(Icons.Default.Delete, null, tint = Red, modifier = Modifier.size(17.dp))
                }
                Column(modifier = Modifier.weight(1f)) {
                    TextButton(onClick = onDeleteAccount, enabled = !isDeleting, contentPadding = PaddingValues(0.dp)) {
                        Text("Delete Account", fontSize = 16.sp, fontWeight = FontWeight.Medium, color = Red)
                    }
                    Text("Permanently removed after 24 h", fontSize = 11.sp, color = TextHint)
                }
                if (isDeleting) CircularProgressIndicator(color = Red, modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
            }
        }
    }
}

@Composable
private fun SettingsRow(icon: ImageVector, label: String, color: Color, onClick: () -> Unit) {
    Row(modifier = Modifier.fillMaxWidth().clickable { onClick() }.padding(horizontal = 18.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        Box(modifier = Modifier.size(36.dp).background(color.copy(0.12f), RoundedCornerShape(10.dp)),
            contentAlignment = Alignment.Center) {
            Icon(icon, null, tint = color, modifier = Modifier.size(15.dp))
        }
        Text(label, fontSize = 15.sp, fontWeight = FontWeight.Medium, color = TextPrimary, modifier = Modifier.weight(1f))
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = TextHint, modifier = Modifier.size(16.dp))
    }
}

// ── Shared components ─────────────────────────────────────────────────────────

@Composable
private fun ProfileModePicker(isViewMode: Boolean, onModeChange: (Boolean) -> Unit, modifier: Modifier = Modifier) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .shadow(12.dp, RoundedCornerShape(14.dp), clip = false)
            .background(CardBackground, RoundedCornerShape(14.dp))
            .border(1.dp, Color.White.copy(0.07f), RoundedCornerShape(14.dp))
            .padding(4.dp)
    ) {
        listOf(true to Pair(Icons.Default.Visibility, "View"), false to Pair(Icons.Default.Tune, "Manage"))
            .forEach { (isView, item) ->
                val selected = isViewMode == isView
                val (icon, label) = item
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .height(40.dp)
                        .graphicsLayer {
                            if (selected) {
                                shadowElevation = 8.dp.toPx()
                                shape = RoundedCornerShape(10.dp)
                                clip = true
                            }
                        }
                        .background(if (selected) SurfaceElevated else Color.Transparent, RoundedCornerShape(10.dp))
                        .clickable { onModeChange(isView) },
                    contentAlignment = Alignment.Center
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Icon(icon, null, tint = if (selected) Color.White else TextSecondary, modifier = Modifier.size(12.dp))
                        Text(label, fontSize = 14.sp, fontWeight = FontWeight.Bold, color = if (selected) Color.White else TextSecondary)
                    }
                }
            }
    }
}

@Composable
private fun SectionLabel(title: String, icon: ImageVector, modifier: Modifier = Modifier) {
    Row(modifier = modifier, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(7.dp)) {
        Icon(icon, null, modifier = Modifier.size(15.dp), tint = Pink)
        Text(title, fontSize = 17.sp, fontWeight = FontWeight.Bold, color = TextPrimary)
    }
}

@Composable
private fun StaggeredItem(appeared: Boolean, index: Int, content: @Composable () -> Unit) {
    var visible by remember { mutableStateOf(false) }
    LaunchedEffect(appeared) {
        if (appeared) { kotlinx.coroutines.delay(index * 90L); visible = true }
    }
    AnimatedVisibility(visible, enter = slideInVertically(spring(dampingRatio = 0.72f)) { it / 3 } + fadeIn(tween(260))) {
        content()
    }
}

// ── Shimmer ───────────────────────────────────────────────────────────────────

@Composable
private fun ProfileShimmer() {
    val transition = rememberInfiniteTransition(label = "shimmer")
    val shimmerX by transition.animateFloat(
        initialValue = -300f, targetValue = 1200f,
        animationSpec = infiniteRepeatable(tween(1200, easing = LinearEasing)), label = "shimmerX"
    )
    val shimmerBrush = Brush.linearGradient(
        listOf(SurfaceVariant, SurfaceVariant.copy(0.4f), SurfaceVariant),
        start = androidx.compose.ui.geometry.Offset(shimmerX, 0f),
        end = androidx.compose.ui.geometry.Offset(shimmerX + 300f, 300f)
    )
    @Composable fun ShimmerBox(m: Modifier) = Box(modifier = m.background(shimmerBrush, RoundedCornerShape(12.dp)))
    Column(modifier = Modifier.fillMaxWidth().padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            ShimmerBox(Modifier.size(88.dp).clip(CircleShape))
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                ShimmerBox(Modifier.width(140.dp).height(20.dp))
                ShimmerBox(Modifier.width(100.dp).height(14.dp))
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) { repeat(3) { ShimmerBox(Modifier.weight(1f).height(80.dp)) } }
        ShimmerBox(Modifier.fillMaxWidth().height(80.dp))
        ShimmerBox(Modifier.fillMaxWidth().height(180.dp))
    }
}

// ── Helper functions (mirror iOS cleanedProfession, etc.) ─────────────────────

private val INVALID_VALUES = setOf("other", "others", "na", "n/a", "none", "null", "nil",
    "prefer not to say", "not specified", "unknown", "-")

private fun cleanProfileValue(value: String): String? {
    val t = value.trim()
    return if (t.isEmpty() || INVALID_VALUES.contains(t.lowercase())) null else t
}

private fun cleanedProfession(profile: UserProfile) = cleanProfileValue(profile.profession)
private fun cleanedLookingFor(profile: UserProfile) = cleanProfileValue(profile.lookingFor)
private fun cleanedGender(profile: UserProfile) = cleanProfileValue(profile.gender)

private fun profileCompletenessHint(profile: UserProfile): String = when {
    profile.photos.size < 3 -> "Add at least three photos so viewers can understand your vibe faster."
    profile.prompts.count { it.answer.isNotBlank() } < 2 -> "Answer another prompt to give people an easy way to start a chat."
    profile.interests.size < 4 -> "Add a few more interests to make your profile easier to connect with."
    else -> "Your profile has enough detail for a strong first impression."
}

private fun iconForProfession(profession: String): ImageVector {
    val n = profession.lowercase()
    return when {
        "chef" in n || "cook" in n -> Icons.Default.Restaurant
        "doctor" in n || "nurse" in n -> Icons.Default.LocalHospital
        "engineer" in n || "developer" in n -> Icons.Default.Construction
        "architect" in n -> Icons.Default.Apartment
        "artist" in n || "painter" in n -> Icons.Default.Palette
        "designer" in n -> Icons.Default.Draw
        "teacher" in n || "professor" in n -> Icons.Default.MenuBook
        "writer" in n || "journalist" in n -> Icons.Default.Edit
        "music" in n || "musician" in n -> Icons.Default.MusicNote
        "student" in n -> Icons.Default.School
        "lawyer" in n -> Icons.Default.Gavel
        "photographer" in n -> Icons.Default.PhotoCamera
        else -> Icons.Default.Work
    }
}

private fun interestIcon(interest: String): ImageVector = when (interest) {
    "Baking" -> Icons.Default.Cake
    "Code" -> Icons.Default.Code
    "Hiking" -> Icons.Default.Landscape
    "Concerts" -> Icons.Default.MusicNote
    "Coffee" -> Icons.Default.Coffee
    "Travel" -> Icons.Default.Flight
    "Cooking" -> Icons.Default.Restaurant
    "Yoga" -> Icons.Default.SelfImprovement
    "Books" -> Icons.Default.MenuBook
    "Photography" -> Icons.Default.PhotoCamera
    "Dogs" -> Icons.Default.Pets
    "Writing" -> Icons.Default.Edit
    "Wine" -> Icons.Default.WineBar
    else -> Icons.Default.Star
}

private fun interestGradientPair(interest: String): Pair<Color, Color> {
    val palettes = listOf(
        Pink to Purple, Purple to DeepPurple, Green to Color(0xFF00B4D8),
        Color(0xFFFF9A3C) to Pink, Color(0xFF00B4D8) to DeepPurple,
        Gold to Pink, DeepPurple to Green, Color(0xFFFF4081) to Gold
    )
    return palettes[((interest.hashCode() % palettes.size) + palettes.size) % palettes.size]
}

// ── Canvas draw helpers (orbital rings + balls) ───────────────────────────────

private fun DrawScope.drawOrbitalRing(
    cx: Float, cy: Float, radiusDp: Float, rotationDeg: Float,
    colors: List<Color>, strokeWidthDp: Float, dashOn: Float, dashOff: Float
) {
    val rPx = radiusDp.dp.toPx(); val sPx = strokeWidthDp.dp.toPx()
    val stroke = if (dashOn > 0f) Stroke(sPx, pathEffect = PathEffect.dashPathEffect(floatArrayOf(dashOn.dp.toPx(), dashOff.dp.toPx())))
                 else Stroke(sPx, cap = StrokeCap.Round)
    rotate(rotationDeg, Offset(cx, cy)) {
        drawArc(Brush.sweepGradient(colors, Offset(cx, cy)), 0f, 360f, false,
            Offset(cx - rPx, cy - rPx), Size(rPx * 2, rPx * 2), style = stroke)
    }
}

private fun DrawScope.drawOrbitBall(cx: Float, cy: Float, radiusDp: Float, angleDeg: Float, color: Color, ballSizeDp: Float, spinMultiplier: Float) {
    val rPx = radiusDp.dp.toPx(); val ballR = ballSizeDp.dp.toPx() / 2f
    val rad = Math.toRadians(angleDeg.toDouble())
    val pos = Offset(cx + (rPx * cos(rad)).toFloat(), cy + (rPx * sin(rad)).toFloat())
    val rad1 = Math.toRadians((angleDeg - 18.0)); val rad2 = Math.toRadians((angleDeg - 34.0))
    val tail1 = Offset(cx + (rPx * cos(rad1)).toFloat(), cy + (rPx * sin(rad1)).toFloat())
    val tail2 = Offset(cx + (rPx * cos(rad2)).toFloat(), cy + (rPx * sin(rad2)).toFloat())
    val nc = drawContext.canvas.nativeCanvas
    nc.drawCircle(tail2.x, tail2.y, ballR * 0.45f, android.graphics.Paint().apply {
        isAntiAlias = true; style = android.graphics.Paint.Style.FILL
        this.color = color.copy(0.20f).toArgb()
        maskFilter = android.graphics.BlurMaskFilter(4f.dp.toPx(), android.graphics.BlurMaskFilter.Blur.NORMAL)
    })
    nc.drawCircle(tail1.x, tail1.y, ballR * 0.65f, android.graphics.Paint().apply {
        isAntiAlias = true; style = android.graphics.Paint.Style.FILL
        this.color = color.copy(0.35f).toArgb()
        maskFilter = android.graphics.BlurMaskFilter(3f.dp.toPx(), android.graphics.BlurMaskFilter.Blur.NORMAL)
    })
    nc.drawCircle(pos.x, pos.y, ballR + 4.dp.toPx(), android.graphics.Paint().apply {
        isAntiAlias = true; style = android.graphics.Paint.Style.FILL
        this.color = color.copy(0.55f).toArgb()
        maskFilter = android.graphics.BlurMaskFilter(10f.dp.toPx(), android.graphics.BlurMaskFilter.Blur.NORMAL)
    })
    rotate(angleDeg * spinMultiplier, pos) {
        drawCircle(Brush.sweepGradient(listOf(color, Color.White.copy(0.9f), color.copy(0.5f), color, color), pos), ballR, pos)
    }
    drawCircle(Brush.radialGradient(listOf(Color.White.copy(0.85f), Color.Transparent),
        Offset(pos.x - ballR * 0.40f, pos.y - ballR * 0.50f), ballR), ballR, pos)
}
