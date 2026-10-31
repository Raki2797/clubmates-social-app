package com.clubmates.app.ui.profile

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.clubmates.app.ui.theme.*

private val onboardingPink = Color(0xFFFF6B9D)
private val onboardingPurple = Color(0xFFC44EFF)
private val onboardingGradient = Brush.linearGradient(listOf(onboardingPink, onboardingPurple))

@Composable
fun OnboardingHeader(
    step: Int,
    totalSteps: Int,
    onBack: (() -> Unit)?
) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        // Back button or spacer
        if (onBack != null) {
            IconButton(onClick = onBack, modifier = Modifier.size(42.dp)) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back", tint = TextPrimary)
            }
        } else {
            Spacer(modifier = Modifier.size(42.dp))
        }

        // Title + step
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text("ClubMates", fontSize = 17.sp, fontWeight = FontWeight.Bold, color = TextPrimary)
            Text("Step $step of $totalSteps", fontSize = 13.sp, color = TextSecondary)
        }

        // Step pills
        Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
            repeat(totalSteps) { i ->
                Box(
                    modifier = Modifier
                        .width(16.dp)
                        .height(6.dp)
                        .background(
                            if (i < step) onboardingGradient else Brush.linearGradient(listOf(TextHint.copy(alpha = 0.45f), TextHint.copy(alpha = 0.45f))),
                            RoundedCornerShape(50)
                        )
                )
            }
        }
    }
    HorizontalDivider(color = SurfaceVariant)
}

@Composable
fun OnboardingBottomBar(
    label: String,
    enabled: Boolean,
    isLoading: Boolean,
    step: Int,
    totalSteps: Int,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Surface(
        modifier = modifier.fillMaxWidth(),
        color = Background,
        shadowElevation = 8.dp
    ) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Button(
                onClick = onClick,
                enabled = enabled && !isLoading,
                modifier = Modifier.fillMaxWidth().height(54.dp),
                shape = RoundedCornerShape(18.dp),
                colors = ButtonDefaults.buttonColors(containerColor = Color.Transparent),
                contentPadding = PaddingValues(0.dp)
            ) {
                Box(
                    modifier = Modifier.fillMaxSize().background(if (enabled) onboardingGradient else Brush.linearGradient(listOf(TextHint.copy(0.4f), TextHint.copy(0.4f))), RoundedCornerShape(18.dp)),
                    contentAlignment = Alignment.Center
                ) {
                    if (isLoading) {
                        CircularProgressIndicator(modifier = Modifier.size(20.dp), color = Color.White, strokeWidth = 2.dp)
                    } else {
                        Text(label, fontSize = 16.sp, fontWeight = FontWeight.Bold, color = Color.White)
                    }
                }
            }
        }
    }
}
