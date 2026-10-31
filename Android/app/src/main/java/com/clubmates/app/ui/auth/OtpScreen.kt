package com.clubmates.app.ui.auth

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Numbers
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.clubmates.app.ui.theme.*

@Composable
fun OtpScreen(
    phone: String,
    intent: AuthIntent,
    viewModel: AuthViewModel,
    onVerified: () -> Unit,
    onBack: () -> Unit = {}
) {
    val uiState by viewModel.uiState.collectAsState()
    var otp by remember { mutableStateOf("") }
    val focusRequester = remember { FocusRequester() }
    val keyboardController = LocalSoftwareKeyboardController.current
    val pillCount = if (intent == AuthIntent.CreateAccount) 4 else 2

    LaunchedEffect(uiState.isAuthenticated, uiState.needsSelfie, uiState.needsProfile) {
        if (uiState.isAuthenticated || uiState.needsSelfie || uiState.needsProfile) onVerified()
    }
    LaunchedEffect(Unit) { focusRequester.requestFocus() }
    // Dismiss keyboard as soon as all 6 digits are entered
    LaunchedEffect(otp) {
        if (otp.length == 6) keyboardController?.hide()
    }

    Column(modifier = Modifier.fillMaxSize().background(Background).imePadding()) {
        // Shared header — back navigates to phone step
        AuthHeader(
            title = "ClubMates",
            subtitle = "Verification",
            pillCount = pillCount,
            activeUpTo = 2,
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
            // Hero card — "One More Step"
            AuthHeroCard(
                eyebrow = "One More Step",
                headline = "Enter your verification code.",
                body = "Type the 6-digit SMS code to continue."
            )

            // Input card
            AuthInputCard(
                title = "Verification Code",
                subtitle = "Enter the 6-digit code to continue with $phone."
            ) {
                AuthNumberFieldContainer {
                    Icon(Icons.Default.Numbers, contentDescription = null, tint = authPink, modifier = Modifier.size(20.dp))
                    Box(modifier = Modifier.width(1.dp).height(28.dp).background(Surface))
                    BasicTextField(
                        value = otp,
                        onValueChange = { if (it.length <= 6 && it.all { c -> c.isDigit() }) otp = it },
                        modifier = Modifier
                            .weight(1f)
                            .focusRequester(focusRequester),
                        keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(
                            keyboardType = KeyboardType.NumberPassword,
                            imeAction = androidx.compose.ui.text.input.ImeAction.Done
                        ),
                        singleLine = true,
                        textStyle = TextStyle(
                            fontSize = 20.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = TextPrimary
                        ),
                        cursorBrush = SolidColor(authPink),
                        decorationBox = { innerTextField ->
                            Box(contentAlignment = Alignment.CenterStart) {
                                if (otp.isBlank()) {
                                    Text(
                                        "000000",
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

                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.Top) {
                    Icon(Icons.Default.Info, contentDescription = null, tint = TextSecondary, modifier = Modifier.size(14.dp))
                    Text(
                        "We sent a 6-digit SMS code to $phone.",
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Medium,
                        color = TextSecondary,
                        lineHeight = 18.sp
                    )
                }

                uiState.error?.let { err ->
                    AuthErrorRow(err)
                }
            }

            // Build note card
            AuthNoteCard(
                title = "SMS Verification",
                body = "Codes usually arrive within a few seconds. If yours does not arrive, go back and request a new one."
            )
        }

        // Verify button pinned to bottom
        AuthContinueButton(
            label = "Verify And Continue",
            enabled = otp.length == 6 && !uiState.isLoading,
            isLoading = uiState.isLoading,
            onClick = { keyboardController?.hide(); viewModel.verifyOtp(phone, otp) }
        )
    }
}
