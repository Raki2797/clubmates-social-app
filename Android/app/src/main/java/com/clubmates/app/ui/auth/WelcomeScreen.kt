package com.clubmates.app.ui.auth

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.clubmates.app.ui.theme.*

enum class AuthIntent { Login, CreateAccount }

private val pink = Color(0xFFFF6B9D)
private val purple = Color(0xFFC44EFF)
private val primaryGradient = Brush.linearGradient(listOf(pink, purple))

@Composable
fun WelcomeScreen(
    onCreateAccount: () -> Unit,
    onLogin: () -> Unit,
    isLoggedIn: Boolean,
    onAlreadyLoggedIn: () -> Unit
) {
    LaunchedEffect(isLoggedIn) {
        if (isLoggedIn) onAlreadyLoggedIn()
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Background)
    ) {
        // Background orbs — mirrors iOS ZStack orbs
        Box(
            modifier = Modifier
                .size(400.dp)
                .offset(x = (-100).dp, y = (-220).dp)
                .background(
                    Brush.radialGradient(
                        colors = listOf(purple.copy(alpha = 0.25f), Color.Transparent),
                        center = Offset(200f, 200f),
                        radius = 400f
                    ),
                    CircleShape
                )
        )
        Box(
            modifier = Modifier
                .size(360.dp)
                .align(Alignment.BottomEnd)
                .offset(x = 60.dp, y = (-80).dp)
                .background(
                    Brush.radialGradient(
                        colors = listOf(pink.copy(alpha = 0.2f), Color.Transparent),
                        center = Offset(180f, 180f),
                        radius = 360f
                    ),
                    CircleShape
                )
        )

        Column(
            modifier = Modifier.fillMaxSize(),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Spacer(modifier = Modifier.weight(1f))

            // Brand section — heart logo + title + subtitle
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(20.dp)
            ) {
                Box(
                    modifier = Modifier
                        .size(88.dp)
                        .background(primaryGradient, CircleShape),
                    contentAlignment = Alignment.Center
                ) {
                    Text("♥", fontSize = 40.sp, color = Color.White, fontWeight = FontWeight.Bold)
                }

                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Text(
                        "ClubMates",
                        fontSize = 38.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.Transparent,
                        style = MaterialTheme.typography.displaySmall.copy(
                            brush = primaryGradient,
                            fontWeight = FontWeight.Bold
                        )
                    )
                    Text(
                        "Meet people at the same venues.\nSwipe, match, and connect.",
                        fontSize = 16.sp,
                        color = TextSecondary,
                        textAlign = TextAlign.Center,
                        lineHeight = 24.sp
                    )
                }
            }

            Spacer(modifier = Modifier.weight(1f))

            // CTA section
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 24.dp)
                    .padding(bottom = 48.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                // Create Account — gradient fill, capsule shape
                Button(
                    onClick = onCreateAccount,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(56.dp),
                    shape = RoundedCornerShape(22.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = Color.Transparent),
                    contentPadding = PaddingValues(0.dp)
                ) {
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .background(primaryGradient, RoundedCornerShape(22.dp)),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(
                            "Create Account",
                            fontSize = 17.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = Color.White
                        )
                    }
                }

                // Log In — surface fill with border
                OutlinedButton(
                    onClick = onLogin,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(56.dp),
                    shape = RoundedCornerShape(22.dp),
                    colors = ButtonDefaults.outlinedButtonColors(
                        contentColor = TextPrimary,
                        containerColor = Surface
                    ),
                    border = androidx.compose.foundation.BorderStroke(1.dp, Surface)
                ) {
                    Text(
                        "Log In",
                        fontSize = 17.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = TextPrimary
                    )
                }

                Text(
                    "By continuing you agree to our Terms & Privacy Policy.",
                    fontSize = 12.sp,
                    color = TextHint,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.padding(top = 4.dp)
                )
            }
        }
    }
}
