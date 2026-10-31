package com.clubmates.app.ui.profile

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.clubmates.app.domain.model.NotificationPreferences
import com.clubmates.app.ui.theme.*

private val notifPink = Color(0xFFFF6B9D)
private val notifPurple = Color(0xFFC44EFF)
private val notifGreen = Color(0xFF00C853)
private val notifGold = Color(0xFFFFB800)

@Composable
fun NotificationSettingsScreen(
    onBack: () -> Unit,
    viewModel: ProfileViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    val profile = uiState.profile ?: return

    var prefs by remember { mutableStateOf(profile.notificationPreferences) }

    val saveAndBack = {
        viewModel.patchProfile(
            com.clubmates.app.data.network.PatchProfileRequest(
                notificationPreferences = com.clubmates.app.data.network.ApiNotificationPreferences(
                    enabled = prefs.enabled, newMatch = prefs.newMatch,
                    newMessage = prefs.newMessage, likedYou = prefs.likedYou,
                    superLike = prefs.superLike, venueActivity = prefs.venueActivity
                )
            )
        )
        onBack()
    }

    Column(modifier = Modifier.fillMaxSize().background(Background)) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            IconButton(onClick = onBack) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back", tint = TextPrimary)
            }
            Text("Notifications", fontSize = 18.sp, fontWeight = FontWeight.SemiBold, color = TextPrimary)
            TextButton(onClick = saveAndBack, enabled = !uiState.isSaving) {
                if (uiState.isSaving) CircularProgressIndicator(color = notifPink, strokeWidth = 2.dp, modifier = Modifier.size(20.dp))
                else Text("Done", color = notifPink, fontWeight = FontWeight.SemiBold)
            }
        }
        HorizontalDivider(color = SurfaceVariant)

        Column(
            modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            // Master toggle
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(CardBackground, RoundedCornerShape(16.dp))
                    .border(1.dp, notifPink.copy(alpha = 0.18f), RoundedCornerShape(16.dp))
                    .padding(16.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(14.dp)
            ) {
                Box(
                    modifier = Modifier.size(42.dp).background(notifPurple.copy(alpha = 0.15f), CircleShape),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        if (prefs.enabled) Icons.Default.Notifications else Icons.Default.NotificationsOff,
                        contentDescription = null,
                        tint = notifPurple,
                        modifier = Modifier.size(20.dp)
                    )
                }
                Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text("Enable Notifications", fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = TextPrimary)
                    Text(
                        if (prefs.enabled) "You'll receive push notifications" else "All notifications are turned off",
                        fontSize = 12.sp, color = TextSecondary
                    )
                }
                Switch(
                    checked = prefs.enabled,
                    onCheckedChange = { prefs = prefs.copy(enabled = it) },
                    colors = SwitchDefaults.colors(checkedThumbColor = notifPink, checkedTrackColor = notifPink.copy(alpha = 0.4f))
                )
            }

            // Individual toggles
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(CardBackground, RoundedCornerShape(16.dp))
                    .border(1.dp, Color.White.copy(alpha = 0.06f), RoundedCornerShape(16.dp))
                    .then(if (!prefs.enabled) Modifier.then(Modifier) else Modifier)
            ) {
                val alpha = if (prefs.enabled) 1f else 0.4f

                NotifRow(icon = Icons.Default.Favorite, color = notifPink, title = "New Matches",
                    subtitle = "When someone matches with you",
                    checked = prefs.newMatch, enabled = prefs.enabled,
                    onCheckedChange = { prefs = prefs.copy(newMatch = it) }, alpha = alpha)
                HorizontalDivider(color = Color.White.copy(alpha = 0.06f), modifier = Modifier.padding(start = 68.dp))

                NotifRow(icon = Icons.Default.ChatBubble, color = notifPurple, title = "New Messages",
                    subtitle = "When a match sends you a message",
                    checked = prefs.newMessage, enabled = prefs.enabled,
                    onCheckedChange = { prefs = prefs.copy(newMessage = it) }, alpha = alpha)
                HorizontalDivider(color = Color.White.copy(alpha = 0.06f), modifier = Modifier.padding(start = 68.dp))

                NotifRow(icon = Icons.Default.ThumbUp, color = notifGreen, title = "Someone Liked You",
                    subtitle = "When someone swipes right on you",
                    checked = prefs.likedYou, enabled = prefs.enabled,
                    onCheckedChange = { prefs = prefs.copy(likedYou = it) }, alpha = alpha)
                HorizontalDivider(color = Color.White.copy(alpha = 0.06f), modifier = Modifier.padding(start = 68.dp))

                NotifRow(icon = Icons.Default.Star, color = notifGold, title = "Invites",
                    subtitle = "When someone sends you a treat invite",
                    checked = prefs.superLike, enabled = prefs.enabled,
                    onCheckedChange = { prefs = prefs.copy(superLike = it) }, alpha = alpha)
                HorizontalDivider(color = Color.White.copy(alpha = 0.06f), modifier = Modifier.padding(start = 68.dp))

                NotifRow(icon = Icons.Default.LocationOn, color = Color(0xFF2196F3), title = "Venue Activity",
                    subtitle = "When a match checks in at your venue",
                    checked = prefs.venueActivity, enabled = prefs.enabled,
                    onCheckedChange = { prefs = prefs.copy(venueActivity = it) }, alpha = alpha)
            }
        }
    }
}

@Composable
private fun NotifRow(
    icon: ImageVector,
    color: Color,
    title: String,
    subtitle: String,
    checked: Boolean,
    enabled: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    alpha: Float
) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 18.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        Box(
            modifier = Modifier.size(36.dp).background(color.copy(alpha = 0.12f), RoundedCornerShape(10.dp)),
            contentAlignment = Alignment.Center
        ) {
            Icon(icon, contentDescription = null, tint = color.copy(alpha = alpha), modifier = Modifier.size(16.dp))
        }
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, fontSize = 15.sp, fontWeight = FontWeight.Medium, color = TextPrimary.copy(alpha = alpha))
            Text(subtitle, fontSize = 12.sp, color = TextSecondary.copy(alpha = alpha))
        }
        Switch(
            checked = checked,
            onCheckedChange = onCheckedChange,
            enabled = enabled,
            colors = SwitchDefaults.colors(
                checkedThumbColor = Color(0xFFFF6B9D),
                checkedTrackColor = Color(0xFFFF6B9D).copy(alpha = 0.4f)
            )
        )
    }
}
