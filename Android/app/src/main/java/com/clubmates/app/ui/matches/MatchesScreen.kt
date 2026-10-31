package com.clubmates.app.ui.matches

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.PersonRemove
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import coil.compose.AsyncImage
import com.clubmates.app.domain.model.Match
import com.clubmates.app.ui.components.AvatarImage
import com.clubmates.app.ui.discover.ProfileCard
import com.clubmates.app.ui.discover.VenueScreenBackground
import com.clubmates.app.ui.theme.Background
import com.clubmates.app.ui.theme.CardBackground
import com.clubmates.app.ui.theme.Like
import com.clubmates.app.ui.theme.Nope
import com.clubmates.app.ui.theme.Primary
import com.clubmates.app.ui.theme.Surface
import com.clubmates.app.ui.theme.SurfaceVariant
import com.clubmates.app.ui.theme.SuperLike
import com.clubmates.app.ui.theme.TextHint
import com.clubmates.app.ui.theme.TextPrimary
import com.clubmates.app.ui.theme.TextSecondary
import java.time.Duration
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlin.math.abs
import androidx.compose.animation.togetherWith

internal val primaryGradient = Brush.linearGradient(listOf(Color(0xFFFF6B9D), Color(0xFFC44EFF)))
private val nopeGradient = Brush.linearGradient(listOf(Color(0xFF6B7280), Color(0xFF4B5563)))

enum class MatchesDisplayMode {
    MATCHES,
    CHATS
}

private enum class MatchesTab {
    FOR_YOU,
    CONNECTED
}

private enum class ConnectedLayout {
    LIST,
    GRID
}

@Composable
fun MatchesScreen(
    viewModel: MatchesViewModel,
    displayMode: MatchesDisplayMode = MatchesDisplayMode.MATCHES
) {
    val matchesState by viewModel.matchesState.collectAsState()
    val chatState by viewModel.chatState.collectAsState()
    val onlineUserIds by viewModel.onlineUserIds.collectAsState()

    var isSearchVisible by remember { mutableStateOf(false) }
    var searchText by remember { mutableStateOf("") }
    var pendingUnmatch by remember { mutableStateOf<Match?>(null) }
    var selectedMatchesTab by remember { mutableStateOf(MatchesTab.FOR_YOU) }
    var connectedLayout by remember { mutableStateOf(ConnectedLayout.LIST) }

    val trimmedSearch = searchText.trim()
    val filteredMatches = remember(matchesState.matches, trimmedSearch) {
        if (trimmedSearch.isEmpty()) {
            matchesState.matches
        } else {
            matchesState.matches.filter { match ->
                match.profile.name.contains(trimmedSearch, ignoreCase = true) ||
                    match.lastMessage.contains(trimmedSearch, ignoreCase = true)
            }
        }
    }
    val pendingLikes = remember(filteredMatches) {
        filteredMatches.filter { viewModel.isPendingIncomingLike(it) }
    }
    val confirmedMatches = remember(filteredMatches) {
        filteredMatches.filter { !viewModel.isPendingIncomingLike(it) }
    }
    val conversationMatches = remember(filteredMatches) {
        filteredMatches.filter { !it.isNew && !viewModel.isPendingIncomingLike(it) }
    }
    val showsSearchField = isSearchVisible || trimmedSearch.isNotEmpty()

    BackHandler(enabled = chatState.match != null) {
        viewModel.closeChat()
    }

    BackHandler(enabled = chatState.match == null && showsSearchField) {
        searchText = ""
        isSearchVisible = false
    }

    pendingUnmatch?.let { match ->
        AlertDialog(
            onDismissRequest = { pendingUnmatch = null },
            title = { Text("Unmatch ${match.profile.name}?") },
            text = { Text("This removes the conversation and chat history from Matches.") },
            confirmButton = {
                TextButton(
                    onClick = {
                        viewModel.unmatch(match.id)
                        pendingUnmatch = null
                    }
                ) {
                    Text("Unmatch", color = Nope)
                }
            },
            dismissButton = {
                TextButton(onClick = { pendingUnmatch = null }) {
                    Text("Cancel")
                }
            },
            containerColor = CardBackground
        )
    }

    matchesState.selectedIncomingLikeProfile?.let { profile ->
        val pendingMatch = matchesState.matches.firstOrNull { it.profile.id == profile.id }
        val treatInvite = pendingMatch?.let { viewModel.pendingTreatInvite(it) }
        val onPassAction: (() -> Unit)? = if (pendingMatch != null) {
            {
                if (treatInvite != null) viewModel.reviewTreatInvite(pendingMatch, accept = false)
                else viewModel.reviewIncomingLike(pendingMatch, accept = false)
            }
        } else {
            null
        }
        val onLikeAction: (() -> Unit)? = if (pendingMatch != null) {
            {
                if (treatInvite != null) viewModel.reviewTreatInvite(pendingMatch, accept = true)
                else viewModel.reviewIncomingLike(pendingMatch, accept = true)
            }
        } else {
            null
        }
        IncomingLikeProfileDialog(
            profile = profile,
            treatInvite = treatInvite,
            onDismiss = { viewModel.dismissIncomingLikeProfile() },
            onPass = onPassAction,
            onLike = onLikeAction
        )
    }

    Box(modifier = Modifier.fillMaxSize()) {
        VenueScreenBackground(modifier = Modifier.fillMaxSize())

        AnimatedContent(
            targetState = chatState.match != null,
            transitionSpec = {
                if (targetState) {
                    slideInHorizontally { it } + fadeIn() togetherWith slideOutHorizontally { -it / 6 } + fadeOut()
                } else {
                    slideInHorizontally { -it / 6 } + fadeIn() togetherWith slideOutHorizontally { it } + fadeOut()
                }
            },
            label = "matchesChatTransition"
        ) { isChatOpen ->
            if (isChatOpen) {
                ChatScreen(
                    viewModel = viewModel,
                    onBack = { viewModel.closeChat() }
                )
            } else {
                Column(modifier = Modifier.fillMaxSize()) {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 20.dp, vertical = 14.dp),
                        verticalArrangement = Arrangement.spacedBy(14.dp)
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = if (displayMode == MatchesDisplayMode.MATCHES) Alignment.Top else Alignment.CenterVertically
                        ) {
                            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                Text(
                                    if (displayMode == MatchesDisplayMode.CHATS) "Chat" else "Matches",
                                    fontSize = 30.sp,
                                    fontWeight = FontWeight.Black,
                                    color = TextPrimary
                                )
                                if (displayMode == MatchesDisplayMode.MATCHES) {
                                    Text(
                                        "See incoming invites and your confirmed connections.",
                                        fontSize = 14.sp,
                                        fontWeight = FontWeight.Medium,
                                        color = Color.White.copy(alpha = 0.5f)
                                    )
                                }
                            }

                            IconButton(
                                onClick = {
                                    if (showsSearchField) {
                                        searchText = ""
                                        isSearchVisible = false
                                    } else {
                                        isSearchVisible = true
                                    }
                                },
                                modifier = Modifier
                                    .size(42.dp)
                                    .background(Surface, RoundedCornerShape(14.dp))
                                    .border(1.dp, Color.White.copy(alpha = 0.08f), RoundedCornerShape(14.dp))
                            ) {
                                Icon(
                                    imageVector = if (showsSearchField) Icons.Default.Close else Icons.Default.Search,
                                    contentDescription = if (showsSearchField) "Close search" else "Search",
                                    tint = TextPrimary
                                )
                            }
                        }

                        AnimatedVisibility(visible = showsSearchField, enter = fadeIn(), exit = fadeOut()) {
                            MatchesSearchField(
                                value = searchText,
                                onValueChange = { searchText = it },
                                placeholder = if (displayMode == MatchesDisplayMode.MATCHES) "Search matches" else "Search by name or message",
                                onClear = { searchText = "" }
                            )
                        }

                        if (displayMode == MatchesDisplayMode.MATCHES) {
                            MatchesSegmentedControl(
                                selectedTab = selectedMatchesTab,
                                pendingCount = pendingLikes.size,
                                onTabSelected = { selectedMatchesTab = it }
                            )
                        }
                    }

                    when {
                        matchesState.isLoading -> {
                            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                                CircularProgressIndicator(color = Primary)
                            }
                        }

                        displayMode == MatchesDisplayMode.MATCHES -> {
                            LazyColumn(
                                modifier = Modifier.fillMaxSize(),
                                contentPadding = PaddingValues(bottom = 24.dp)
                            ) {
                                if (selectedMatchesTab == MatchesTab.FOR_YOU) {
                                    if (pendingLikes.isEmpty()) {
                                        item {
                                            SectionPlaceholder(
                                                title = if (trimmedSearch.isEmpty()) "Nothing waiting right now" else "No requests found",
                                                subtitle = if (trimmedSearch.isEmpty()) {
                                                    "Incoming likes and venue invites will appear here for quick decisions."
                                                } else {
                                                    "Try another name or clear search to see all requests."
                                                },
                                                icon = if (trimmedSearch.isEmpty()) Icons.Default.Favorite else Icons.Default.Search
                                            )
                                        }
                                    } else {
                                        item {
                                            SectionHeader(
                                                title = "Pending Invites",
                                                subtitle = null
                                            )
                                        }
                                        items(pendingLikes, key = { it.id }) { match ->
                                            val treatInvite = viewModel.pendingTreatInvite(match)
                                            PendingLikeRow(
                                                match = match,
                                                treatInvite = treatInvite,
                                                onTap = { viewModel.handleNewMatchTap(match) },
                                                onPass = {
                                                    if (treatInvite != null) viewModel.reviewTreatInvite(match, accept = false)
                                                    else viewModel.reviewIncomingLike(match, accept = false)
                                                },
                                                onLike = {
                                                    if (treatInvite != null) viewModel.reviewTreatInvite(match, accept = true)
                                                    else viewModel.reviewIncomingLike(match, accept = true)
                                                }
                                            )
                                        }
                                    }
                                } else {
                                    item {
                                        ConnectedHeader(
                                            count = confirmedMatches.size,
                                            layout = connectedLayout,
                                            onLayoutSelected = { connectedLayout = it }
                                        )
                                    }

                                    if (confirmedMatches.isEmpty()) {
                                        item {
                                            SectionPlaceholder(
                                                title = if (trimmedSearch.isEmpty()) "No connected matches yet" else "No connections found",
                                                subtitle = if (trimmedSearch.isEmpty()) {
                                                    "Accept an invite or match with someone to start a connection."
                                                } else {
                                                    "No confirmed matches match that search."
                                                },
                                                icon = if (trimmedSearch.isEmpty()) Icons.Default.Person else Icons.Default.Search
                                            )
                                        }
                                    } else if (connectedLayout == ConnectedLayout.GRID) {
                                        item {
                                            MatchGrid(
                                                matches = confirmedMatches,
                                                onClick = { viewModel.handleNewMatchTap(it) },
                                                onLongPress = { pendingUnmatch = it }
                                            )
                                        }
                                    } else {
                                        items(confirmedMatches, key = { it.id }) { match ->
                                            ConnectedMatchRow(
                                                match = match,
                                                isOnline = viewModel.isUserOnline(match.profile.id),
                                                onClick = { viewModel.handleNewMatchTap(match) },
                                                onStartChat = { viewModel.openChat(match) },
                                                onLongPress = { pendingUnmatch = match }
                                            )
                                        }
                                    }
                                }
                            }
                        }

                        else -> {
                            LazyColumn(
                                modifier = Modifier.fillMaxSize(),
                                contentPadding = PaddingValues(bottom = 24.dp)
                            ) {
                                item {
                                    SectionHeader(title = "Conversations", subtitle = null)
                                }

                                if (conversationMatches.isEmpty()) {
                                    item {
                                        SectionPlaceholder(
                                            title = if (trimmedSearch.isEmpty()) "No conversations yet" else "No conversations found",
                                            subtitle = if (trimmedSearch.isEmpty()) {
                                                "Start a chat from your matches and conversations will live here."
                                            } else {
                                                "No threads match that search right now."
                                            },
                                            icon = if (trimmedSearch.isEmpty()) Icons.Outlined.ChatBubbleOutline else Icons.Default.Search
                                        )
                                    }
                                } else {
                                    items(conversationMatches, key = { it.id }) { match ->
                                        SwipeToUnmatchRow(onUnmatch = { pendingUnmatch = match }) {
                                            MessageMatchRow(
                                                match = match,
                                                onClick = { viewModel.openChat(match) },
                                                onLongPress = { pendingUnmatch = match }
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
    }
}

@Composable
private fun MatchesSearchField(
    value: String,
    onValueChange: (String) -> Unit,
    placeholder: String,
    onClear: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(Surface, RoundedCornerShape(20.dp))
            .border(1.dp, Color.White.copy(alpha = 0.08f), RoundedCornerShape(20.dp))
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Icon(Icons.Default.Search, contentDescription = null, tint = TextSecondary, modifier = Modifier.size(15.dp))
        BasicTextField(
            value = value,
            onValueChange = onValueChange,
            singleLine = true,
            textStyle = TextStyle(color = TextPrimary, fontSize = 15.sp),
            cursorBrush = SolidColor(Primary),
            modifier = Modifier.weight(1f),
            decorationBox = { innerTextField ->
                Box(contentAlignment = Alignment.CenterStart) {
                    if (value.isEmpty()) {
                        Text(placeholder, color = TextHint, fontSize = 15.sp)
                    }
                    innerTextField()
                }
            }
        )
        if (value.isNotEmpty()) {
            Icon(
                Icons.Default.Close,
                contentDescription = "Clear search",
                tint = TextHint,
                modifier = Modifier.clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                    onClick = onClear
                )
            )
        }
    }
}

@Composable
private fun SectionHeader(title: String, subtitle: String?) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 20.dp, vertical = 6.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            title.uppercase(),
            fontSize = 13.sp,
            fontWeight = FontWeight.SemiBold,
            color = TextSecondary,
            letterSpacing = 0.8.sp
        )
        subtitle?.let {
            Text(
                it,
                fontSize = 12.sp,
                color = TextHint,
                fontWeight = FontWeight.Medium
            )
        }
    }
}

@Composable
private fun SectionPlaceholder(
    title: String,
    subtitle: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 20.dp)
            .background(CardBackground, RoundedCornerShape(24.dp))
            .border(1.dp, Surface, RoundedCornerShape(24.dp))
            .padding(16.dp),
        horizontalArrangement = Arrangement.spacedBy(14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier
                .size(54.dp)
                .background(SurfaceVariant, RoundedCornerShape(18.dp)),
            contentAlignment = Alignment.Center
        ) {
            Icon(icon, contentDescription = null, tint = Primary, modifier = Modifier.size(20.dp))
        }

        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Text(title, color = TextPrimary, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
            Text(subtitle, color = TextSecondary, fontSize = 13.sp)
        }
    }
}

@Composable
private fun MatchesSegmentedControl(
    selectedTab: MatchesTab,
    pendingCount: Int,
    onTabSelected: (MatchesTab) -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(Surface, RoundedCornerShape(20.dp))
            .border(1.dp, Color.White.copy(alpha = 0.08f), RoundedCornerShape(20.dp))
            .padding(5.dp)
    ) {
        MatchesTabButton(
            title = "For You",
            selected = selectedTab == MatchesTab.FOR_YOU,
            count = pendingCount.takeIf { it > 0 },
            onClick = { onTabSelected(MatchesTab.FOR_YOU) },
            modifier = Modifier.weight(1f)
        )
        MatchesTabButton(
            title = "Connected",
            selected = selectedTab == MatchesTab.CONNECTED,
            count = null,
            onClick = { onTabSelected(MatchesTab.CONNECTED) },
            modifier = Modifier.weight(1f)
        )
    }
}

@Composable
private fun MatchesTabButton(
    title: String,
    selected: Boolean,
    count: Int?,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Box(
        modifier = modifier
            .clip(RoundedCornerShape(16.dp))
            .background(if (selected) primaryGradient else Brush.linearGradient(listOf(Color.Transparent, Color.Transparent)))
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 12.dp),
        contentAlignment = Alignment.Center
    ) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                title,
                fontSize = 15.sp,
                fontWeight = FontWeight.Bold,
                color = if (selected) Color.White else Color.White.copy(alpha = 0.52f)
            )
            count?.let {
                Box(
                    modifier = Modifier
                        .background(Color(0xFFFF453A), RoundedCornerShape(999.dp))
                        .padding(horizontal = 8.dp, vertical = 4.dp)
                ) {
                    Text(it.toString(), fontSize = 11.sp, fontWeight = FontWeight.Black, color = Color.White)
                }
            }
        }
    }
}

@Composable
private fun ConnectedHeader(
    count: Int,
    layout: ConnectedLayout,
    onLayoutSelected: (ConnectedLayout) -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 20.dp, vertical = 6.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            "$count Connected".uppercase(),
            fontSize = 13.sp,
            fontWeight = FontWeight.Bold,
            color = Color.White.copy(alpha = 0.5f),
            letterSpacing = 1.2.sp
        )
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            ConnectedLayoutButton(
                title = "Grid",
                selected = layout == ConnectedLayout.GRID,
                onClick = { onLayoutSelected(ConnectedLayout.GRID) }
            )
            ConnectedLayoutButton(
                title = "List",
                selected = layout == ConnectedLayout.LIST,
                onClick = { onLayoutSelected(ConnectedLayout.LIST) }
            )
        }
    }
}

@Composable
private fun ConnectedLayoutButton(
    title: String,
    selected: Boolean,
    onClick: () -> Unit
) {
    Box(
        modifier = Modifier
            .clip(RoundedCornerShape(12.dp))
            .background(if (selected) primaryGradient else Brush.linearGradient(listOf(Color.Transparent, Color.Transparent)))
            .border(
                width = 1.dp,
                color = if (selected) Color.Transparent else Color.White.copy(alpha = 0.1f),
                shape = RoundedCornerShape(12.dp)
            )
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 10.dp)
    ) {
        Text(
            title,
            fontSize = 13.sp,
            fontWeight = FontWeight.Bold,
            color = if (selected) Color.White else Color.White.copy(alpha = 0.55f)
        )
    }
}

@Composable
private fun MatchGrid(
    matches: List<Match>,
    onClick: (Match) -> Unit,
    onLongPress: (Match) -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        matches.chunked(2).forEach { rowMatches ->
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                rowMatches.forEach { match ->
                    MatchGridCell(
                        match = match,
                        modifier = Modifier.weight(1f),
                        onClick = { onClick(match) },
                        onLongPress = { onLongPress(match) }
                    )
                }
                if (rowMatches.size == 1) {
                    Spacer(modifier = Modifier.weight(1f))
                }
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun ConnectedMatchRow(
    match: Match,
    isOnline: Boolean,
    onClick: () -> Unit,
    onStartChat: () -> Unit,
    onLongPress: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 20.dp, vertical = 6.dp)
            .background(Surface, RoundedCornerShape(20.dp))
            .border(1.dp, Color.White.copy(alpha = 0.08f), RoundedCornerShape(20.dp))
            .combinedClickable(onClick = onClick, onLongClick = onLongPress)
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        AvatarImage(photoUrl = match.profile.photos.firstOrNull()?.cdnUrl, size = 64.dp)
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(7.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    "${match.profile.name}, ${match.profile.age}",
                    fontSize = 17.sp,
                    fontWeight = FontWeight.Black,
                    color = TextPrimary
                )
                Box(
                    modifier = Modifier
                        .size(10.dp)
                        .background(if (isOnline) Like else Color.White.copy(alpha = 0.24f), CircleShape)
                )
            }
            Text(
                "Connected${formatRelativeTime(match.lastMessageAt).takeIf { it.isNotEmpty() }?.let { " • $it" } ?: ""}",
                fontSize = 13.sp,
                color = Color.White.copy(alpha = 0.5f)
            )
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .height(42.dp)
                        .background(primaryGradient, RoundedCornerShape(12.dp))
                        .clickable(onClick = onStartChat),
                    contentAlignment = Alignment.Center
                ) {
                    Text("Start Chat", fontSize = 14.sp, fontWeight = FontWeight.Bold, color = Color.White)
                }
                Box(
                    modifier = Modifier
                        .size(width = 44.dp, height = 42.dp)
                        .background(Color.White.copy(alpha = 0.04f), RoundedCornerShape(12.dp))
                        .border(1.dp, Color.White.copy(alpha = 0.1f), RoundedCornerShape(12.dp))
                        .clickable(onClick = onLongPress),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        Icons.Default.PersonRemove,
                        contentDescription = "Remove",
                        tint = Color.White.copy(alpha = 0.62f),
                        modifier = Modifier.size(15.dp)
                    )
                }
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun MatchGridCell(
    match: Match,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
    onLongPress: () -> Unit
) {
    Box(
        modifier = modifier
            .aspectRatio(3f / 4f)
            .clip(RoundedCornerShape(20.dp))
            .background(CardBackground)
            .border(1.dp, Surface, RoundedCornerShape(20.dp))
            .combinedClickable(onClick = onClick, onLongClick = onLongPress)
    ) {
        val photoUrl = match.profile.photos.firstOrNull()?.cdnUrl
        if (photoUrl != null) {
            AsyncImage(
                model = photoUrl,
                contentDescription = match.profile.name,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize()
            )
        } else {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(
                        Brush.linearGradient(
                            listOf(
                                Color(0xFF1E1B4B),
                                Color(0xFF7C3AED)
                            )
                        )
                    ),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    Icons.Default.Person,
                    contentDescription = null,
                    tint = Color.White.copy(alpha = 0.14f),
                    modifier = Modifier.size(56.dp)
                )
            }
        }

        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(
                    Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.75f)))
                )
        )

        Column(
            modifier = Modifier
                .align(Alignment.BottomStart)
                .padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(3.dp)
        ) {
            Text(
                match.profile.name,
                fontSize = 18.sp,
                fontWeight = FontWeight.Black,
                color = Color.White,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Text(
                match.profile.age.toString(),
                fontSize = 14.sp,
                fontWeight = FontWeight.Black,
                color = Color.White
            )
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun PendingLikeRow(
    match: Match,
    treatInvite: com.clubmates.app.data.network.ApiTreatInvite?,
    onTap: () -> Unit,
    onPass: () -> Unit,
    onLike: () -> Unit
) {
    val treat = treatInvite?.treat
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 20.dp, vertical = 6.dp)
            .background(CardBackground, RoundedCornerShape(20.dp))
            .border(1.dp, Surface, RoundedCornerShape(20.dp))
            .combinedClickable(onClick = onTap)
            .padding(14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(13.dp)
    ) {
        Box {
            AvatarImage(photoUrl = match.profile.photos.firstOrNull()?.cdnUrl, size = 58.dp)
            Box(
                modifier = Modifier
                    .size(20.dp)
                    .background(Color(0xFFFF6B9D), CircleShape)
                    .border(2.dp, CardBackground, CircleShape)
                    .align(Alignment.TopEnd),
                contentAlignment = Alignment.Center
            ) {
                Icon(Icons.Default.Favorite, contentDescription = null, tint = Color.White, modifier = Modifier.size(10.dp))
            }
        }

        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Text(match.profile.name, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = TextPrimary)
            Text(
                match.lastMessage.ifBlank {
                    if (treat != null) "${treat.emoji} wants to ${treat.notificationNoun}" else "Liked you"
                },
                fontSize = 13.sp,
                color = TextSecondary,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis
            )
        }

        DecisionCircle(icon = Icons.Default.Close, gradient = nopeGradient, onClick = onPass)
        DecisionCircle(icon = if (treat != null) Icons.Default.Favorite else Icons.Default.Favorite, gradient = primaryGradient, onClick = onLike)
    }
}

@Composable
private fun DecisionCircle(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    gradient: Brush,
    onClick: () -> Unit
) {
    Box(
        modifier = Modifier
            .size(38.dp)
            .clip(CircleShape)
            .background(gradient)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center
    ) {
        Icon(icon, contentDescription = null, tint = Color.White, modifier = Modifier.size(18.dp))
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun MessageMatchRow(
    match: Match,
    onClick: () -> Unit,
    onLongPress: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .combinedClickable(onClick = onClick, onLongClick = onLongPress)
            .padding(horizontal = 20.dp, vertical = 12.dp)
            .background(if (match.unreadCount > 0) CardBackground else Color.Transparent)
            .padding(horizontal = 0.dp, vertical = 0.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        Box {
            AvatarImage(photoUrl = match.profile.photos.firstOrNull()?.cdnUrl, size = 58.dp)
            if (match.unreadCount > 0) {
                Box(
                    modifier = Modifier
                        .size(20.dp)
                        .background(Primary, CircleShape)
                        .border(2.dp, Background, CircleShape)
                        .align(Alignment.BottomEnd),
                    contentAlignment = Alignment.Center
                ) {
                    Text(match.unreadCount.toString(), fontSize = 11.sp, color = Color.White, fontWeight = FontWeight.Bold)
                }
            }
        }

        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(match.profile.name, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = TextPrimary)
                formatRelativeTime(match.lastMessageAt).takeIf { it.isNotEmpty() }?.let { timestamp ->
                    Text(timestamp, fontSize = 12.sp, color = TextHint)
                }
            }

            Text(
                if (match.lastMessage.isBlank()) "Say hi! 👋" else match.lastMessage,
                fontSize = 14.sp,
                color = if (match.unreadCount > 0) TextPrimary else TextSecondary,
                fontWeight = if (match.unreadCount > 0) FontWeight.Medium else FontWeight.Normal,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }

        Text("›", fontSize = 18.sp, color = TextHint)
    }
}

@Composable
private fun IncomingLikeProfileDialog(
    profile: com.clubmates.app.domain.model.UserProfile,
    treatInvite: com.clubmates.app.data.network.ApiTreatInvite?,
    onDismiss: () -> Unit,
    onPass: (() -> Unit)?,
    onLike: (() -> Unit)?
) {
    Dialog(onDismissRequest = onDismiss) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Background)
        ) {
            ProfileCard(
                profile = profile,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 24.dp)
            )

            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(horizontal = 20.dp, vertical = 16.dp)
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.End
                ) {
                    IconButton(
                        onClick = onDismiss,
                        modifier = Modifier
                            .size(34.dp)
                            .background(Surface, CircleShape)
                    ) {
                        Icon(Icons.Default.Close, contentDescription = "Close", tint = TextPrimary)
                    }
                }

                Spacer(modifier = Modifier.weight(1f))

                treatInvite?.treat?.let { treat ->
                    Surface(
                        color = CardBackground,
                        shape = RoundedCornerShape(18.dp),
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(bottom = 12.dp)
                    ) {
                        Column(
                            modifier = Modifier.padding(16.dp),
                            verticalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            Text("${treat.emoji} Treat invite", fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = TextPrimary)
                            Text("${profile.name} wants to ${treat.notificationNoun}.", fontSize = 13.sp, color = TextSecondary)
                        }
                    }
                }

                if (onPass != null && onLike != null) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        Button(
                            onClick = {
                                onDismiss()
                                onPass()
                            },
                            modifier = Modifier.weight(1f),
                            shape = RoundedCornerShape(999.dp),
                            colors = ButtonDefaults.buttonColors(containerColor = Nope)
                        ) {
                            Text(if (treatInvite != null) "Decline" else "Pass", color = Color.White, fontWeight = FontWeight.SemiBold)
                        }
                        Button(
                            onClick = {
                                onDismiss()
                                onLike()
                            },
                            modifier = Modifier.weight(1f),
                            shape = RoundedCornerShape(999.dp),
                            colors = ButtonDefaults.buttonColors(containerColor = Primary)
                        ) {
                            Text(if (treatInvite != null) "Accept" else "Like Back", color = Color.White, fontWeight = FontWeight.SemiBold)
                        }
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun SwipeToUnmatchRow(
    onUnmatch: () -> Unit,
    content: @Composable () -> Unit
) {
    var settledOffset by remember { mutableFloatStateOf(0f) }
    var dragTranslation by remember { mutableFloatStateOf(0f) }
    val actionWidth = 104f

    val rowOffset = (settledOffset + dragTranslation).coerceIn(-actionWidth * 1.2f, actionWidth * 1.2f)
    val animatedOffset by animateFloatAsState(
        targetValue = rowOffset,
        animationSpec = spring(dampingRatio = 0.82f, stiffness = 400f),
        label = "swipeOffset"
    )
    val revealProgress = (abs(animatedOffset) / actionWidth).coerceIn(0f, 1f)
    val bgAlpha = (0.18f + 0.82f * revealProgress).coerceIn(0f, 1f)

    Box(modifier = Modifier.fillMaxWidth().clipToBounds()) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .fillMaxSize()
                .background(Color(0xFFFF3B30).copy(alpha = bgAlpha))
        ) {
            if (rowOffset > 8f) {
                UnmatchActionButton(
                    modifier = Modifier
                        .align(Alignment.CenterStart)
                        .fillMaxHeight()
                        .width(actionWidth.dp),
                    onClick = { settledOffset = 0f; dragTranslation = 0f; onUnmatch() }
                )
            }
            if (rowOffset < -8f) {
                UnmatchActionButton(
                    modifier = Modifier
                        .align(Alignment.CenterEnd)
                        .fillMaxHeight()
                        .width(actionWidth.dp),
                    onClick = { settledOffset = 0f; dragTranslation = 0f; onUnmatch() }
                )
            }
        }

        Box(
            modifier = Modifier
                .offset { androidx.compose.ui.unit.IntOffset(animatedOffset.toInt(), 0) }
                .combinedClickable(
                    onClick = {
                        if (settledOffset != 0f) {
                            settledOffset = 0f
                            dragTranslation = 0f
                        }
                    }
                )
                .pointerInput(Unit) {
                    detectHorizontalDragGestures(
                        onDragEnd = {
                            val proposed = settledOffset + dragTranslation
                            val predicted = settledOffset + dragTranslation * 1.35f
                            val shouldUnmatch = abs(proposed) > actionWidth * 1.15f || abs(predicted) > actionWidth * 1.55f
                            when {
                                shouldUnmatch -> {
                                    settledOffset = 0f
                                    dragTranslation = 0f
                                    onUnmatch()
                                }

                                proposed > actionWidth * 0.45f -> {
                                    settledOffset = actionWidth
                                    dragTranslation = 0f
                                }

                                proposed < -actionWidth * 0.45f -> {
                                    settledOffset = -actionWidth
                                    dragTranslation = 0f
                                }

                                else -> {
                                    settledOffset = 0f
                                    dragTranslation = 0f
                                }
                            }
                        },
                        onDragCancel = {
                            settledOffset = 0f
                            dragTranslation = 0f
                        },
                        onHorizontalDrag = { _, dragAmount ->
                            dragTranslation += dragAmount
                        }
                    )
                }
        ) {
            content()
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun UnmatchActionButton(modifier: Modifier, onClick: () -> Unit) {
    Box(modifier = modifier.combinedClickable(onClick = onClick), contentAlignment = Alignment.Center) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Icon(Icons.Default.PersonRemove, contentDescription = "Unmatch", tint = Color.White, modifier = Modifier.size(20.dp))
            Text("Unmatch", fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = Color.White)
        }
    }
}

private fun formatRelativeTime(rawTimestamp: String): String {
    val instant = rawTimestamp.toLongOrNull()?.let(Instant::ofEpochMilli)
        ?: runCatching { Instant.parse(rawTimestamp) }.getOrNull()
        ?: return ""

    val duration = Duration.between(instant, Instant.now())
    val minutes = duration.toMinutes().coerceAtLeast(0)

    return when {
        minutes < 1 -> "now"
        minutes < 60 -> "${minutes}m"
        duration.toHours() < 24 -> "${duration.toHours()}h"
        duration.toDays() < 7 -> "${duration.toDays()}d"
        else -> DateTimeFormatter.ofPattern("MMM d")
            .withZone(ZoneId.systemDefault())
            .format(instant)
    }
}
