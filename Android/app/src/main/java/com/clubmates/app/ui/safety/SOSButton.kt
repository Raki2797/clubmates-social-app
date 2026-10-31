package com.clubmates.app.ui.safety

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.clubmates.app.ui.theme.TextPrimary

@Composable
fun SOSButton(
    source: String,
    venueId: String? = null,
    matchId: String? = null,
    compact: Boolean = false,
    viewModel: SOSViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    var showConfirm by remember { mutableStateOf(false) }

    LaunchedEffect(uiState.success) {
        if (uiState.success) {
            kotlinx.coroutines.delay(2000)
            viewModel.clearSuccess()
        }
    }

    // Confirmation dialog
    if (showConfirm) {
        AlertDialog(
            onDismissRequest = { showConfirm = false },
            title = { Text("Emergency SOS", color = TextPrimary) },
            text = { Text("This will alert the ClubMates safety team with your location. Use only in a genuine emergency.") },
            confirmButton = {
                TextButton(onClick = {
                    showConfirm = false
                    viewModel.triggerSOS(source = source, venueId = venueId, matchId = matchId)
                }) {
                    Text("Send SOS", color = Color.Red, fontWeight = FontWeight.Bold)
                }
            },
            dismissButton = {
                TextButton(onClick = { showConfirm = false }) {
                    Text("Cancel")
                }
            }
        )
    }

    // Error dialog
    uiState.error?.let { err ->
        AlertDialog(
            onDismissRequest = { viewModel.clearError() },
            title = { Text("SOS Failed", color = TextPrimary) },
            text = { Text(err) },
            confirmButton = { TextButton(onClick = { viewModel.clearError() }) { Text("OK") } }
        )
    }

    if (compact) {
        FilledIconButton(
            onClick = { if (!uiState.isTriggering && !uiState.success) showConfirm = true },
            modifier = Modifier
                .size(42.dp)
                .clip(RoundedCornerShape(21.dp)),
            colors = IconButtonDefaults.filledIconButtonColors(
                containerColor = if (uiState.success) Color(0xFF4CAF50) else Color.Red,
                disabledContainerColor = Color.Red.copy(alpha = 0.5f),
                contentColor = Color.White
            ),
            enabled = !uiState.isTriggering
        ) {
            if (uiState.isTriggering) {
                CircularProgressIndicator(
                    modifier = Modifier.size(16.dp),
                    color = Color.White,
                    strokeWidth = 2.dp
                )
            } else {
                Icon(
                    if (uiState.success) Icons.Default.Shield else Icons.Default.Warning,
                    contentDescription = if (uiState.success) "SOS sent" else "Emergency SOS",
                    tint = Color.White,
                    modifier = Modifier.size(18.dp)
                )
            }
        }
    } else {
        Button(
            onClick = { if (!uiState.isTriggering && !uiState.success) showConfirm = true },
            modifier = Modifier.height(44.dp),
            shape = RoundedCornerShape(22.dp),
            colors = ButtonDefaults.buttonColors(
                containerColor = if (uiState.success) Color(0xFF4CAF50) else Color.Red,
                disabledContainerColor = Color.Red.copy(alpha = 0.5f)
            ),
            enabled = !uiState.isTriggering
        ) {
            if (uiState.isTriggering) {
                CircularProgressIndicator(modifier = Modifier.size(18.dp), color = Color.White, strokeWidth = 2.dp)
            } else {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Icon(Icons.Default.Shield, contentDescription = null, tint = Color.White, modifier = Modifier.size(18.dp))
                    Text(
                        if (uiState.success) "Sent" else "SOS",
                        color = Color.White,
                        fontWeight = FontWeight.Bold,
                        fontSize = 14.sp
                    )
                }
            }
        }
    }
}
