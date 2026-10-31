package com.clubmates.app.ui.matches

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.spring
import androidx.compose.material.icons.filled.Warning
import androidx.compose.animation.core.StartOffset
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.Block
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.clubmates.app.domain.model.ChatMessage
import com.clubmates.app.ui.components.AvatarImage
import com.clubmates.app.ui.theme.Background
import com.clubmates.app.ui.theme.CardBackground
import com.clubmates.app.ui.theme.Like
import com.clubmates.app.ui.theme.Primary
import com.clubmates.app.ui.theme.Surface
import com.clubmates.app.ui.theme.SurfaceVariant
import com.clubmates.app.ui.theme.TextHint
import com.clubmates.app.ui.theme.TextPrimary
import com.clubmates.app.ui.theme.TextSecondary
import com.clubmates.app.ui.safety.SOSViewModel
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

@Composable
fun ChatScreen(
    viewModel: MatchesViewModel,
    onBack: () -> Unit
) {
    BackHandler { onBack() }

    val chatState by viewModel.chatState.collectAsState()
    val matchesState by viewModel.matchesState.collectAsState()
    val onlineUserIds by viewModel.onlineUserIds.collectAsState()
    val sosViewModel: SOSViewModel = hiltViewModel()
    val sosState by sosViewModel.uiState.collectAsState()
    val match = chatState.match ?: return
    val isMatchOnline = onlineUserIds.contains(match.profile.id)
    val listState = rememberLazyListState()
    var messageText by remember { mutableStateOf("") }
    var showMenu by remember { mutableStateOf(false) }
    var showUnmatchConfirmation by remember { mutableStateOf(false) }
    var showSOSConfirmation by remember { mutableStateOf(false) }
    var showBlockConfirmation by remember { mutableStateOf(false) }
    var showSpamReasons by remember { mutableStateOf(false) }

    val spamReasons = remember {
        listOf(
            "Promotional or selling",
            "Scam or money request",
            "Fake or suspicious profile",
            "Repeated unwanted messages",
            "Harassment or sexual spam"
        )
    }

    LaunchedEffect(chatState.messages.size) {
        if (chatState.messages.isNotEmpty()) {
            listState.animateScrollToItem(chatState.messages.size)
        }
    }

    LaunchedEffect(chatState.isTyping) {
        if (chatState.isTyping) {
            listState.animateScrollToItem(chatState.messages.size + 1)
        }
    }

    LaunchedEffect(messageText) {
        if (messageText.isNotEmpty()) viewModel.sendTypingStart() else viewModel.sendTypingStop()
    }

    if (showUnmatchConfirmation) {
        AlertDialog(
            onDismissRequest = { showUnmatchConfirmation = false },
            title = { Text("Unmatch ${match.profile.name}?") },
            text = { Text("This removes the conversation and chat history from Matches.") },
            confirmButton = {
                TextButton(
                    onClick = {
                        showUnmatchConfirmation = false
                        viewModel.unmatch(match.id)
                        onBack()
                    }
                ) {
                    Text("Unmatch", color = Color(0xFFFF3B30))
                }
            },
            dismissButton = {
                TextButton(onClick = { showUnmatchConfirmation = false }) {
                    Text("Cancel")
                }
            },
            containerColor = CardBackground
        )
    }

    // Custom SOS overlay — matches iOS sosOverlay glassmorphic style
    AnimatedVisibility(
        visible = showSOSConfirmation,
        enter = fadeIn(spring(dampingRatio = 0.8f)) + scaleIn(spring(dampingRatio = 0.72f), initialScale = 0.9f),
        exit = fadeOut() + scaleOut(targetScale = 0.9f)
    ) {
        com.clubmates.app.ui.discover.GlassmorphicConfirmOverlay(
            iconRes = Icons.Default.Warning,
            iconTint = Color(0xFFFF4757),
            iconGradient = Brush.linearGradient(listOf(Color(0xFFFF4757), Color(0xFFB91C1C))),
            borderGradient = Brush.linearGradient(listOf(Color.White.copy(0.12f), Color(0xFFFF4757).copy(0.20f), Color.White.copy(0.06f))),
            title = "Emergency SOS",
            body = "This records this chat as safety context and opens the emergency phone number.",
            confirmLabel = "Record SOS & Call 112",
            cancelLabel = "Cancel",
            onConfirm = {
                showSOSConfirmation = false
                sosViewModel.triggerSOS(source = "chat", matchId = match.id)
            },
            onDismiss = { showSOSConfirmation = false }
        )
    }

    if (showBlockConfirmation) {
        AlertDialog(
            onDismissRequest = { showBlockConfirmation = false },
            title = { Text("Block ${match.profile.name}?") },
            text = { Text("They will disappear from your matches and will not be shown to you again.") },
            confirmButton = {
                TextButton(
                    onClick = {
                        showBlockConfirmation = false
                        viewModel.block(match, onDone = onBack)
                    }
                ) {
                    Text("Block", color = Color(0xFFFF3B30))
                }
            },
            dismissButton = {
                TextButton(onClick = { showBlockConfirmation = false }) {
                    Text("Cancel")
                }
            },
            containerColor = CardBackground
        )
    }

    if (showSpamReasons) {
        AlertDialog(
            onDismissRequest = { showSpamReasons = false },
            title = { Text("Why is this spam?") },
            text = {
                Column {
                    spamReasons.forEach { reason ->
                        TextButton(
                            onClick = {
                                showSpamReasons = false
                                viewModel.reportSpam(match, reason, onDone = onBack)
                            },
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Text(reason, color = Color(0xFFFF3B30), modifier = Modifier.fillMaxWidth())
                        }
                    }
                }
            },
            confirmButton = {},
            dismissButton = {
                TextButton(onClick = { showSpamReasons = false }) {
                    Text("Cancel")
                }
            },
            containerColor = CardBackground
        )
    }

    chatState.messageError?.let { messageError ->
        AlertDialog(
            onDismissRequest = { viewModel.clearMessageError() },
            title = { Text("Message not sent") },
            text = { Text(messageError) },
            confirmButton = {
                TextButton(onClick = { viewModel.clearMessageError() }) {
                    Text("OK")
                }
            },
            containerColor = CardBackground
        )
    }

    sosState.error?.let { errorMsg ->
        AlertDialog(
            onDismissRequest = { sosViewModel.clearError() },
            title = { Text("SOS could not be recorded") },
            text = { Text(errorMsg) },
            confirmButton = {
                TextButton(onClick = { sosViewModel.clearError() }) {
                    Text("OK")
                }
            },
            containerColor = CardBackground
        )
    }

    matchesState.safetyError?.let { errorMsg ->
        AlertDialog(
            onDismissRequest = { viewModel.clearSafetyError() },
            title = { Text("Safety action failed") },
            text = { Text(errorMsg) },
            confirmButton = {
                TextButton(onClick = { viewModel.clearSafetyError() }) {
                    Text("OK")
                }
            },
            containerColor = CardBackground
        )
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Background)
            .imePadding()
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .background(CardBackground)
                .padding(horizontal = 16.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            IconButton(onClick = onBack, modifier = Modifier.size(36.dp)) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back", tint = TextPrimary)
            }

            Box(
                modifier = Modifier
                    .size(42.dp)
                    .background(primaryGradient, CircleShape)
                    .padding(2.dp),
                contentAlignment = Alignment.Center
            ) {
                AvatarImage(photoUrl = match.profile.photos.firstOrNull()?.cdnUrl, size = 38.dp)
            }

            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(2.dp)
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    Text(match.profile.name, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = TextPrimary)
                    if (match.profile.isVerified) {
                        Icon(Icons.Default.CheckCircle, contentDescription = "Verified", tint = Primary, modifier = Modifier.size(13.dp))
                    }
                }
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    Box(
                        modifier = Modifier
                            .size(7.dp)
                            .background(if (isMatchOnline) Like else TextSecondary.copy(alpha = 0.65f), CircleShape)
                    )
                    Text(
                        if (isMatchOnline) "Active now" else "Offline",
                        fontSize = 12.sp,
                        color = if (isMatchOnline) Like else TextSecondary
                    )
                }
            }

            Box {
                IconButton(
                    onClick = { showMenu = true },
                    modifier = Modifier
                        .size(36.dp)
                        .background(Surface, CircleShape)
                ) {
                    Icon(Icons.Default.MoreHoriz, contentDescription = "More", tint = TextPrimary)
                }
                DropdownMenu(
                    expanded = showMenu,
                    onDismissRequest = { showMenu = false },
                    containerColor = CardBackground
                ) {
                    DropdownMenuItem(
                        text = { Text("Emergency SOS", color = Color(0xFFFF3B30)) },
                        leadingIcon = {
                            Icon(Icons.Default.ErrorOutline, contentDescription = null, tint = Color(0xFFFF3B30))
                        },
                        onClick = {
                            showMenu = false
                            showSOSConfirmation = true
                        }
                    )
                    DropdownMenuItem(
                        text = { Text("Report spam", color = Color(0xFFFF3B30)) },
                        leadingIcon = {
                            Icon(Icons.Default.Flag, contentDescription = null, tint = Color(0xFFFF3B30))
                        },
                        onClick = {
                            showMenu = false
                            showSpamReasons = true
                        }
                    )
                    DropdownMenuItem(
                        text = { Text("Block", color = Color(0xFFFF3B30)) },
                        leadingIcon = {
                            Icon(Icons.Default.Block, contentDescription = null, tint = Color(0xFFFF3B30))
                        },
                        onClick = {
                            showMenu = false
                            showBlockConfirmation = true
                        }
                    )
                    DropdownMenuItem(
                        text = { Text("Unmatch", color = Color(0xFFFF3B30)) },
                        leadingIcon = {
                            Icon(Icons.Default.Block, contentDescription = null, tint = Color(0xFFFF3B30))
                        },
                        onClick = {
                            showMenu = false
                            showUnmatchConfirmation = true
                        }
                    )
                }
            }
        }

        HorizontalDivider(color = Surface)

        if (chatState.isLoading) {
            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = Primary)
            }
        } else {
            LazyColumn(
                state = listState,
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp),
                contentPadding = PaddingValues(vertical = 16.dp),
                verticalArrangement = Arrangement.spacedBy(2.dp)
            ) {
                item {
                    MatchBanner(
                        matchName = match.profile.name,
                        photoUrl = match.profile.photos.firstOrNull()?.cdnUrl
                    )
                }

                itemsIndexed(chatState.messages, key = { _, msg -> msg.id }) { index, message ->
                    val previous = chatState.messages.getOrNull(index - 1)
                    val next = chatState.messages.getOrNull(index + 1)
                    MessageBubble(
                        message = message,
                        isFirstInGroup = previous?.isFromMe != message.isFromMe,
                        isLastInGroup = next?.isFromMe != message.isFromMe
                    )
                }

                if (chatState.isTyping) {
                    item { AnimatedTypingIndicator() }
                }
            }
        }

        HorizontalDivider(color = Surface)

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .background(CardBackground)
                .padding(horizontal = 16.dp, vertical = 10.dp),
            verticalAlignment = Alignment.Bottom,
            horizontalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Row(
                modifier = Modifier
                    .weight(1f)
                    .background(Surface, CircleShape)
                    .padding(horizontal = 16.dp, vertical = 11.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                BasicTextField(
                    value = messageText,
                    onValueChange = { messageText = it },
                    modifier = Modifier.weight(1f),
                    maxLines = 5,
                    singleLine = false,
                    textStyle = TextStyle(
                        color = TextPrimary,
                        fontSize = 16.sp
                    ),
                    cursorBrush = SolidColor(Primary),
                    decorationBox = { innerTextField ->
                        Box(contentAlignment = Alignment.CenterStart) {
                            if (messageText.isBlank()) {
                                Text("Message...", color = TextHint, fontSize = 16.sp)
                            }
                            innerTextField()
                        }
                    }
                )
            }

            val isEmpty = messageText.isBlank()
            Box(
                modifier = Modifier
                    .size(46.dp)
                    .then(
                        if (isEmpty) Modifier.background(Surface, CircleShape)
                        else Modifier.background(primaryGradient, CircleShape)
                    ),
                contentAlignment = Alignment.Center
            ) {
                IconButton(
                    onClick = {
                        if (!isEmpty) {
                            viewModel.sendMessage(messageText)
                            messageText = ""
                        }
                    },
                    modifier = Modifier.size(46.dp)
                ) {
                    Icon(
                        if (isEmpty) Icons.Default.Mic else Icons.AutoMirrored.Filled.Send,
                        contentDescription = if (isEmpty) "Voice" else "Send",
                        tint = Color.White
                    )
                }
            }
        }
    }
}

@Composable
private fun MatchBanner(matchName: String, photoUrl: String?) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 28.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Box(
            modifier = Modifier
                .size(88.dp)
                .background(Primary.copy(alpha = 0.12f), CircleShape),
            contentAlignment = Alignment.Center
        ) {
            Box(
                modifier = Modifier
                    .size(72.dp)
                    .background(primaryGradient, CircleShape)
                    .padding(2.5.dp),
                contentAlignment = Alignment.Center
            ) {
                AvatarImage(photoUrl = photoUrl, size = 67.dp)
            }
        }

        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Text("You matched with $matchName!", fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = TextPrimary)
            Text("Say something nice ✨", fontSize = 13.sp, color = TextSecondary)
        }
    }
}

@Composable
private fun MessageBubble(
    message: ChatMessage,
    isFirstInGroup: Boolean,
    isLastInGroup: Boolean
) {
    val alignment = if (message.isFromMe) Alignment.End else Alignment.Start
    val r = 18.dp
    val t = 5.dp
    val shape = if (message.isFromMe) {
        RoundedCornerShape(
            topStart = r,
            topEnd = if (isFirstInGroup) r else t,
            bottomStart = r,
            bottomEnd = if (isLastInGroup) r else t
        )
    } else {
        RoundedCornerShape(
            topStart = if (isFirstInGroup) r else t,
            topEnd = r,
            bottomStart = if (isLastInGroup) r else t,
            bottomEnd = r
        )
    }

    Column(
        modifier = Modifier.fillMaxWidth(),
        horizontalAlignment = alignment
    ) {
        Box(
            modifier = Modifier
                .widthIn(max = 280.dp)
                .background(if (message.isFromMe) primaryGradient else Brush.linearGradient(listOf(Surface, Surface)), shape)
                .padding(horizontal = 14.dp, vertical = 10.dp)
        ) {
            Text(message.body, fontSize = 16.sp, color = if (message.isFromMe) Color.White else TextPrimary)
        }

        if (isLastInGroup) {
            Text(
                formatMessageTime(message.createdAt),
                fontSize = 11.sp,
                color = TextHint,
                modifier = Modifier.padding(horizontal = 4.dp, vertical = 2.dp)
            )
        }
    }
}

@Composable
private fun AnimatedTypingIndicator() {
    val transition = rememberInfiniteTransition(label = "typing")
    Row(
        modifier = Modifier
            .background(Surface, RoundedCornerShape(18.dp))
            .padding(horizontal = 14.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(5.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        repeat(3) { index ->
            val scale by transition.animateFloat(
                initialValue = 1f,
                targetValue = 1.4f,
                animationSpec = infiniteRepeatable(
                    animation = tween(450),
                    repeatMode = RepeatMode.Reverse,
                    initialStartOffset = StartOffset(index * 180)
                ),
                label = "dot$index"
            )
            Box(
                modifier = Modifier
                    .size(7.dp)
                    .graphicsLayer {
                        scaleX = scale
                        scaleY = scale
                    }
                    .background(TextSecondary, CircleShape)
            )
        }
    }
}

private fun formatMessageTime(rawTimestamp: String): String {
    val instant = rawTimestamp.toLongOrNull()?.let(Instant::ofEpochMilli)
        ?: runCatching { Instant.parse(rawTimestamp) }.getOrNull()
        ?: return ""

    return DateTimeFormatter.ofPattern("h:mm a")
        .withZone(ZoneId.systemDefault())
        .format(instant)
        .lowercase()
}
