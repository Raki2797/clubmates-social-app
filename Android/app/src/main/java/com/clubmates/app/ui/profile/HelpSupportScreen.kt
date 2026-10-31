package com.clubmates.app.ui.profile

import android.content.Intent
import android.net.Uri
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.clubmates.app.ui.theme.*

@Composable
fun HelpSupportScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    var expandedId by remember { mutableStateOf<String?>(null) }
    val pink = Color(0xFFFF6B9D)
    val purple = Color(0xFFC44EFF)

    Column(modifier = Modifier.fillMaxSize().background(Background)) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            IconButton(onClick = onBack) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back", tint = TextPrimary)
            }
            Spacer(modifier = Modifier.weight(1f))
            Text("Help & Support", fontSize = 18.sp, fontWeight = FontWeight.SemiBold, color = TextPrimary)
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
                Icon(Icons.Default.Forum, contentDescription = null, tint = pink, modifier = Modifier.size(36.dp))
                Text("We're here to help", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = TextPrimary)
                Text(
                    "Find answers to common questions below, or reach out to our support team directly.",
                    fontSize = 13.sp, color = TextSecondary,
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                    lineHeight = 18.sp
                )
            }

            // Contact
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp)
                    .background(CardBackground, RoundedCornerShape(16.dp))
                    .border(1.dp, Color.White.copy(alpha = 0.06f), RoundedCornerShape(16.dp))
            ) {
                ContactRow(icon = Icons.Default.Email, color = purple, title = "Email Support",
                    subtitle = "support@clubmates.app",
                    onClick = { context.startActivity(Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:support@clubmates.app"))) })
                HorizontalDivider(color = Color.White.copy(alpha = 0.06f), modifier = Modifier.padding(start = 60.dp))
                ContactRow(icon = Icons.Default.BugReport, color = pink, title = "Report a Bug",
                    subtitle = "bugs@clubmates.app",
                    onClick = { context.startActivity(Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:bugs@clubmates.app"))) })
            }

            // FAQs
            SectionLabel("Frequently Asked Questions")
            faqs.forEach { faq ->
                FaqCard(faq = faq, isExpanded = expandedId == faq.id, onToggle = {
                    expandedId = if (expandedId == faq.id) null else faq.id
                })
            }

            SectionLabel("Safety")
            safetyFaqs.forEach { faq ->
                FaqCard(faq = faq, isExpanded = expandedId == faq.id, onToggle = {
                    expandedId = if (expandedId == faq.id) null else faq.id
                })
            }

            Spacer(modifier = Modifier.height(24.dp))
        }
    }
}

@Composable
private fun SectionLabel(text: String) {
    Text(
        text.uppercase(),
        fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = TextHint,
        letterSpacing = 0.8.sp,
        modifier = Modifier.padding(horizontal = 24.dp, vertical = 4.dp)
    )
}

@Composable
private fun ContactRow(icon: ImageVector, color: Color, title: String, subtitle: String, onClick: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().clickable { onClick() }.padding(horizontal = 18.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        Box(
            modifier = Modifier.size(36.dp).background(color.copy(alpha = 0.12f), RoundedCornerShape(10.dp)),
            contentAlignment = Alignment.Center
        ) { Icon(icon, contentDescription = null, tint = color, modifier = Modifier.size(16.dp)) }
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, fontSize = 15.sp, fontWeight = FontWeight.Medium, color = TextPrimary)
            Text(subtitle, fontSize = 12.sp, color = TextSecondary)
        }
        Icon(Icons.AutoMirrored.Filled.ArrowForward, contentDescription = null, tint = TextHint, modifier = Modifier.size(14.dp))
    }
}

private data class Faq(val id: String, val question: String, val answer: String)

@Composable
private fun FaqCard(faq: Faq, isExpanded: Boolean, onToggle: () -> Unit) {
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
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text(faq.question, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = TextPrimary, modifier = Modifier.weight(1f))
            Icon(
                if (isExpanded) Icons.Default.KeyboardArrowUp else Icons.Default.KeyboardArrowDown,
                contentDescription = null, tint = TextHint, modifier = Modifier.size(18.dp)
            )
        }
        AnimatedVisibility(visible = isExpanded, enter = expandVertically(), exit = shrinkVertically()) {
            Column {
                HorizontalDivider(color = Color.White.copy(alpha = 0.06f), modifier = Modifier.padding(horizontal = 16.dp))
                Text(faq.answer, fontSize = 13.sp, color = TextSecondary, lineHeight = 18.sp,
                    modifier = Modifier.padding(16.dp))
            }
        }
    }
}

private val faqs = listOf(
    Faq("checkin", "How do I check in to a venue?",
        "Tap the building icon on the Discover tab. You must be physically within the venue's radius (usually 200m) for the check-in to succeed. ClubMates uses your GPS to verify this."),
    Faq("discover", "Why can't I see anyone on the discover feed?",
        "You need to be checked in to a venue to see other people. If you're checked in and still see nothing, try adjusting your Dating Preferences — your age or height filters may be too narrow, or 'Verified Only' may be on."),
    Faq("match", "How do matches work?",
        "When two people both like each other at the same venue, it's a match. You can then chat in the Chat tab. Matches are tied to the venue — you'll see where you first matched."),
    Faq("superlike", "What is a Super Like?",
        "Swiping up on a profile sends a Super Like. The other person sees a star on your profile in their discover feed, signalling that you're especially interested."),
    Faq("undo", "Can I undo a swipe?",
        "Yes — tap the undo button in the discover toolbar immediately after swiping. You can only undo the most recent swipe."),
    Faq("checkout", "What happens when I leave a venue?",
        "You are automatically checked out when you move beyond the venue radius. Your profile is no longer visible in the discover feed, but your matches and messages remain."),
    Faq("delete", "How do I delete my account?",
        "Go to Profile → scroll to the bottom → tap Delete Account. Your account is deactivated immediately and permanently deleted after 24 hours. You can cancel by logging back in within that window.")
)

private val safetyFaqs = listOf(
    Faq("block", "How do I block someone?",
        "Open a chat → tap the menu icon → Block. They will no longer appear in your discover feed and cannot see your profile."),
    Faq("report", "How do I report inappropriate behaviour?",
        "Open a chat → tap the menu icon → Report spam. Choose a category, add details if needed, and submit. Our team reviews all reports within 24 hours."),
    Faq("sos", "What is the SOS feature?",
        "If you feel unsafe, tap the SOS button in the Discover or Chat screen. It sends your current location and venue to our safety team and displays local emergency contacts."),
    Faq("verified", "What does the verified badge mean?",
        "A checkmark means the person has completed selfie verification — a live photo was compared to their profile photos to confirm they are a real person.")
)
