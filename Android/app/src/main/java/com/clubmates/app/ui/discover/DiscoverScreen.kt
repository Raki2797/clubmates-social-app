package com.clubmates.app.ui.discover

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ExitToApp
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.ButtonDefaults
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.hilt.navigation.compose.hiltViewModel
import com.clubmates.app.domain.model.Match
import com.clubmates.app.domain.model.SwipeDirection
import com.clubmates.app.domain.model.UserProfile
import com.clubmates.app.ui.components.AvatarImage
import com.clubmates.app.ui.matches.IncomingLikeBanner
import com.clubmates.app.ui.safety.SOSButton
import com.clubmates.app.ui.theme.*
import kotlin.math.abs
import kotlin.math.roundToInt

@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
fun DiscoverScreen(
    onOpenMatchChat: (Match) -> Unit,
    viewModel: DiscoverViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    var showVenuePicker by remember { mutableStateOf(false) }
    var inviteProfile by remember { mutableStateOf<UserProfile?>(null) }
    var showCheckOutConfirmation by remember { mutableStateOf(false) }
    val venuePickerSheetState = rememberModalBottomSheetState(skipPartiallyExpanded = false)

    // Treat invite sheet
    inviteProfile?.let { profile ->
        androidx.compose.material3.ModalBottomSheet(
            onDismissRequest = { inviteProfile = null },
            containerColor = SurfaceVariant
        ) {
            TreatInviteSheet(
                profile = profile,
                onSelect = { treat ->
                    viewModel.sendInvite(profile.id, treat)
                    inviteProfile = null
                },
                onDismiss = { inviteProfile = null }
            )
        }
    }

    // Invite error alert
    uiState.inviteError?.let { error ->
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { viewModel.clearInviteError() },
            title = { Text("Invite not sent") },
            text = { Text(error) },
            confirmButton = {
                TextButton(onClick = { viewModel.clearInviteError() }) { Text("OK") }
            },
            containerColor = CardBackground
        )
    }

    // Custom checkout overlay — matches iOS checkOutOverlay glassmorphic style
    AnimatedVisibility(
        visible = showCheckOutConfirmation,
        enter = fadeIn(spring(dampingRatio = 0.8f)) + scaleIn(spring(dampingRatio = 0.72f), initialScale = 0.9f),
        exit = fadeOut() + scaleOut(targetScale = 0.9f)
    ) {
        GlassmorphicConfirmOverlay(
            iconRes = Icons.AutoMirrored.Filled.ExitToApp,
            iconTint = Color(0xFFFF6B9D),
            iconGradient = Brush.linearGradient(listOf(Color(0xFFFF6B9D), Color(0xFFC44EFF))),
            borderGradient = Brush.linearGradient(listOf(Color.White.copy(0.12f), Color(0xFFFF6B9D).copy(0.20f), Color.White.copy(0.06f))),
            title = "Leaving already?",
            body = "You'll stop appearing in this venue's live roster until you check in again.",
            confirmLabel = "Check Out",
            cancelLabel = "Stay",
            onConfirm = { showCheckOutConfirmation = false; viewModel.checkOut() },
            onDismiss = { showCheckOutConfirmation = false }
        )
    }

    // Venue picker bottom sheet (mirrors iOS .sheet presentation)
    if (showVenuePicker) {
        LaunchedEffect(showVenuePicker) {
            viewModel.refreshVenuesForPicker()
        }
        androidx.compose.material3.ModalBottomSheet(
            onDismissRequest = { showVenuePicker = false },
            containerColor = Color.Transparent,
            sheetState = venuePickerSheetState,
            dragHandle = { BottomSheetDefaults.DragHandle(color = TextHint.copy(alpha = 0.7f)) }
        ) {
            VenuePickerScreen(
                venues = uiState.venues,
                onCheckIn = { venue ->
                    viewModel.checkIn(venue)
                    showVenuePicker = false
                },
                isLoading = uiState.isLoading,
                selectedCity = uiState.selectedCity,
                onSelectCity = { viewModel.selectCity(it) },
                activeVenueId = uiState.activeVenue?.id,
                onCheckOut = {
                    viewModel.checkOut()
                    showVenuePicker = false
                },
                onDone = { showVenuePicker = false }
            )
        }
    }

    // Roster profile full detail sheet (mirrors iOS ProfileFullDetailView)
    uiState.selectedRosterProfile?.let { profile ->
        ProfileFullDetailSheet(
            profile = profile,
            onDismiss = { viewModel.dismissRosterProfile() },
            showActions = true,
            onLike = { viewModel.swipe(profile, SwipeDirection.LIKE); viewModel.dismissRosterProfile() },
            onPass = { viewModel.swipe(profile, SwipeDirection.NOPE); viewModel.dismissRosterProfile() },
            onSuperLike = { viewModel.swipe(profile, SwipeDirection.SUPERLIKE) }
        )
    }

    Box(modifier = Modifier.fillMaxSize()) {
        VenueScreenBackground(modifier = Modifier.matchParentSize())
        Column(modifier = Modifier.fillMaxSize()) {
            // Header — always visible
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp, vertical = 8.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(
                        if (uiState.isCheckedIn) uiState.activeVenue?.name ?: "" else "Venue Discovery",
                        fontSize = 22.sp,
                        fontWeight = FontWeight.Bold,
                        color = TextPrimary,
                        maxLines = 1
                    )
                    if (uiState.isCheckedIn) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            Icon(Icons.Default.LocationOn, contentDescription = null, tint = Primary, modifier = Modifier.size(9.dp))
                            Text(
                                buildString {
                                    append(uiState.activeVenue?.neighborhood.orEmpty())
                                    uiState.activeVenue?.city?.takeIf { it.isNotBlank() }?.let { city ->
                                        if (isNotEmpty()) append(", ")
                                        append(city)
                                    }
                                }.ifBlank { "Check in is live" },
                                fontSize = 12.sp,
                                color = TextSecondary,
                                fontWeight = FontWeight.Medium
                            )
                            if (uiState.occupancy > 0) {
                                Text("•", fontSize = 12.sp, color = TextHint)
                                Row(
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(4.dp)
                                ) {
                                    Box(
                                        modifier = Modifier
                                            .size(6.dp)
                                            .background(Like, CircleShape)
                                    )
                                    Text(
                                        "${uiState.occupancy} here now",
                                        fontSize = 12.sp,
                                        fontWeight = FontWeight.SemiBold,
                                        color = Like
                                    )
                                }
                            }
                        }
                    } else {
                        Text(
                            "Pick a city, then check in to a club",
                            fontSize = 12.sp,
                            color = TextSecondary,
                            fontWeight = FontWeight.Medium
                        )
                    }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    if (uiState.isCheckedIn) {
                        HeaderActionButton(
                            icon = Icons.AutoMirrored.Filled.Undo,
                            contentDescription = "Undo",
                            enabled = uiState.canUndo,
                            tint = if (uiState.canUndo) TextPrimary else TextHint,
                            onClick = { viewModel.undo() }
                        )
                        SOSButton(
                            source = "venue",
                            venueId = uiState.activeVenue?.id,
                            compact = true
                        )
                        HeaderActionButton(
                            icon = Icons.AutoMirrored.Filled.ExitToApp,
                            contentDescription = "Check out",
                            tint = Nope,
                            onClick = { showCheckOutConfirmation = true }
                        )
                    } else {
                        HeaderActionButton(
                            icon = Icons.Default.Business,
                            contentDescription = "Pick venue",
                            tint = Primary,
                            onClick = { showVenuePicker = true }
                        )
                    }
                }
            }

            if (uiState.isCheckedIn) {
                Box(
                    modifier = Modifier.weight(1f).fillMaxWidth().padding(horizontal = 16.dp),
                    contentAlignment = Alignment.Center
                ) {
                    if (uiState.profiles.isEmpty()) {
                        HereNowEmptyState(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 8.dp)
                        )
                    } else {
                        if (uiState.profiles.size > 1) {
                            VenueSwipeCardBody(
                                profile = uiState.profiles[1],
                                onOpenDetail = {},
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .graphicsLayer {
                                        scaleX = 0.94f
                                        scaleY = 0.94f
                                        translationY = -28f
                                        alpha = 0.62f
                                    }
                                    .padding(horizontal = 6.dp)
                                    .zIndex(0f)
                            )
                        }
                        SwipeableHereNowCard(
                            profile = uiState.profiles[0],
                            onSwipe = { viewModel.swipe(uiState.profiles[0], it) },
                            onOpenDetail = { viewModel.openRosterProfile(uiState.profiles[0]) },
                            onInvite = { inviteProfile = uiState.profiles[0] },
                            modifier = Modifier.fillMaxWidth().zIndex(1f)
                        )
                    }
                }
            } else {
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxWidth()
                        .padding(horizontal = 24.dp, vertical = 16.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Surface(
                        color = CardBackground,
                        shape = RoundedCornerShape(24.dp),
                        modifier = Modifier
                            .fillMaxWidth()
                            .border(1.dp, Surface, RoundedCornerShape(24.dp))
                    ) {
                        Column(
                            modifier = Modifier.padding(24.dp),
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(18.dp)
                        ) {
                            Box(
                                modifier = Modifier.size(104.dp).background(Surface, CircleShape),
                                contentAlignment = Alignment.Center
                            ) {
                                Icon(Icons.Default.Business, contentDescription = null, tint = Primary, modifier = Modifier.size(42.dp))
                            }

                            Column(
                                horizontalAlignment = Alignment.CenterHorizontally,
                                verticalArrangement = Arrangement.spacedBy(8.dp)
                            ) {
                                Text("Choose city and venue", fontSize = 21.sp, fontWeight = FontWeight.Bold, color = TextPrimary)
                                Text(
                                    "Check in to see who's at the same club and start venue-based matching.",
                                    fontSize = 14.sp,
                                    color = TextSecondary,
                                    textAlign = TextAlign.Center,
                                    lineHeight = 20.sp
                                )
                            }

                            Button(
                                onClick = { showVenuePicker = true },
                                enabled = !uiState.isCheckingIn,
                                contentPadding = PaddingValues(),
                                colors = ButtonDefaults.buttonColors(
                                    containerColor = Color.Transparent,
                                    disabledContainerColor = Color.Transparent
                                ),
                                modifier = Modifier.fillMaxWidth()
                            ) {
                                Box(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .background(
                                            Brush.horizontalGradient(listOf(Primary, PrimaryVariant)),
                                            RoundedCornerShape(999.dp)
                                        )
                                        .padding(vertical = 16.dp),
                                    contentAlignment = Alignment.Center
                                ) {
                                    Row(
                                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                                        verticalAlignment = Alignment.CenterVertically
                                    ) {
                                        if (uiState.isCheckingIn) {
                                            CircularProgressIndicator(
                                                modifier = Modifier.size(18.dp),
                                                color = Color.White,
                                                strokeWidth = 2.dp
                                            )
                                        } else {
                                            Icon(Icons.Default.LocationOn, contentDescription = null, tint = Color.White, modifier = Modifier.size(18.dp))
                                        }
                                        Text(
                                            if (uiState.isCheckingIn) "Verifying location..." else "Check in now",
                                            fontWeight = FontWeight.SemiBold,
                                            color = Color.White
                                        )
                                    }
                                }
                            }

                            uiState.checkInError?.let { checkInError ->
                                Text(
                                    checkInError,
                                    fontSize = 12.sp,
                                    fontWeight = FontWeight.Medium,
                                    color = Nope,
                                    textAlign = TextAlign.Center
                                )
                            }
                        }
                    }
                }
            }
        }

        // Match alert
        uiState.matchResult?.let { result ->
            MatchAlertDialog(
                profile = result.profile,
                onDismiss = { viewModel.dismissMatch() },
                onSendMessage = {
                    val match = Match(
                        id = result.matchId,
                        profile = result.profile,
                        venueId = uiState.activeVenue?.id,
                        lastMessage = "It's a match!",
                        lastMessageAt = System.currentTimeMillis().toString(),
                        unreadCount = 0,
                        isNew = true
                    )
                    viewModel.dismissMatch()
                    onOpenMatchChat(match)
                }
            )
        }
    }
}

@Composable
private fun HereNowEmptyState(modifier: Modifier = Modifier) {
    Surface(
        modifier = modifier,
        color = CardBackground,
        shape = RoundedCornerShape(24.dp)
    ) {
        Column(
            modifier = Modifier.padding(horizontal = 28.dp, vertical = 32.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(18.dp)
        ) {
            Box(
                modifier = Modifier
                    .size(100.dp)
                    .background(Surface, CircleShape),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    Icons.Default.People,
                    contentDescription = null,
                    tint = Primary,
                    modifier = Modifier.size(40.dp)
                )
            }

            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Text(
                    "No new people right now",
                    color = TextPrimary,
                    fontSize = 20.sp,
                    fontWeight = FontWeight.Bold
                )
                Text(
                    "You've seen everyone currently at this venue. Stay checked in for new arrivals.",
                    color = TextSecondary,
                    fontSize = 14.sp,
                    lineHeight = 20.sp,
                    textAlign = TextAlign.Center
                )
            }
        }
    }
}

@Composable
fun VenueScreenBackground(modifier: Modifier = Modifier) {
    Box(modifier = modifier) {
        Box(
            modifier = Modifier
                .matchParentSize()
                .background(
                    Brush.verticalGradient(
                        colors = listOf(
                            Color(0xFF0D0B1E),
                            Color(0xFF1A0D2E),
                            Color(0xFF0D0D0F)
                        )
                    )
                )
        )
        Box(
            modifier = Modifier
                .size(260.dp)
                .offset(x = (-90).dp, y = (-70).dp)
                .background(
                    Brush.radialGradient(
                        colors = listOf(
                            Color(0xFF7C3AED).copy(alpha = 0.34f),
                            Color(0xFF7C3AED).copy(alpha = 0.12f),
                            Color.Transparent
                        )
                    ),
                    CircleShape
                )
        )
        Box(
            modifier = Modifier
                .size(220.dp)
                .offset(x = 110.dp, y = 16.dp)
                .background(
                    Brush.radialGradient(
                        colors = listOf(
                            Primary.copy(alpha = 0.24f),
                            Primary.copy(alpha = 0.08f),
                            Color.Transparent
                        )
                    ),
                    CircleShape
                )
        )
        Box(
            modifier = Modifier
                .size(180.dp)
                .offset(x = 22.dp, y = 84.dp)
                .background(
                    Brush.radialGradient(
                        colors = listOf(
                            Color(0xFFC44EFF).copy(alpha = 0.16f),
                            Color(0xFFC44EFF).copy(alpha = 0.05f),
                            Color.Transparent
                        )
                    ),
                    CircleShape
                )
        )
        Box(
            modifier = Modifier
                .matchParentSize()
                .background(Color.White.copy(alpha = 0.015f))
        )
    }
}

@Composable
private fun VenueRosterSection(
    roster: List<UserProfile>,
    venueEvent: String,
    onProfileClick: (UserProfile) -> Unit,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier
            .background(SurfaceVariant.copy(alpha = 0.7f), RoundedCornerShape(18.dp))
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text("Here Now", fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = TextPrimary)
            Text("${roster.size} people", fontSize = 12.sp, color = TextSecondary)
        }

        if (roster.isEmpty()) {
            Text(
                "No one has checked in yet. Keep your check-in active and we'll show people here in real time.",
                fontSize = 12.sp,
                color = TextSecondary,
                lineHeight = 18.sp
            )
        } else {
            LazyRow(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                items(roster, key = { it.id }) { profile ->
                    Column(
                        modifier = Modifier.clickable { onProfileClick(profile) },
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        AvatarImage(photoUrl = profile.photos.firstOrNull()?.cdnUrl, size = 46.dp)
                        Text(
                            profile.name,
                            fontSize = 11.sp,
                            color = TextSecondary,
                            maxLines = 1
                        )
                    }
                }
            }
        }

        AnimatedVisibility(visible = venueEvent.isNotBlank(), enter = fadeIn()) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(Icons.Default.Bolt, contentDescription = null, tint = Color(0xFFFFC857), modifier = Modifier.size(14.dp))
                Text(
                    venueEvent,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Medium,
                    color = TextSecondary
                )
            }
        }
    }
}

@Composable
private fun HeaderActionButton(
    icon: ImageVector,
    contentDescription: String,
    enabled: Boolean = true,
    tint: Color = TextPrimary,
    onClick: () -> Unit
) {
    IconButton(
        onClick = onClick,
        enabled = enabled,
        modifier = Modifier
            .size(36.dp)
            .background(Surface, CircleShape)
    ) {
        Icon(
            icon,
            contentDescription = contentDescription,
            tint = tint,
            modifier = Modifier.size(14.dp)
        )
    }
}

@Composable
private fun VenueSwipeCardBody(
    profile: UserProfile,
    onOpenDetail: () -> Unit,
    modifier: Modifier = Modifier
) {
    Box(
        modifier = modifier
            .shadow(24.dp, RoundedCornerShape(34.dp), clip = false)
            .background(SurfaceVariant.copy(alpha = 0.96f), RoundedCornerShape(34.dp))
            .clip(RoundedCornerShape(34.dp))
            .padding(12.dp)
    ) {
        ProfileCard(
            profile = profile,
            modifier = Modifier.fillMaxWidth()
        )
        Box(
            modifier = Modifier
                .align(Alignment.TopEnd)
                .padding(18.dp)
                .size(42.dp)
                .background(Color.Black.copy(alpha = 0.30f), CircleShape)
                .border(1.dp, Color.White.copy(alpha = 0.14f), CircleShape)
                .clickable(onClick = onOpenDetail),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                Icons.Default.KeyboardArrowDown,
                contentDescription = "Open details",
                tint = Color.White,
                modifier = Modifier.size(22.dp)
            )
        }
    }
}

@Composable
private fun HeroMetaLabel(
    text: String,
    icon: ImageVector,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            icon,
            contentDescription = null,
            tint = Color.White.copy(alpha = 0.82f),
            modifier = Modifier.size(14.dp)
        )
        Text(
            text,
            color = Color.White.copy(alpha = 0.82f),
            fontSize = 13.sp,
            fontWeight = FontWeight.SemiBold,
            maxLines = 1
        )
    }
}

@Composable
private fun HereNowActionButton(
    icon: ImageVector,
    label: String,
    gradient: Brush,
    shadowColor: Color,
    onClick: () -> Unit
) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
        modifier = Modifier.clickable(onClick = onClick)
    ) {
        Box(
            modifier = Modifier
                .size(54.dp)
                .shadow(
                    elevation = 14.dp,
                    shape = CircleShape,
                    clip = false,
                    ambientColor = shadowColor.copy(alpha = 0.45f),
                    spotColor = shadowColor.copy(alpha = 0.45f)
                )
                .background(gradient, CircleShape),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                icon,
                contentDescription = label,
                tint = Color.White,
                modifier = Modifier.size(20.dp)
            )
        }
        Text(
            label,
            color = TextSecondary,
            fontSize = 11.sp,
            fontWeight = FontWeight.SemiBold
        )
    }
}

@Composable
private fun SwipeableHereNowCard(
    profile: UserProfile,
    onSwipe: (SwipeDirection) -> Unit,
    onOpenDetail: () -> Unit,
    onInvite: () -> Unit,
    modifier: Modifier = Modifier
) {
    var offsetX by remember { mutableFloatStateOf(0f) }
    var offsetY by remember { mutableFloatStateOf(0f) }
    var isDragging by remember { mutableStateOf(false) }

    val animatedOffsetX by animateFloatAsState(
        targetValue = if (isDragging) offsetX else 0f,
        animationSpec = spring(dampingRatio = 0.7f), label = "offsetX"
    )
    val animatedOffsetY by animateFloatAsState(
        targetValue = if (isDragging) offsetY else 0f,
        animationSpec = spring(dampingRatio = 0.7f), label = "offsetY"
    )

    val rotation = animatedOffsetX / 30f
    val likeOpacity = (animatedOffsetX / 150f).coerceIn(0f, 1f)
    val nopeOpacity = (-animatedOffsetX / 150f).coerceIn(0f, 1f)
    val superLikeOpacity = if (abs(animatedOffsetX) < 60) (-animatedOffsetY / 150f).coerceIn(0f, 1f) else 0f

    Box(
        modifier = modifier
            .offset { IntOffset(animatedOffsetX.roundToInt(), animatedOffsetY.roundToInt()) }
            .rotate(rotation)
            .pointerInput(Unit) {
                detectDragGestures(
                    onDragStart = { isDragging = true },
                    onDragEnd = {
                        isDragging = false
                        when {
                            offsetX > 110 -> { offsetX = 0f; offsetY = 0f; onSwipe(SwipeDirection.LIKE) }
                            offsetX < -110 -> { offsetX = 0f; offsetY = 0f; onSwipe(SwipeDirection.NOPE) }
                            offsetY < -130 && abs(offsetX) < 60 -> { offsetX = 0f; offsetY = 0f; onSwipe(SwipeDirection.SUPERLIKE) }
                            else -> { offsetX = 0f; offsetY = 0f }
                        }
                    },
                    onDragCancel = { isDragging = false; offsetX = 0f; offsetY = 0f },
                    onDrag = { _, dragAmount -> offsetX += dragAmount.x; offsetY += dragAmount.y }
                )
            }
    ) {
        VenueSwipeCardBody(
            profile = profile,
            onOpenDetail = onOpenDetail,
            modifier = Modifier
                .fillMaxWidth()
        )

        VenueActionDock(
            onPass = { onSwipe(SwipeDirection.NOPE) },
            onInvite = onInvite,
            onLike = { onSwipe(SwipeDirection.LIKE) },
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(horizontal = 24.dp, vertical = 24.dp)
        )

        if (likeOpacity > 0) {
            Box(
                modifier = Modifier.align(Alignment.TopStart).padding(24.dp)
                    .graphicsLayer { alpha = likeOpacity }
                    .rotate((-22).toFloat())
                    .shadow(12.dp, RoundedCornerShape(10.dp), ambientColor = Like.copy(alpha = 0.5f), spotColor = Like.copy(alpha = 0.5f))
                    .background(Like.copy(alpha = 0.85f), RoundedCornerShape(10.dp))
                    .border(2.5.dp, Like, RoundedCornerShape(10.dp))
                    .padding(horizontal = 14.dp, vertical = 7.dp)
            ) { Text("LIKE", color = Color.White, fontWeight = FontWeight.Black, fontSize = 28.sp, letterSpacing = 1.sp) }
        }
        if (nopeOpacity > 0) {
            Box(
                modifier = Modifier.align(Alignment.TopEnd).padding(24.dp)
                    .graphicsLayer { alpha = nopeOpacity }
                    .rotate(22f)
                    .shadow(12.dp, RoundedCornerShape(10.dp), ambientColor = Nope.copy(alpha = 0.5f), spotColor = Nope.copy(alpha = 0.5f))
                    .background(Nope.copy(alpha = 0.85f), RoundedCornerShape(10.dp))
                    .border(2.5.dp, Nope, RoundedCornerShape(10.dp))
                    .padding(horizontal = 14.dp, vertical = 7.dp)
            ) { Text("NOPE", color = Color.White, fontWeight = FontWeight.Black, fontSize = 28.sp, letterSpacing = 1.sp) }
        }
        if (superLikeOpacity > 0) {
            Box(
                modifier = Modifier.align(Alignment.TopCenter).padding(top = 24.dp)
                    .graphicsLayer { alpha = superLikeOpacity }
                    .shadow(12.dp, RoundedCornerShape(10.dp), ambientColor = SuperLike.copy(alpha = 0.5f), spotColor = SuperLike.copy(alpha = 0.5f))
                    .background(SuperLike.copy(alpha = 0.85f), RoundedCornerShape(10.dp))
                    .border(2.5.dp, SuperLike, RoundedCornerShape(10.dp))
                    .padding(horizontal = 14.dp, vertical = 7.dp)
            ) { Text("SUPER", color = Color.White, fontWeight = FontWeight.Black, fontSize = 28.sp, letterSpacing = 1.sp) }
        }
    }
}

@Composable
private fun VenueActionDock(
    onPass: () -> Unit,
    onInvite: () -> Unit,
    onLike: () -> Unit,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier
            .background(
                Brush.linearGradient(
                    listOf(Color(0xFF14141E).copy(alpha = 0.82f), Color(0xFF14141E).copy(alpha = 0.82f))
                ),
                RoundedCornerShape(50)
            )
            .border(
                1.dp,
                Brush.linearGradient(listOf(Color.White.copy(alpha = 0.14f), Primary.copy(alpha = 0.20f), Color(0xFFC44EFF).copy(alpha = 0.14f))),
                RoundedCornerShape(50)
            )
            .padding(horizontal = 24.dp, vertical = 14.dp),
        horizontalArrangement = Arrangement.spacedBy(18.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        VenueDockButton(
            icon = Icons.Default.Close,
            tint = TextSecondary,
            borderBrush = Brush.linearGradient(listOf(Color.White.copy(alpha = 0.12f), Color.White.copy(alpha = 0.12f))),
            onClick = onPass
        )
        VenueDockButton(
            icon = Icons.Default.CardGiftcard,
            tint = SuperLike,
            borderBrush = Brush.linearGradient(listOf(Color(0xFFFFD56B).copy(alpha = 0.4f), SuperLike.copy(alpha = 0.3f))),
            onClick = onInvite
        )
        VenueDockButton(
            icon = Icons.Default.Favorite,
            tint = Color.White,
            fillBrush = Brush.linearGradient(listOf(Primary, Color(0xFFC44EFF))),
            onClick = onLike,
            size = 64.dp,
            iconSize = 22.dp
        )
    }
}

@Composable
private fun VenueDockButton(
    icon: ImageVector,
    tint: Color,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    fillBrush: Brush? = null,
    borderBrush: Brush? = null,
    size: Dp = 52.dp,
    iconSize: Dp = 20.dp
) {
    Box(
        modifier = modifier
            .size(size)
            .background(fillBrush ?: Brush.linearGradient(listOf(Color.White.copy(alpha = 0.08f), Color.White.copy(alpha = 0.08f))), CircleShape)
            .then(
                if (borderBrush != null) Modifier.border(1.dp, borderBrush, CircleShape)
                else Modifier
            )
            .clickable(
                indication = null,
                interactionSource = remember { MutableInteractionSource() }
            ) { onClick() },
        contentAlignment = Alignment.Center
    ) {
        Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(iconSize))
    }
}

private fun cleanProfession(profile: UserProfile): String? {
    val invalid = setOf(
        "other",
        "others",
        "na",
        "n/a",
        "none",
        "null",
        "nil",
        "prefer not to say",
        "not specified",
        "unknown",
        "-"
    )
    val value = profile.profession.trim()
    return value.takeIf { it.isNotBlank() && it.lowercase() !in invalid }
}

private fun professionIcon(profile: UserProfile): ImageVector {
    val profession = cleanProfession(profile)?.lowercase().orEmpty()
    return when {
        "chef" in profession -> Icons.Default.Restaurant
        "architect" in profession -> Icons.Default.Apartment
        "doctor" in profession -> Icons.Default.LocalHospital
        "engineer" in profession -> Icons.Default.Handyman
        "artist" in profession -> Icons.Default.Palette
        "designer" in profession -> Icons.Default.Draw
        "teacher" in profession -> Icons.Default.MenuBook
        "student" in profession -> Icons.Default.School
        else -> Icons.Default.Work
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ProfileCard(profile: UserProfile, modifier: Modifier = Modifier) {
    val pink = Color(0xFFFF6B9D)
    val purple = Color(0xFFC44EFF)
    var selectedPhotoIndex by remember { mutableIntStateOf(0) }
    var expandedPromptId by remember { mutableStateOf<String?>(null) }

    val photos = profile.photos.takeIf { it.isNotEmpty() }
    val gradientColors = listOf(Color(0xFF1A0A2E), Color(0xFF0D0D1A))

    Column(
        modifier = modifier
            .background(CardBackground, RoundedCornerShape(20.dp))
            .clip(RoundedCornerShape(20.dp))
    ) {
        // ── Hero photo ───────────────────────────────────────────────────────
        Box(modifier = Modifier.fillMaxWidth().height(400.dp)) {
            if (photos != null) {
                val photoUrl = photos.getOrNull(selectedPhotoIndex)?.cdnUrl
                    ?: photos.firstOrNull()?.cdnUrl
                coil.compose.AsyncImage(
                    model = photoUrl,
                    contentDescription = profile.name,
                    contentScale = androidx.compose.ui.layout.ContentScale.Crop,
                    modifier = Modifier.fillMaxSize()
                )
                // Photo dots indicator
                if (photos.size > 1) {
                    Row(
                        modifier = Modifier.align(Alignment.TopCenter).padding(top = 12.dp),
                        horizontalArrangement = Arrangement.spacedBy(4.dp)
                    ) {
                        photos.forEachIndexed { i, _ ->
                            Box(
                                modifier = Modifier
                                    .size(if (i == selectedPhotoIndex) 6.dp else 4.dp)
                                    .background(
                                        if (i == selectedPhotoIndex) Color.White else Color.White.copy(alpha = 0.5f),
                                        CircleShape
                                    )
                            )
                        }
                    }
                    // Left/right tap areas to switch photos
                    Row(modifier = Modifier.fillMaxSize()) {
                        Box(modifier = Modifier.weight(1f).fillMaxHeight().clickable {
                            if (selectedPhotoIndex > 0) selectedPhotoIndex--
                        })
                        Box(modifier = Modifier.weight(1f).fillMaxHeight().clickable {
                            if (selectedPhotoIndex < photos.size - 1) selectedPhotoIndex++
                        })
                    }
                }
            } else {
                Box(
                    modifier = Modifier.fillMaxSize().background(Brush.linearGradient(gradientColors)),
                    contentAlignment = Alignment.Center
                ) { AvatarImage(photoUrl = null, size = 100.dp) }
            }

            // Bottom gradient scrim
            Box(
                modifier = Modifier.fillMaxWidth().height(160.dp).align(Alignment.BottomCenter)
                    .background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.9f))))
            )

            // Name / age / info overlay
            Column(
                modifier = Modifier.align(Alignment.BottomStart).padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("${profile.name}, ${profile.age}", fontSize = 26.sp, fontWeight = FontWeight.Bold, color = Color.White)
                    if (profile.isVerified) Icon(Icons.Default.CheckCircle, contentDescription = "Verified", tint = pink, modifier = Modifier.size(18.dp))
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    if (profile.profession.isNotBlank()) {
                        InfoPill(text = profile.profession, icon = Icons.Default.Work, tint = purple.copy(alpha = 0.9f))
                    }
                    if (profile.height > 0) {
                        InfoPill(text = "${profile.height} cm", icon = Icons.Default.Height, tint = Color(0xFF00E5A0).copy(alpha = 0.9f))
                    }
                    if (profile.distance > 0) {
                        val distText = if (profile.distance < 0.2) "Nearby" else "${"%.1f".format(profile.distance)} km"
                        InfoPill(text = distText, icon = Icons.Default.LocationOn, tint = Color.White.copy(alpha = 0.7f))
                    }
                }
                if (profile.lookingFor.isNotBlank()) {
                    Box(
                        modifier = Modifier
                            .background(Color.White.copy(alpha = 0.15f), RoundedCornerShape(50))
                            .padding(horizontal = 10.dp, vertical = 3.dp)
                    ) { Text(profile.lookingFor, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = Color.White) }
                }
                if (profile.hasSuperLikedMe) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        Icon(Icons.Default.Star, contentDescription = null, tint = SuperLike, modifier = Modifier.size(14.dp))
                        Text("Super liked you", fontSize = 12.sp, color = SuperLike)
                    }
                }
            }
        }

        // ── Scrollable info panel ─────────────────────────────────────────────
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .background(CardBackground)
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            // Bio
            if (profile.bio.isNotBlank()) {
                Text(profile.bio, fontSize = 14.sp, color = TextSecondary, lineHeight = 20.sp, maxLines = 3)
            }

            // Interests
            if (profile.interests.isNotEmpty()) {
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    profile.interests.take(6).forEachIndexed { idx, interest ->
                        val (c1, c2) = cardInterestGradient(interest)
                        var visible by remember { mutableStateOf(false) }
                        LaunchedEffect(Unit) {
                            kotlinx.coroutines.delay(idx * 55L)
                            visible = true
                        }
                        androidx.compose.animation.AnimatedVisibility(
                            visible = visible,
                            enter = androidx.compose.animation.scaleIn(
                                androidx.compose.animation.core.spring(dampingRatio = 0.65f)
                            ) + androidx.compose.animation.fadeIn()
                        ) {
                            Box(
                                modifier = Modifier
                                    .background(c1.copy(alpha = 0.10f), RoundedCornerShape(50))
                                    .border(1.dp, c1.copy(alpha = 0.28f), RoundedCornerShape(50))
                                    .padding(horizontal = 10.dp, vertical = 5.dp)
                            ) {
                                Text(interest, fontSize = 12.sp, fontWeight = FontWeight.Medium,
                                    style = androidx.compose.ui.text.TextStyle(
                                        brush = Brush.linearGradient(listOf(c1, c2))
                                    ))
                            }
                        }
                    }
                }
            }

            // Prompts — expandable
            profile.prompts.take(2).forEach { prompt ->
                val isExpanded = expandedPromptId == prompt.id
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(SurfaceVariant, RoundedCornerShape(12.dp))
                        .clickable { expandedPromptId = if (isExpanded) null else prompt.id }
                        .padding(12.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(prompt.question.uppercase(), fontSize = 10.sp, fontWeight = FontWeight.Bold,
                            color = pink, letterSpacing = 0.6.sp, modifier = Modifier.weight(1f))
                        Icon(
                            if (isExpanded) Icons.Default.KeyboardArrowUp else Icons.Default.KeyboardArrowDown,
                            contentDescription = null, tint = TextHint, modifier = Modifier.size(16.dp)
                        )
                    }
                    if (isExpanded || prompt.answer.length <= 60) {
                        Text(prompt.answer, fontSize = 14.sp, color = TextPrimary, lineHeight = 20.sp)
                    } else {
                        Text(prompt.answer, fontSize = 14.sp, color = TextPrimary, lineHeight = 20.sp, maxLines = 2)
                    }
                }
            }
        }
    }
}

@Composable
private fun InfoPill(text: String, icon: androidx.compose.ui.graphics.vector.ImageVector, tint: Color) {
    Row(
        modifier = Modifier
            .background(Color.Black.copy(alpha = 0.35f), RoundedCornerShape(50))
            .padding(horizontal = 8.dp, vertical = 3.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(3.dp)
    ) {
        Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(10.dp))
        Text(text, fontSize = 11.sp, fontWeight = FontWeight.Medium, color = Color.White)
    }
}

@Composable
private fun ActionButton(
    icon: ImageVector,
    label: String,
    size: Dp,
    tint: Color,
    containerColor: Color,
    enabled: Boolean,
    onClick: () -> Unit
) {
    val alpha = if (enabled) 1f else 0.45f
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
        modifier = Modifier.alpha(alpha)
    ) {
        FloatingActionButton(
            onClick = { if (enabled) onClick() },
            modifier = Modifier
                .size(size)
                .shadow(elevation = if (enabled) 8.dp else 0.dp, shape = CircleShape),
            containerColor = containerColor,
            contentColor = tint,
            elevation = FloatingActionButtonDefaults.elevation(0.dp, 0.dp, 0.dp, 0.dp)
        ) {
            Icon(
                icon,
                contentDescription = label,
                tint = tint,
                modifier = Modifier.size(size * 0.4f)
            )
        }
        Text(
            label,
            fontSize = 11.sp,
            fontWeight = FontWeight.SemiBold,
            color = TextSecondary
        )
    }
}

private fun Modifier.alpha(alpha: Float): Modifier = this.graphicsLayer { this.alpha = alpha }

@Composable
private fun TreatInviteSheet(
    profile: UserProfile,
    onSelect: (com.clubmates.app.data.network.TreatType) -> Unit,
    onDismiss: () -> Unit
) {
    val pink = Color(0xFFFF6B9D)
    val purple = Color(0xFFC44EFF)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 20.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
            Text("Invite ${profile.name}", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = TextPrimary)
            Text("Choose a treat", fontSize = 14.sp, color = TextSecondary)
        }
        com.clubmates.app.data.network.TreatType.entries.forEach { treat ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(CardBackground, RoundedCornerShape(16.dp))
                    .border(1.dp, pink.copy(alpha = 0.15f), RoundedCornerShape(16.dp))
                    .clickable { onSelect(treat) }
                    .padding(16.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(14.dp)
            ) {
                Text(treat.emoji, fontSize = 28.sp)
                Column(modifier = Modifier.weight(1f)) {
                    Text(treat.title, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = TextPrimary)
                    Text("I'll ${treat.notificationNoun}", fontSize = 13.sp, color = TextSecondary)
                }
                Icon(Icons.Default.ChevronRight, contentDescription = null, tint = TextHint, modifier = Modifier.size(16.dp))
            }
        }
        Text(
            "If we both meet and vibe, I'm open to this treat.",
            fontSize = 12.sp, color = TextHint,
            textAlign = androidx.compose.ui.text.style.TextAlign.Center,
            modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp)
        )
        Spacer(modifier = Modifier.height(16.dp))
    }
}

@Composable
private fun IncomingLikeToast(
    banner: IncomingLikeBanner,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier
) {
    val pink = Color(0xFFFF6B9D)
    val gold = Color(0xFFFFB800)
    Row(
        modifier = modifier
            .fillMaxWidth()
            .background(CardBackground, RoundedCornerShape(14.dp))
            .border(1.dp, SurfaceVariant, RoundedCornerShape(14.dp))
            .clickable { onDismiss() }
            .padding(horizontal = 12.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Box(
            modifier = Modifier
                .size(28.dp)
                .background(SurfaceVariant, CircleShape),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                if (banner.isSuperLike) Icons.Default.Star else Icons.Default.Favorite,
                contentDescription = null,
                tint = if (banner.isSuperLike) gold else pink,
                modifier = Modifier.size(14.dp)
            )
        }
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                if (banner.isSuperLike) "New super like" else "New like",
                fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = TextPrimary
            )
            Text(
                "${banner.name} liked your profile",
                fontSize = 12.sp, color = TextSecondary, maxLines = 1
            )
        }
    }
}

private fun cardInterestGradient(interest: String): Pair<Color, Color> {
    val palettes = listOf(
        Color(0xFFFF6B9D) to Color(0xFFC44EFF),
        Color(0xFFC44EFF) to Color(0xFF7C3AED),
        Color(0xFF00E5A0) to Color(0xFF00B4D8),
        Color(0xFFFF9A3C) to Color(0xFFFF6B9D),
        Color(0xFF00B4D8) to Color(0xFF7C3AED),
        Color(0xFFFFB800) to Color(0xFFFF6B9D),
        Color(0xFF7C3AED) to Color(0xFF00E5A0),
        Color(0xFFFF4081) to Color(0xFFFFB800)
    )
    return palettes[((interest.hashCode() % palettes.size) + palettes.size) % palettes.size]
}
