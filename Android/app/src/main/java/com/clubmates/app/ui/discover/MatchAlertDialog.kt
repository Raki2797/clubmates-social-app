package com.clubmates.app.ui.discover

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import com.clubmates.app.domain.model.UserProfile
import com.clubmates.app.ui.components.AvatarImage
import com.clubmates.app.ui.theme.*

@Composable
fun MatchAlertDialog(
    profile: UserProfile,
    onDismiss: () -> Unit,
    onSendMessage: () -> Unit
) {
    Dialog(onDismissRequest = onDismiss) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .background(
                    Brush.verticalGradient(listOf(Color(0xFF2A0A4A), Color(0xFF0A0A1A))),
                    RoundedCornerShape(24.dp)
                )
                .padding(32.dp),
            contentAlignment = Alignment.Center
        ) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(20.dp)
            ) {
                Text("It's a Match! 💫", fontSize = 28.sp, fontWeight = FontWeight.Bold, color = TextPrimary, textAlign = TextAlign.Center)
                Text("You and ${profile.name} liked each other!", fontSize = 16.sp, color = TextSecondary, textAlign = TextAlign.Center)

                AvatarImage(photoUrl = profile.photos.firstOrNull()?.cdnUrl, size = 100.dp)

                Text(profile.name, fontSize = 22.sp, fontWeight = FontWeight.SemiBold, color = TextPrimary)

                Button(
                    onClick = onSendMessage,
                    modifier = Modifier.fillMaxWidth().height(50.dp),
                    shape = RoundedCornerShape(14.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = Primary)
                ) { Text("Send a Message", fontSize = 16.sp, fontWeight = FontWeight.SemiBold) }

                TextButton(onClick = onDismiss) {
                    Text("Keep Swiping", color = TextSecondary, fontSize = 15.sp)
                }
            }
        }
    }
}
