package com.clubmates.app.ui.auth

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Phone
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Restore
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import com.clubmates.app.ui.theme.*

internal val authPink = Color(0xFFFF6B9D)
internal val authPurple = Color(0xFFC44EFF)
val authGradient = Brush.linearGradient(listOf(authPink, authPurple))
internal val heroBrush = Brush.linearGradient(
    listOf(Color(0xFF24103D), Color(0xFF571A53), Color(0xFF8D2D63))
)

@Composable
fun PhoneInputScreen(
    intent: AuthIntent,
    viewModel: AuthViewModel,
    onOtpSent: (String) -> Unit,
    onBack: () -> Unit = {}
) {
    val uiState by viewModel.uiState.collectAsState()
    var phoneDigits by remember { mutableStateOf("") }
    val focusRequester = remember { FocusRequester() }
    val keyboardController = LocalSoftwareKeyboardController.current
    val fullPhone = "+91$phoneDigits"
    var showAccountExistsDialog by remember { mutableStateOf(false) }

    // Clear any existing auth state so OtpScreen doesn't auto-skip if the user
    // was previously logged in and is now starting a fresh login flow.
    LaunchedEffect(Unit) { viewModel.startAuthFlow() }

    LaunchedEffect(uiState.otpSent) {
        if (uiState.otpSent) {
            viewModel.resetOtpSent()
            onOtpSent(fullPhone)
        }
    }
    LaunchedEffect(uiState.accountExistsForPhone) {
        if (uiState.accountExistsForPhone) {
            showAccountExistsDialog = true
        }
    }
    LaunchedEffect(Unit) { focusRequester.requestFocus() }

    if (showAccountExistsDialog) {
        AuthAccountExistsOverlay(
            phone = fullPhone,
            onDismiss = {
                showAccountExistsDialog = false
                viewModel.clearAccountExists()
            },
            onLoginInstead = {
                showAccountExistsDialog = false
                viewModel.clearAccountExists()
                viewModel.resetOtpSent()
                onOtpSent(fullPhone)
            }
        )
    }

    val pillCount = if (intent == AuthIntent.CreateAccount) 4 else 2

    Column(modifier = Modifier.fillMaxSize().background(Background).imePadding()) {
        // Header — back button, centred title, progress pills
        AuthHeader(
            title = "ClubMates",
            subtitle = if (intent == AuthIntent.Login) "Log In" else "Create Account",
            pillCount = pillCount,
            activeUpTo = 1,
            onBack = onBack
        )

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp)
                .padding(top = 24.dp, bottom = 40.dp),
            verticalArrangement = Arrangement.spacedBy(24.dp)
        ) {
            // Hero card
            AuthHeroCard(
                eyebrow = if (intent == AuthIntent.Login) "Welcome Back" else "Get Started",
                headline = if (intent == AuthIntent.Login) "Sign back in." else "Create your account.",
                body = if (intent == AuthIntent.Login)
                    "Enter your phone number to log back in to ClubMates."
                else
                    "Enter your phone number to get started. You'll set up your profile next."
            )

            // Input card
            AuthInputCard(title = "Mobile Number", subtitle = "Enter your number to continue. We default to India with +91.") {
                AuthNumberFieldContainer {
                    Icon(Icons.Default.Phone, contentDescription = null, tint = authPink, modifier = Modifier.size(20.dp))
                    Box(modifier = Modifier.width(1.dp).height(28.dp).background(Surface))
                    Text("+91", fontSize = 18.sp, fontWeight = FontWeight.Bold, color = TextPrimary)
                    BasicTextField(
                        value = phoneDigits,
                        onValueChange = { v ->
                            if (v.length <= 10 && v.all { c -> c.isDigit() }) {
                                phoneDigits = v
                                if (v.length == 10) keyboardController?.hide()
                            }
                        },
                        modifier = Modifier
                            .weight(1f)
                            .focusRequester(focusRequester),
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone, imeAction = ImeAction.Done),
                        keyboardActions = KeyboardActions(onDone = { if (phoneDigits.length == 10) viewModel.sendOtp(fullPhone, intent) }),
                        singleLine = true,
                        textStyle = TextStyle(
                            fontSize = 20.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = TextPrimary
                        ),
                        cursorBrush = SolidColor(authPink),
                        decorationBox = { innerTextField ->
                            Box(contentAlignment = Alignment.CenterStart) {
                                if (phoneDigits.isBlank()) {
                                    Text(
                                        "98765 43210",
                                        color = TextHint,
                                        fontSize = 20.sp,
                                        fontWeight = FontWeight.SemiBold
                                    )
                                }
                                innerTextField()
                            }
                        }
                    )
                }

                uiState.error?.let { err ->
                    Spacer(modifier = Modifier.height(4.dp))
                    AuthErrorRow(err)
                }
            }

            // Account deletion restore notice
            uiState.deletionScheduledAt?.let { scheduledAt ->
                AuthRestoreCard(scheduledAt = scheduledAt)
            }

            // Build note card
            AuthNoteCard(
                title = "SMS Verification",
                body = "We will send a 6-digit login code to this number."
            )
        }

        // Continue button pinned to bottom
        AuthContinueButton(
            label = if (uiState.deletionScheduledAt != null) "Restore Account" else "Continue",
            enabled = phoneDigits.length == 10 && !uiState.isLoading,
            isLoading = uiState.isLoading,
            onClick = { viewModel.sendOtp(fullPhone, intent, restore = uiState.deletionScheduledAt != null) }
        )
    }
}

// ─── Shared auth layout components ───────────────────────────────────────────

@Composable
private fun AuthAccountExistsOverlay(
    phone: String,
    onDismiss: () -> Unit,
    onLoginInstead: () -> Unit
) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black.copy(alpha = 0.7f))
            .padding(horizontal = 32.dp),
        contentAlignment = Alignment.Center
    ) {
        Surface(
            color = CardBackground,
            shape = RoundedCornerShape(28.dp),
            modifier = Modifier
                .fillMaxWidth()
                .border(
                    width = 1.dp,
                    brush = Brush.linearGradient(
                        listOf(
                            Color.White.copy(alpha = 0.12f),
                            authPurple.copy(alpha = 0.2f),
                            Color.White.copy(alpha = 0.06f)
                        )
                    ),
                    shape = RoundedCornerShape(28.dp)
                ),
            tonalElevation = 0.dp
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Box(
                    modifier = Modifier
                        .padding(top = 32.dp)
                        .size(64.dp)
                        .background(authGradient, CircleShape),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(Icons.Default.Person, contentDescription = null, tint = Color.White, modifier = Modifier.size(26.dp))
                }

                Text(
                    "Already a Member?",
                    fontSize = 22.sp,
                    fontWeight = FontWeight.Bold,
                    color = TextPrimary,
                    modifier = Modifier.padding(top = 20.dp)
                )
                Text(
                    "An account with $phone already exists.",
                    fontSize = 15.sp,
                    color = TextSecondary,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.padding(horizontal = 24.dp, vertical = 8.dp)
                )
                Text(
                    "Would you like to log in instead?",
                    fontSize = 15.sp,
                    color = TextSecondary,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.padding(horizontal = 24.dp)
                )

                Column(
                    modifier = Modifier.padding(horizontal = 24.dp, vertical = 28.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    Button(
                        onClick = onLoginInstead,
                        modifier = Modifier.fillMaxWidth().height(52.dp),
                        shape = RoundedCornerShape(999.dp),
                        colors = ButtonDefaults.buttonColors(containerColor = Color.Transparent),
                        contentPadding = PaddingValues(0.dp)
                    ) {
                        Box(
                            modifier = Modifier
                                .fillMaxSize()
                                .background(authGradient, RoundedCornerShape(999.dp)),
                            contentAlignment = Alignment.Center
                        ) {
                            Text("Log In Instead", color = Color.White, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
                        }
                    }

                    Button(
                        onClick = onDismiss,
                        modifier = Modifier.fillMaxWidth().height(52.dp),
                        shape = RoundedCornerShape(999.dp),
                        colors = ButtonDefaults.buttonColors(containerColor = Surface)
                    ) {
                        Text("Cancel", color = TextSecondary, fontSize = 16.sp, fontWeight = FontWeight.Medium)
                    }
                }
            }
        }
    }
}

@Composable
fun AuthNumberFieldContainer(content: @Composable RowScope.() -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(CardBackground, RoundedCornerShape(26.dp))
            .border(1.dp, Surface, RoundedCornerShape(26.dp))
            .padding(horizontal = 18.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
        content = content
    )
}

@Composable
fun AuthHeader(
    title: String,
    subtitle: String,
    pillCount: Int,
    activeUpTo: Int,
    onBack: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 20.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        // Back button
        IconButton(
            onClick = onBack,
            modifier = Modifier.size(42.dp).background(Surface, CircleShape)
        ) {
            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back", tint = TextPrimary)
        }

        Spacer(modifier = Modifier.weight(1f))

        // Centred title
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(title, fontSize = 18.sp, fontWeight = FontWeight.Bold, color = TextPrimary)
            Text(subtitle, fontSize = 12.sp, fontWeight = FontWeight.Medium, color = TextSecondary)
        }

        Spacer(modifier = Modifier.weight(1f))

        // Progress pills
        Row(
            modifier = Modifier.width(42.dp),
            horizontalArrangement = Arrangement.spacedBy(4.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            repeat(pillCount) { index ->
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .height(6.dp)
                        .background(
                            if (index < activeUpTo) authPink else TextHint.copy(alpha = 0.45f),
                            RoundedCornerShape(3.dp)
                        )
                )
            }
        }
    }
}

@Composable
fun AuthHeroCard(eyebrow: String, headline: String, body: String) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(250.dp)
            .background(heroBrush, RoundedCornerShape(32.dp))
    ) {
        // Decorative circles
        Box(
            modifier = Modifier
                .size(220.dp)
                .offset(x = 120.dp, y = (-90).dp)
                .background(Color.White.copy(alpha = 0.08f), CircleShape)
        )
        Box(
            modifier = Modifier
                .size(140.dp)
                .offset(x = (-30).dp, y = (-100).dp)
                .background(Color.White.copy(alpha = 0.05f), CircleShape)
        )
        Column(
            modifier = Modifier
                .align(Alignment.BottomStart)
                .padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Text(
                eyebrow.uppercase(),
                fontSize = 12.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White.copy(alpha = 0.75f),
                letterSpacing = 1.sp
            )
            Text(headline, fontSize = 28.sp, fontWeight = FontWeight.Bold, color = Color.White)
            Text(body, fontSize = 14.sp, color = Color.White.copy(alpha = 0.78f), lineHeight = 20.sp)
        }
    }
}

@Composable
fun AuthInputCard(title: String, subtitle: String, content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(CardBackground, RoundedCornerShape(30.dp))
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp)
    ) {
        Text(title, fontSize = 18.sp, fontWeight = FontWeight.SemiBold, color = TextPrimary)
        Text(subtitle, fontSize = 13.sp, color = TextSecondary, lineHeight = 18.sp)
        content()
    }
}

@Composable
fun AuthNoteCard(title: String, body: String) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(Surface.copy(alpha = 0.6f), RoundedCornerShape(24.dp))
            .padding(18.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Box(
            modifier = Modifier
                .size(34.dp)
                .background(Surface, CircleShape),
            contentAlignment = Alignment.Center
        ) {
            Icon(Icons.Default.Info, contentDescription = null, tint = authPink, modifier = Modifier.size(16.dp))
        }
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(title, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = TextPrimary)
            Text(body, fontSize = 13.sp, color = TextSecondary, lineHeight = 18.sp)
        }
    }
}

@Composable
fun AuthErrorRow(message: String) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(Icons.Default.Warning, contentDescription = null, tint = Nope, modifier = Modifier.size(14.dp))
        Text(message, fontSize = 13.sp, fontWeight = FontWeight.Medium, color = Nope)
    }
}

@Composable
fun AuthRestoreCard(scheduledAt: String) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(authPink.copy(alpha = 0.1f), RoundedCornerShape(18.dp))
            .border(1.dp, authPink.copy(alpha = 0.22f), RoundedCornerShape(18.dp))
            .padding(16.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Box(
            modifier = Modifier
                .size(34.dp)
                .background(Surface, CircleShape),
            contentAlignment = Alignment.Center
        ) {
            Icon(Icons.Default.Restore, contentDescription = null, tint = authPink, modifier = Modifier.size(18.dp))
        }
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text("Account deletion is pending", fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = TextPrimary)
            Text(
                "Restore this account before ${formatScheduledDeletion(scheduledAt)} to keep your profile and chats.",
                fontSize = 13.sp,
                fontWeight = FontWeight.Medium,
                color = TextSecondary,
                lineHeight = 18.sp
            )
        }
    }
}

@Composable
fun AuthContinueButton(label: String, enabled: Boolean, isLoading: Boolean, onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .background(Background)
            .padding(horizontal = 20.dp)
            .padding(top = 12.dp, bottom = 16.dp)
    ) {
        Button(
            onClick = onClick,
            enabled = enabled && !isLoading,
            modifier = Modifier.fillMaxWidth().height(52.dp),
            shape = RoundedCornerShape(22.dp),
            colors = ButtonDefaults.buttonColors(
                containerColor = Color.Transparent,
                disabledContainerColor = Color.Transparent
            ),
            contentPadding = PaddingValues(0.dp)
        ) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(
                        if (enabled && !isLoading) authGradient
                        else Brush.linearGradient(listOf(Surface, Surface)),
                        RoundedCornerShape(22.dp)
                    ),
                contentAlignment = Alignment.Center
            ) {
                if (isLoading) {
                    CircularProgressIndicator(color = Color.White, strokeWidth = 2.dp, modifier = Modifier.size(22.dp))
                } else {
                    Text(label, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = Color.White)
                }
            }
        }
    }
}

@Composable
fun AuthProgressPills(
    total: Int,
    activeUpTo: Int,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        repeat(total) { index ->
            Box(
                modifier = Modifier
                    .weight(1f)
                    .height(4.dp)
                    .background(
                        if (index < activeUpTo) authPink else SurfaceVariant,
                        RoundedCornerShape(2.dp)
                    )
            )
        }
    }
}

private fun formatScheduledDeletion(raw: String): String {
    val instant = runCatching { Instant.parse(raw) }.getOrNull()
        ?: return raw
    return DateTimeFormatter.ofPattern("MMM d, h:mm a")
        .withZone(ZoneId.systemDefault())
        .format(instant)
}
