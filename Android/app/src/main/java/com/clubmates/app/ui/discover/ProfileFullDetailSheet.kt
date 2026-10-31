package com.clubmates.app.ui.discover

import androidx.compose.animation.*
import androidx.compose.animation.core.*
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
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
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import coil.request.ImageRequest
import androidx.compose.ui.platform.LocalContext
import com.clubmates.app.domain.model.UserProfile
import com.clubmates.app.ui.main.LocalTabBarController
import com.clubmates.app.ui.theme.*

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ProfileFullDetailSheet(
    profile: UserProfile,
    onDismiss: () -> Unit,
    showActions: Boolean = false,
    onPass: (() -> Unit)? = null,
    onLike: (() -> Unit)? = null,
    onSuperLike: (() -> Unit)? = null
) {
    val pink = Color(0xFFFF6B9D)
    val purple = Color(0xFFC44EFF)
    val green = Color(0xFF00C853)
    val tabBarController = LocalTabBarController.current

    var appeared by remember { mutableStateOf(false) }
    var photoPage by remember { mutableIntStateOf(0) }
    var scrollOffset by remember { mutableFloatStateOf(0f) }

    LaunchedEffect(Unit) {
        appeared = true
        tabBarController?.isHidden = true
    }
    DisposableEffect(Unit) {
        onDispose { tabBarController?.isHidden = false }
    }

    // Parallax: hero shifts at 35% of scroll speed (mirrors iOS parallaxOffset * 0.35)
    val parallaxOffsetDp = if (scrollOffset < 0) scrollOffset * 0.35f else 0f
    val scrollState = rememberScrollState()
    LaunchedEffect(scrollState.value) { scrollOffset = -scrollState.value.toFloat() }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Background)
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(scrollState),
            verticalArrangement = Arrangement.spacedBy(20.dp)
        ) {
            // ── Hero card ─────────────────────────────────────────────────────
            AnimatedVisibility(
                visible = appeared,
                enter = fadeIn() + slideInVertically { 20 }
            ) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(480.dp)
                        .clip(RoundedCornerShape(bottomStart = 0.dp, bottomEnd = 0.dp))
                ) {
                    val photoUrl = profile.photos.firstOrNull()?.cdnUrl
                    if (photoUrl != null) {
                        val ctx = LocalContext.current
                        AsyncImage(
                            model = remember(photoUrl) { ImageRequest.Builder(ctx).data(photoUrl).crossfade(false).build() },
                            contentDescription = profile.name,
                            contentScale = ContentScale.Crop,
                            modifier = Modifier.fillMaxSize()
                                .graphicsLayer {
                                    // Parallax: scale up slightly on overscroll, shift at 35% speed
                                    val over = maxOf(0f, -scrollOffset)
                                    scaleX = 1f + over / 1200f
                                    scaleY = 1f + over / 1200f
                                    translationY = parallaxOffsetDp
                                }
                        )
                    } else {
                        Box(modifier = Modifier.fillMaxSize().background(Brush.linearGradient(listOf(Color(0xFF111827), Color(0xFF4A1259)))))
                    }
                    // Top gradient
                    Box(modifier = Modifier.fillMaxWidth().height(100.dp).background(Brush.verticalGradient(listOf(Color.Black.copy(0.45f), Color.Transparent))))
                    // Bottom gradient
                    Box(modifier = Modifier.fillMaxWidth().height(160.dp).align(Alignment.BottomCenter).background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(0.88f)))))

                    // Verified badge
                    if (profile.isVerified) {
                        Row(
                            modifier = Modifier.align(Alignment.TopStart).padding(16.dp)
                                .background(green.copy(0.18f), RoundedCornerShape(50))
                                .border(1.dp, green.copy(0.45f), RoundedCornerShape(50))
                                .padding(horizontal = 10.dp, vertical = 6.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(4.dp)
                        ) {
                            Icon(Icons.Default.CheckCircle, contentDescription = null, tint = green, modifier = Modifier.size(11.dp))
                            Text("Verified", fontSize = 11.sp, fontWeight = FontWeight.Bold, color = green)
                        }
                    }

                    // Name + age + info
                    Column(modifier = Modifier.align(Alignment.BottomStart).padding(20.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text(profile.name, fontSize = 36.sp, fontWeight = FontWeight.Black, color = Color.White)
                            Text("${profile.age}", fontSize = 28.sp, fontWeight = FontWeight.Light, color = Color.White.copy(0.78f))
                        }
                        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            if (profile.profession.isNotBlank()) {
                                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                                    Icon(Icons.Default.Work, null, tint = Color.White.copy(0.82f), modifier = Modifier.size(12.dp))
                                    Text(profile.profession, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = Color.White.copy(0.82f))
                                }
                            }
                            if (profile.height > 0) {
                                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                                    Icon(Icons.Default.Height, null, tint = Color.White.copy(0.82f), modifier = Modifier.size(12.dp))
                                    Text("${profile.height} cm", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = Color.White.copy(0.82f))
                                }
                            }
                        }
                        if (profile.lookingFor.isNotBlank()) {
                            Box(modifier = Modifier.background(pink.copy(0.78f), RoundedCornerShape(50)).padding(horizontal = 12.dp, vertical = 7.dp)) {
                                Text(profile.lookingFor, fontSize = 13.sp, fontWeight = FontWeight.Bold, color = Color.White)
                            }
                        }
                    }
                }
            }

            // ── Bento grid ────────────────────────────────────────────────────
            AnimatedVisibility(visible = appeared, enter = fadeIn(tween(delayMillis = 60)) + slideInVertically(tween(delayMillis = 60)) { 20 }) {
                Row(
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp),
                    horizontalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    listOf(
                        Triple(Icons.Default.Work, profile.profession, pink),
                        Triple(Icons.Default.Height, if (profile.height > 0) "${profile.height} cm" else "", purple),
                        Triple(Icons.Default.Person, profile.gender, green),
                        Triple(Icons.Default.Favorite, profile.lookingFor, Color(0xFFFFB800))
                    ).filter { it.second.isNotBlank() }.forEach { (icon, value, color) ->
                        Column(
                            modifier = Modifier.weight(1f).background(CardBackground, RoundedCornerShape(14.dp)).border(1.dp, color.copy(0.15f), RoundedCornerShape(14.dp)).padding(12.dp),
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            Box(modifier = Modifier.size(32.dp).background(color.copy(0.12f), CircleShape), contentAlignment = Alignment.Center) {
                                Icon(icon, null, tint = color, modifier = Modifier.size(14.dp))
                            }
                            Text(value, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = TextPrimary, maxLines = 1)
                        }
                    }
                }
            }

            // ── Bio ───────────────────────────────────────────────────────────
            if (profile.bio.isNotBlank()) {
                AnimatedVisibility(visible = appeared, enter = fadeIn(tween(delayMillis = 110)) + slideInVertically(tween(delayMillis = 110)) { 20 }) {
                    Column(
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp).background(CardBackground, RoundedCornerShape(18.dp)).border(1.dp, purple.copy(0.2f), RoundedCornerShape(18.dp)).padding(18.dp),
                        verticalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            Icon(Icons.Default.FormatQuote, null, tint = pink, modifier = Modifier.size(14.dp))
                            Text("About", fontSize = 14.sp, fontWeight = FontWeight.Bold, color = TextPrimary)
                        }
                        Text(profile.bio, fontSize = 16.sp, fontWeight = FontWeight.Medium, color = TextSecondary, lineHeight = 22.sp)
                    }
                }
            }

            // ── Photo gallery (swipeable) ──────────────────────────────────────
            if (profile.photos.size > 1) {
                AnimatedVisibility(visible = appeared, enter = fadeIn(tween(delayMillis = 190)) + slideInVertically(tween(delayMillis = 190)) { 20 }) {
                    val extraPhotos = profile.photos.drop(1)
                    val hints = listOf("Ask about this moment", "This looks like a story", "A good photo to start with", "Ask where this was taken")
                    Column(modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                Icon(Icons.Default.PhotoLibrary, null, tint = pink, modifier = Modifier.size(14.dp))
                                Text("Photo Story", fontSize = 14.sp, fontWeight = FontWeight.Bold, color = TextPrimary)
                            }
                            Box(modifier = Modifier.background(SurfaceVariant, RoundedCornerShape(50)).padding(horizontal = 10.dp, vertical = 4.dp)) {
                                Text("${profile.photos.size}/6", fontSize = 11.sp, fontWeight = FontWeight.Bold, color = TextSecondary)
                            }
                        }
                        // Dot indicators
                        Row(horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                            extraPhotos.forEachIndexed { i, _ ->
                                Box(modifier = Modifier.size(if (i == photoPage) 18.dp else 7.dp, 7.dp).background(if (i == photoPage) Brush.linearGradient(listOf(pink, purple)) else Brush.linearGradient(listOf(Surface, Surface)), RoundedCornerShape(50)))
                            }
                        }
                        // Photos
                        extraPhotos.forEachIndexed { index, photo ->
                            val h = if (index % 2 == 0) 240.dp else 200.dp
                            Box(modifier = Modifier.fillMaxWidth().height(h).clip(RoundedCornerShape(20.dp)).background(SurfaceVariant, RoundedCornerShape(20.dp))) {
                                if (photo.cdnUrl != null) {
                                    val ctx = LocalContext.current
                                    AsyncImage(
                                        model = remember(photo.cdnUrl) { ImageRequest.Builder(ctx).data(photo.cdnUrl).crossfade(false).build() },
                                        contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize()
                                    )
                                }
                                Box(modifier = Modifier.fillMaxWidth().fillMaxHeight(0.55f).align(Alignment.BottomCenter).background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(0.82f)))))
                                Column(modifier = Modifier.align(Alignment.BottomStart).padding(14.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                    Text("Photo ${index + 2}", fontSize = 10.sp, fontWeight = FontWeight.Black, color = Color.White.copy(0.8f))
                                    Text(hints[index % hints.size], fontSize = 15.sp, fontWeight = FontWeight.Bold, color = Color.White)
                                }
                            }
                        }
                    }
                }
            }

            // ── Prompts ───────────────────────────────────────────────────────
            val answeredPrompts = profile.prompts.filter { it.answer.isNotBlank() }
            if (answeredPrompts.isNotEmpty()) {
                AnimatedVisibility(visible = appeared, enter = fadeIn(tween(delayMillis = 150)) + slideInVertically(tween(delayMillis = 150)) { 20 }) {
                    Column(modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            Icon(Icons.Default.Chat, null, tint = pink, modifier = Modifier.size(14.dp))
                            Text("Get to Know Me", fontSize = 14.sp, fontWeight = FontWeight.Bold, color = TextPrimary)
                        }
                        answeredPrompts.forEach { prompt ->
                            Row(
                                modifier = Modifier.fillMaxWidth().background(SurfaceVariant.copy(0.88f), RoundedCornerShape(18.dp)).border(1.dp, pink.copy(0.16f), RoundedCornerShape(18.dp)).padding(16.dp),
                                verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(12.dp)
                            ) {
                                Box(modifier = Modifier.size(34.dp).background(Brush.linearGradient(listOf(pink, purple)), CircleShape), contentAlignment = Alignment.Center) {
                                    Text("\"", fontSize = 16.sp, fontWeight = FontWeight.Black, color = Color.White)
                                }
                                Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                    Text(prompt.question.uppercase(), fontSize = 11.sp, fontWeight = FontWeight.Black, color = pink, letterSpacing = 0.8.sp)
                                    Text(prompt.answer, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = TextPrimary, lineHeight = 21.sp)
                                }
                            }
                        }
                    }
                }
            }

            // ── Interests ─────────────────────────────────────────────────────
            if (profile.interests.isNotEmpty()) {
                AnimatedVisibility(visible = appeared, enter = fadeIn(tween(delayMillis = 230)) + slideInVertically(tween(delayMillis = 230)) { 20 }) {
                    Column(modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            Icon(Icons.Default.AutoAwesome, null, tint = pink, modifier = Modifier.size(14.dp))
                            Text("Interests", fontSize = 14.sp, fontWeight = FontWeight.Bold, color = TextPrimary)
                        }
                        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            profile.interests.forEach { interest ->
                                val hash = kotlin.math.abs(interest.hashCode())
                                val colors = listOf(Color(0xFFFF6B9D) to Color(0xFFC44EFF), Color(0xFF00C8FF) to Color(0xFF0072FF), Color(0xFF00E5A0) to Color(0xFF00A6FF), Color(0xFFFFB800) to Color(0xFFFF6B9D))
                                val (c1, c2) = colors[hash % colors.size]
                                Box(
                                    modifier = Modifier.background(c1.copy(0.1f), RoundedCornerShape(50)).border(1.dp, c1.copy(0.25f), RoundedCornerShape(50)).padding(horizontal = 12.dp, vertical = 6.dp)
                                ) {
                                    Text(interest, fontSize = 13.sp, fontWeight = FontWeight.Medium, style = androidx.compose.ui.text.TextStyle(brush = Brush.linearGradient(listOf(c1, c2))))
                                }
                            }
                        }
                    }
                }
            }

            // Extra bottom space for floating action bar
            Spacer(modifier = Modifier.height(if (showActions) 100.dp else 32.dp))
        }

        Box(
            modifier = Modifier
                .fillMaxWidth()
                .statusBarsPadding()
                .padding(horizontal = 20.dp, vertical = 12.dp),
            contentAlignment = Alignment.TopEnd
        ) {
            IconButton(
                onClick = onDismiss,
                modifier = Modifier
                    .size(36.dp)
                    .background(Color.Black.copy(alpha = 0.28f), CircleShape)
                    .border(1.dp, Color.White.copy(alpha = 0.15f), CircleShape)
            ) {
                Icon(Icons.Default.Close, contentDescription = "Close", tint = Color.White)
            }
        }

        // Floating action bar — Like / Super Like / Pass (mirrors iOS floatingActionBar)
        if (showActions) {
            Box(
                modifier = Modifier
                    .fillMaxSize(),
                contentAlignment = Alignment.BottomCenter
            ) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(120.dp)
                        .background(
                            Brush.verticalGradient(
                                listOf(
                                    Background.copy(alpha = 0f),
                                    Background.copy(alpha = 0.95f),
                                    Background
                                )
                            )
                        )
                        .align(Alignment.BottomCenter)
                )
                FloatingDetailActionBar(
                    onPass = { onPass?.invoke(); onDismiss() },
                    onSuperLike = { onSuperLike?.invoke() },
                    onLike = { onLike?.invoke(); onDismiss() },
                    modifier = Modifier.padding(horizontal = 24.dp, vertical = 24.dp)
                )
            }
        }
    }
}

@Composable
private fun FloatingDetailActionBar(
    onPass: () -> Unit,
    onSuperLike: () -> Unit,
    onLike: () -> Unit,
    modifier: Modifier = Modifier
) {
    val pink = Color(0xFFFF6B9D)
    val purple = Color(0xFFC44EFF)

    Row(
        modifier = modifier
            .background(
                Brush.linearGradient(listOf(
                    Color(0xFF14141E).copy(0.82f), Color(0xFF14141E).copy(0.82f)
                )),
                RoundedCornerShape(50)
            )
            .border(
                1.dp,
                Brush.linearGradient(listOf(Color.White.copy(0.14f), pink.copy(0.20f), purple.copy(0.14f))),
                RoundedCornerShape(50)
            )
            .padding(horizontal = 32.dp, vertical = 14.dp),
        horizontalArrangement = Arrangement.spacedBy(20.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        // Pass button
        Box(
            modifier = Modifier.size(52.dp)
                .background(Color.White.copy(0.08f), CircleShape)
                .border(1.dp, Color.White.copy(0.12f), CircleShape)
                .clickable(
                    indication = null,
                    interactionSource = remember { androidx.compose.foundation.interaction.MutableInteractionSource() }
                ) { onPass() },
            contentAlignment = Alignment.Center
        ) {
            Icon(Icons.Default.Close, null, tint = Color(0xFF9999AA), modifier = Modifier.size(18.dp))
        }

        // Super Like button
        Box(
            modifier = Modifier.size(52.dp)
                .background(Color.White.copy(0.08f), CircleShape)
                .border(1.dp,
                    Brush.linearGradient(listOf(Color(0xFF00C8FF).copy(0.4f), purple.copy(0.3f))),
                    CircleShape)
                .clickable(
                    indication = null,
                    interactionSource = remember { androidx.compose.foundation.interaction.MutableInteractionSource() }
                ) { onSuperLike() },
            contentAlignment = Alignment.Center
        ) {
            Icon(Icons.Default.Star, null, tint = Color(0xFF00C8FF), modifier = Modifier.size(20.dp))
        }

        // Like button (largest, centre-piece)
        Box(
            modifier = Modifier.size(64.dp)
                .background(Brush.linearGradient(listOf(pink, purple)), CircleShape)
                .clickable(
                    indication = null,
                    interactionSource = remember { androidx.compose.foundation.interaction.MutableInteractionSource() }
                ) { onLike() },
            contentAlignment = Alignment.Center
        ) {
            Icon(Icons.Default.Favorite, null, tint = Color.White, modifier = Modifier.size(22.dp))
        }
    }
}
