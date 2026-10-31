package com.clubmates.app.ui.theme

import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

// Mirrors iOS AppTheme dark palette exactly
val Background = Color(0xFF0D0D0F)
val CardBackground = Color(0xFF1A1A1F)
val Surface = Color(0xFF232328)
val SurfaceVariant = Color(0xFF2C2C33)
val SurfaceElevated = Color(0xFF2C2C33)
val Primary = Color(0xFFFF6B9D)
val PrimaryVariant = Color(0xFFC44EFF)
val Secondary = Color(0xFFC44EFF)
val Accent = Color(0xFFFF6B9D)
val TextPrimary = Color(0xFFFFFFFF)
val TextSecondary = Color(0xFF9999AA)
val TextTertiary = Color(0xFF555566)
val TextHint = TextTertiary
val Like = Color(0xFF00E5A0)
val Nope = Color(0xFFFF4757)
val SuperLike = Color(0xFFFFD93D)

private val DarkColorScheme = darkColorScheme(
    primary = Primary,
    secondary = Secondary,
    tertiary = Accent,
    background = Background,
    surface = Surface,
    surfaceVariant = SurfaceVariant,
    onPrimary = Color.White,
    onSecondary = Color.White,
    onBackground = TextPrimary,
    onSurface = TextPrimary,
    onSurfaceVariant = TextSecondary,
    outline = SurfaceElevated
)

@Composable
fun ClubMatesTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = DarkColorScheme,
        typography = ClubMatesTypography,
        content = content
    )
}
