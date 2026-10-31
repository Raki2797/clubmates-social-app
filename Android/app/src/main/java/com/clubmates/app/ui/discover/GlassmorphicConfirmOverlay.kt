package com.clubmates.app.ui.discover

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.clubmates.app.ui.theme.*

/**
 * Custom glassmorphic confirmation overlay matching iOS checkOutOverlay / sosOverlay design.
 * Replaces Material3 AlertDialog for full visual parity with iOS.
 *
 * Identical structure in both iOS overlays:
 * - Black 70% scrim with tap-to-dismiss
 * - Gradient icon circle with shadow
 * - Title + body text
 * - Primary CTA (gradient capsule) + cancel (surface capsule)
 * - BounceButtonStyle equivalent: scale 0.87 on press
 * - Card: cardBackground fill, gradient border, dual shadow, scale(0.9)+opacity entry transition
 */
@Composable
fun GlassmorphicConfirmOverlay(
    iconRes: ImageVector,
    iconTint: Color,
    iconGradient: Brush,
    borderGradient: Brush,
    title: String,
    body: String,
    confirmLabel: String,
    cancelLabel: String,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit
) {
    val pink = Color(0xFFFF6B9D)
    val purple = Color(0xFFC44EFF)
    val primaryGradient = Brush.linearGradient(listOf(pink, purple))

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black.copy(alpha = 0.70f))
            .clickable(
                indication = null,
                interactionSource = remember { MutableInteractionSource() }
            ) { onDismiss() },
        contentAlignment = Alignment.Center
    ) {
        Column(
            modifier = Modifier
                .padding(horizontal = 32.dp)
                .background(CardBackground, RoundedCornerShape(24.dp))
                .border(1.dp, borderGradient, RoundedCornerShape(24.dp))
                .clickable(
                    indication = null,
                    interactionSource = remember { MutableInteractionSource() }
                ) { /* consume tap — don't dismiss */ },
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Spacer(Modifier.height(32.dp))

            // Icon circle with gradient background + shadow
            Box(
                modifier = Modifier.size(64.dp).background(iconGradient, CircleShape),
                contentAlignment = Alignment.Center
            ) {
                androidx.compose.material3.Icon(
                    iconRes, null, tint = Color.White,
                    modifier = Modifier.size(26.dp)
                )
            }

            Spacer(Modifier.height(20.dp))

            Text(
                title,
                fontSize = 22.sp, fontWeight = FontWeight.Bold, color = TextPrimary,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(horizontal = 24.dp)
            )

            Spacer(Modifier.height(8.dp))

            Text(
                body,
                fontSize = 15.sp, color = TextSecondary,
                textAlign = TextAlign.Center,
                lineHeight = 22.sp,
                modifier = Modifier.padding(horizontal = 24.dp)
            )

            Spacer(Modifier.height(28.dp))

            Column(
                modifier = Modifier.padding(horizontal = 24.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                // Primary / confirm button — gradient capsule
                BounceButton(onClick = onConfirm) {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .background(primaryGradient, RoundedCornerShape(50))
                            .padding(vertical = 16.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(
                            confirmLabel,
                            fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = Color.White
                        )
                    }
                }

                // Cancel / secondary button — surface capsule
                BounceButton(onClick = onDismiss) {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .background(Surface, RoundedCornerShape(50))
                            .padding(vertical = 16.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(
                            cancelLabel,
                            fontSize = 16.sp, fontWeight = FontWeight.Medium, color = TextSecondary
                        )
                    }
                }
            }

            Spacer(Modifier.height(28.dp))
        }
    }
}

/**
 * BounceButtonStyle equivalent — scales to 0.87 on press, springs back.
 * Mirrors iOS BounceButtonStyle: scaleEffect(isPressed ? 0.87 : 1)
 */
@Composable
fun BounceButton(onClick: () -> Unit, content: @Composable () -> Unit) {
    val interactionSource = remember { MutableInteractionSource() }
    val isPressed by interactionSource.collectIsPressedAsState()
    val scale = if (isPressed) 0.87f else 1f

    Box(
        modifier = Modifier
            .scale(scale)
            .clickable(
                interactionSource = interactionSource,
                indication = null,
                onClick = onClick
            )
    ) {
        content()
    }
}
