package com.clubmates.app.ui.profile

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.clubmates.app.ui.theme.*

@Composable
fun PrivacyScreen(onBack: () -> Unit) {
    var expandedId by remember { mutableStateOf<String?>(null) }
    val pink = Color(0xFFFF6B9D)

    Column(modifier = Modifier.fillMaxSize().background(Background)) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            IconButton(onClick = onBack) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back", tint = TextPrimary)
            }
            Spacer(modifier = Modifier.weight(1f))
            Text("Privacy Policy", fontSize = 18.sp, fontWeight = FontWeight.SemiBold, color = TextPrimary)
            Spacer(modifier = Modifier.weight(1f))
            Spacer(modifier = Modifier.size(48.dp))
        }
        HorizontalDivider(color = SurfaceVariant)

        Column(
            modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(vertical = 20.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            // Hero
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp)
                    .background(CardBackground, RoundedCornerShape(18.dp))
                    .border(1.dp, pink.copy(alpha = 0.15f), RoundedCornerShape(18.dp))
                    .padding(20.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Icon(Icons.Default.Lock, contentDescription = null, tint = pink, modifier = Modifier.size(36.dp))
                Text("Your privacy matters", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = TextPrimary)
                Text(
                    "ClubMates is built on the principle that you control your data. We collect only what's needed to run the app, never sell it, and delete it permanently when you ask.",
                    fontSize = 13.sp, color = TextSecondary,
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                    lineHeight = 18.sp
                )
            }

            privacySections.forEach { section ->
                PrivacyCard(section = section, isExpanded = expandedId == section.id, onToggle = {
                    expandedId = if (expandedId == section.id) null else section.id
                })
            }

            // Footer
            Column(
                modifier = Modifier.fillMaxWidth(),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                Text("Last updated June 2025", fontSize = 11.sp, color = TextHint)
                Text("Questions? Contact us at privacy@clubmates.app", fontSize = 11.sp, color = TextHint)
            }

            Spacer(modifier = Modifier.height(24.dp))
        }
    }
}

private data class PolicySection(val id: String, val icon: ImageVector, val color: Color, val title: String, val items: List<String>)

@Composable
private fun PrivacyCard(section: PolicySection, isExpanded: Boolean, onToggle: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 20.dp)
            .background(CardBackground, RoundedCornerShape(16.dp))
            .border(1.dp, Color.White.copy(alpha = 0.06f), RoundedCornerShape(16.dp))
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().clickable { onToggle() }.padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Box(
                modifier = Modifier.size(36.dp).background(section.color.copy(alpha = 0.12f), RoundedCornerShape(10.dp)),
                contentAlignment = Alignment.Center
            ) { Icon(section.icon, contentDescription = null, tint = section.color, modifier = Modifier.size(16.dp)) }
            Text(section.title, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = TextPrimary, modifier = Modifier.weight(1f))
            Icon(
                if (isExpanded) Icons.Default.KeyboardArrowUp else Icons.Default.KeyboardArrowDown,
                contentDescription = null, tint = TextHint, modifier = Modifier.size(18.dp)
            )
        }
        AnimatedVisibility(visible = isExpanded, enter = expandVertically(), exit = shrinkVertically()) {
            Column {
                HorizontalDivider(color = Color.White.copy(alpha = 0.06f), modifier = Modifier.padding(horizontal = 16.dp))
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    section.items.forEach { item ->
                        Row(
                            horizontalArrangement = Arrangement.spacedBy(10.dp),
                            verticalAlignment = Alignment.Top
                        ) {
                            Box(modifier = Modifier.size(5.dp).offset(y = 6.dp).background(section.color.copy(alpha = 0.7f), CircleShape))
                            Text(item, fontSize = 13.sp, color = TextSecondary, lineHeight = 18.sp)
                        }
                    }
                }
            }
        }
    }
}

private val privacySections = listOf(
    PolicySection("collect", Icons.Default.Inbox, Color(0xFFC44EFF), "What We Collect", listOf(
        "Phone number — used for OTP login only, never shown on your profile.",
        "Profile info — name, age, gender, height, profession, bio, interests, and prompts you provide.",
        "Photos — profile photos and a one-time verification selfie stored securely.",
        "Location — your GPS coordinates at check-in only, to verify you are within a venue's radius. We do not track your location continuously.",
        "Activity — swipes, matches, messages, and check-ins needed to run the app.",
        "Device token — your push notification token to deliver notifications you've enabled.",
        "Session data — a short-lived access token (15 min) and refresh token (30 days) to keep you logged in."
    )),
    PolicySection("use", Icons.Default.Settings, Color(0xFF00C853), "How We Use Your Data", listOf(
        "To match you with people at the same venue in real time.",
        "To show your profile to other users checked in at the same venue.",
        "To send push notifications for matches, messages, and likes — only for the types you've enabled.",
        "To verify your identity via selfie comparison so the community stays authentic.",
        "To enforce safety features like blocks, reports, and account deletion.",
        "We never use your data for advertising or sell it to third parties."
    )),
    PolicySection("store", Icons.Default.Storage, Color(0xFF2196F3), "How We Store It", listOf(
        "Profile data is stored in a PostgreSQL database hosted on Supabase.",
        "Photos are stored in Supabase Storage with access-controlled signed URLs.",
        "Session tokens are stored in Redis and expire automatically.",
        "OTP codes are hashed before storage and deleted immediately after use.",
        "All data is encrypted at rest and in transit over HTTPS/WSS."
    )),
    PolicySection("share", Icons.Default.People, Color(0xFFFF6B9D), "What Others Can See", listOf(
        "Other users at the same venue can see your name, age, photos, bio, prompts, interests, height, profession, and Looking For status.",
        "Your phone number is never shown to other users.",
        "Your exact GPS location is never shared — only your venue check-in is visible.",
        "After you leave a venue, you are no longer visible in the discover feed.",
        "Blocked or reported users cannot see your profile."
    )),
    PolicySection("retention", Icons.Default.Schedule, Color(0xFFFFB800), "How Long We Keep It", listOf(
        "Your data is kept for as long as your account is active.",
        "OTP codes are deleted immediately after a successful login.",
        "Session tokens expire after 30 days of inactivity.",
        "Check-in location coordinates are not stored after the check-in session ends.",
        "When you delete your account, a 24-hour grace period begins.",
        "After 24 hours, all your data is permanently deleted: profile, photos, matches, messages, swipes, and device tokens."
    )),
    PolicySection("rights", Icons.Default.PanTool, Color(0xFF00C853), "Your Rights", listOf(
        "Access — you can view all your profile data directly in the app.",
        "Edit — update or delete any part of your profile at any time.",
        "Delete — delete your account from Profile → Settings. All data is permanently erased within 24 hours.",
        "Notifications — manage exactly which notifications you receive from Profile → Notifications.",
        "Discovery — control who sees you by adjusting your Dating Preferences.",
        "Block & Report — remove any user from your experience at any time."
    ))
)
