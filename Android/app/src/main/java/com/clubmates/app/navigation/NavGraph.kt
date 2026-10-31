package com.clubmates.app.navigation

import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.runtime.*
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.Modifier
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.clubmates.app.debug.EngineeringMenuScreen
import com.clubmates.app.ui.profile.HelpSupportScreen
import com.clubmates.app.ui.profile.NotificationSettingsScreen
import com.clubmates.app.ui.profile.PreferencesScreen
import com.clubmates.app.ui.profile.PrivacyScreen
import com.clubmates.app.ui.auth.AuthIntent
import com.clubmates.app.ui.auth.AuthViewModel
import com.clubmates.app.ui.auth.OtpScreen
import com.clubmates.app.ui.auth.PhoneInputScreen
import com.clubmates.app.ui.auth.SelfieVerificationMode
import com.clubmates.app.ui.auth.SelfieVerificationScreen
import com.clubmates.app.ui.auth.WelcomeScreen
import com.clubmates.app.ui.main.MainTabScreen
import com.clubmates.app.ui.profile.CreateProfileScreen

sealed class Screen(val route: String) {
    object Welcome : Screen("welcome")
    object PhoneInput : Screen("phone_input/{intent}") {
        fun createRoute(intent: AuthIntent) = "phone_input/${intent.name}"
    }
    object Otp : Screen("otp/{phone}/{intent}") {
        fun createRoute(phone: String, intent: AuthIntent) = "otp/$phone/${intent.name}"
    }
    object SelfieVerification : Screen("selfie_verification/{mode}") {
        fun createRoute(mode: SelfieVerificationMode) = "selfie_verification/${mode.name}"
    }
    object CreateProfile : Screen("create_profile")
    object Main : Screen("main")
    object EngineeringMenu : Screen("engineering_menu")
    object Preferences : Screen("preferences")
    object NotificationSettings : Screen("notification_settings")
    object HelpSupport : Screen("help_support")
    object Privacy : Screen("privacy")
}

@Composable
fun ClubMatesNavGraph() {
    val navController = rememberNavController()
    val authViewModel: AuthViewModel = hiltViewModel()
    val authState by authViewModel.uiState.collectAsState()

    NavHost(
        navController = navController,
        startDestination = Screen.Welcome.route,
        // safeDrawing covers status bar + navigation bar + display cutouts on ALL Android versions.
        // Applied once here so every screen inherits it automatically — no per-screen padding needed.
        modifier = Modifier.windowInsetsPadding(WindowInsets.safeDrawing)
    ) {

        composable(Screen.Welcome.route) {
            WelcomeScreen(
                onCreateAccount = {
                    navController.navigate(Screen.PhoneInput.createRoute(AuthIntent.CreateAccount))
                },
                onLogin = {
                    navController.navigate(Screen.PhoneInput.createRoute(AuthIntent.Login))
                },
                isLoggedIn = authState.isAuthenticated && !authState.needsProfile,
                onAlreadyLoggedIn = {
                    navController.navigate(Screen.Main.route) {
                        popUpTo(Screen.Welcome.route) { inclusive = true }
                    }
                }
            )
        }

        composable(Screen.PhoneInput.route) { backStackEntry ->
            val intentName = backStackEntry.arguments?.getString("intent") ?: AuthIntent.Login.name
            val intent = AuthIntent.valueOf(intentName)
            PhoneInputScreen(
                intent = intent,
                viewModel = authViewModel,
                onOtpSent = { phone ->
                    navController.navigate(Screen.Otp.createRoute(phone, intent))
                },
                onBack = { navController.popBackStack() }
            )
        }

        composable(Screen.Otp.route) { backStackEntry ->
            val phone = backStackEntry.arguments?.getString("phone") ?: ""
            val intentName = backStackEntry.arguments?.getString("intent") ?: AuthIntent.Login.name
            val intent = AuthIntent.valueOf(intentName)
            OtpScreen(
                phone = phone,
                intent = intent,
                viewModel = authViewModel,
                onBack = { navController.popBackStack() },
                onVerified = {
                    when {
                        // New user — go through selfie then profile before entering the app
                        authState.needsSelfie -> {
                            navController.navigate(Screen.SelfieVerification.createRoute(SelfieVerificationMode.Onboarding)) {
                                popUpTo(Screen.Welcome.route) { inclusive = true }
                            }
                        }
                        // Incomplete profile (existing user who never finished)
                        authState.needsProfile -> {
                            navController.navigate(Screen.CreateProfile.route) {
                                popUpTo(Screen.Welcome.route) { inclusive = true }
                            }
                        }
                        // Fully authenticated returning user
                        else -> {
                            navController.navigate(Screen.Main.route) {
                                popUpTo(Screen.Welcome.route) { inclusive = true }
                            }
                        }
                    }
                }
            )
        }

        composable(Screen.SelfieVerification.route) { backStackEntry ->
            val modeName = backStackEntry.arguments?.getString("mode") ?: SelfieVerificationMode.Onboarding.name
            val mode = runCatching { SelfieVerificationMode.valueOf(modeName) }
                .getOrDefault(SelfieVerificationMode.Onboarding)
            SelfieVerificationScreen(
                mode = mode,
                onVerified = { jpegBytes ->
                    authViewModel.completeSelfieVerification(jpegBytes)
                    if (mode == SelfieVerificationMode.Profile) {
                        navController.popBackStack()
                    } else {
                        navController.navigate(Screen.CreateProfile.route) {
                            popUpTo(Screen.SelfieVerification.route) { inclusive = true }
                        }
                    }
                },
                onSkip = {
                    if (mode == SelfieVerificationMode.Profile) {
                        navController.popBackStack()
                    } else {
                        authViewModel.skipSelfieVerification()
                        navController.navigate(Screen.CreateProfile.route) {
                            popUpTo(Screen.SelfieVerification.route) { inclusive = true }
                        }
                    }
                },
                onBack = { navController.popBackStack() }
            )
        }

        composable(Screen.CreateProfile.route) {
            // 3-step onboarding — draft shared via AuthViewModel onboardingStep state
            val onboardingStep by authViewModel.uiState.collectAsState()
            when (onboardingStep.onboardingStep) {
                com.clubmates.app.ui.auth.OnboardingStep.BASICS -> com.clubmates.app.ui.profile.OnboardingBasicsScreen(
                    viewModel = authViewModel,
                    onNext = { authViewModel.advanceOnboardingStep() }
                )
                com.clubmates.app.ui.auth.OnboardingStep.VIBE -> com.clubmates.app.ui.profile.OnboardingVibeScreen(
                    viewModel = authViewModel,
                    onBack = { authViewModel.rewindOnboardingStep() },
                    onNext = { authViewModel.advanceOnboardingStep() }
                )
                com.clubmates.app.ui.auth.OnboardingStep.PREFERENCES -> com.clubmates.app.ui.profile.OnboardingPreferencesScreen(
                    viewModel = authViewModel,
                    onBack = { authViewModel.rewindOnboardingStep() },
                    onFinish = {
                        navController.navigate(Screen.Main.route) {
                            popUpTo(Screen.CreateProfile.route) { inclusive = true }
                        }
                    }
                )
            }
        }

        composable(Screen.Main.route) {
            MainTabScreen(
                onLogout = {
                    authViewModel.logout()
                    navController.navigate(Screen.Welcome.route) {
                        popUpTo(navController.graph.findStartDestination().id) { inclusive = true }
                    }
                },
                onEngineeringMenu = { navController.navigate(Screen.EngineeringMenu.route) },
                onPreferences = { navController.navigate(Screen.Preferences.route) },
                onNotifications = { navController.navigate(Screen.NotificationSettings.route) },
                onPrivacy = { navController.navigate(Screen.Privacy.route) },
                onHelpSupport = { navController.navigate(Screen.HelpSupport.route) },
                onVerify = {
                    navController.navigate(Screen.SelfieVerification.createRoute(SelfieVerificationMode.Profile))
                }
            )
        }

        composable(Screen.EngineeringMenu.route) {
            EngineeringMenuScreen(onBack = { navController.popBackStack() })
        }

        composable(Screen.Preferences.route) {
            PreferencesScreen(onBack = { navController.popBackStack() })
        }

        composable(Screen.NotificationSettings.route) {
            NotificationSettingsScreen(onBack = { navController.popBackStack() })
        }

        composable(Screen.HelpSupport.route) {
            HelpSupportScreen(onBack = { navController.popBackStack() })
        }

        composable(Screen.Privacy.route) {
            PrivacyScreen(onBack = { navController.popBackStack() })
        }
    }
}
