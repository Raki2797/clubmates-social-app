package com.clubmates.app.debug

import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.clubmates.app.BuildConfig
import com.clubmates.app.ui.theme.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EngineeringMenuScreen(onBack: () -> Unit) {
    val context = LocalContext.current

    // Local draft state — maps key → current text field value
    val drafts = remember { mutableStateMapOf<String, String>() }
    var saved by remember { mutableStateOf(false) }

    // Reload from prefs every time the screen becomes visible
    LaunchedEffect(Unit) {
        DebugOverrideStore.Keys.all.forEach { key ->
            drafts[key.key] = DebugOverrideStore.getRawString(context, key)
        }
        saved = false
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Column {
                        Text("Engineering Menu", fontWeight = FontWeight.Bold, color = TextPrimary)
                        Text("v${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})", fontSize = 12.sp, color = TextSecondary)
                    }
                },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back", tint = TextPrimary)
                    }
                },
                actions = {
                    IconButton(onClick = {
                        DebugOverrideStore.clearAll(context)
                        drafts.keys.forEach { k -> drafts[k] = "" }
                        saved = true
                    }) {
                        Icon(Icons.Default.Delete, contentDescription = "Clear all", tint = Color(0xFFFF6B6B))
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = SurfaceVariant)
            )
        },
        containerColor = Background
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            // Group keys by section prefix (text before " — ")
            val grouped = DebugOverrideStore.Keys.all.groupBy { key ->
                key.label.substringBefore(" — ").trim()
            }

            grouped.forEach { (section, keys) ->
                SectionHeader(title = section)

                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(SurfaceVariant, RoundedCornerShape(14.dp))
                        .border(1.dp, Color.White.copy(alpha = 0.07f), RoundedCornerShape(14.dp))
                        .padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(14.dp)
                ) {
                    keys.forEach { key ->
                        OverrideField(
                            context = context,
                            key = key,
                            value = drafts[key.key] ?: "",
                            onValueChange = { drafts[key.key] = it }
                        )
                    }
                }
            }

            // Save button
            Button(
                onClick = {
                    applyDrafts(context, drafts)
                    saved = true
                },
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(12.dp),
                colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFFF6B9D))
            ) {
                Text("Save Overrides", fontWeight = FontWeight.SemiBold, color = Color.White)
            }

            if (saved) {
                Text(
                    "Overrides saved — restart any active screen to pick up changes.",
                    fontSize = 12.sp,
                    color = Color(0xFF00E5A0),
                    modifier = Modifier.padding(horizontal = 4.dp)
                )
            }

            Spacer(modifier = Modifier.height(32.dp))
        }
    }
}

@Composable
private fun SectionHeader(title: String) {
    Text(
        title.uppercase(),
        fontSize = 11.sp,
        fontWeight = FontWeight.Bold,
        color = Color(0xFFFF6B9D),
        letterSpacing = 1.2.sp,
        modifier = Modifier.padding(horizontal = 4.dp)
    )
}

@Composable
private fun OverrideField(
    context: Context,
    key: DebugOverrideStore.OverrideKey<*>,
    value: String,
    onValueChange: (String) -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(
            key.label.substringAfter(" — ").trim().ifEmpty { key.label },
            fontSize = 13.sp,
            fontWeight = FontWeight.SemiBold,
            color = TextPrimary
        )
        Text(key.description, fontSize = 11.sp, color = TextSecondary)

        when (key) {
            is DebugOverrideStore.OverrideKey.BooleanKey -> {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    val checked = value.toBooleanStrictOrNull() ?: key.default
                    Switch(
                        checked = checked,
                        onCheckedChange = { onValueChange(it.toString()) },
                        colors = SwitchDefaults.colors(checkedThumbColor = Color(0xFFFF6B9D))
                    )
                    Text(if (checked) "Enabled" else "Disabled", fontSize = 13.sp, color = TextSecondary)
                }
            }
            else -> {
                val keyboardType = if (key is DebugOverrideStore.OverrideKey.DoubleKey)
                    KeyboardType.Decimal else KeyboardType.Text
                OutlinedTextField(
                    value = value,
                    onValueChange = onValueChange,
                    placeholder = { Text("Not set — using real value", fontSize = 13.sp, color = TextHint) },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = keyboardType),
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(10.dp),
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedBorderColor = Color(0xFFFF6B9D),
                        unfocusedBorderColor = Color.White.copy(alpha = 0.15f),
                        focusedTextColor = TextPrimary,
                        unfocusedTextColor = TextPrimary,
                        cursorColor = Color(0xFFFF6B9D)
                    ),
                    textStyle = androidx.compose.ui.text.TextStyle(fontSize = 14.sp)
                )
            }
        }
    }
}

private fun applyDrafts(context: Context, drafts: Map<String, String>) {
    DebugOverrideStore.Keys.all.forEach { key ->
        val raw = drafts[key.key] ?: ""
        when {
            raw.isBlank() -> DebugOverrideStore.clear(context, key)
            key is DebugOverrideStore.OverrideKey.BooleanKey -> {
                DebugOverrideStore.setBoolean(context, key, raw.toBooleanStrictOrNull() ?: key.default)
            }
            else -> DebugOverrideStore.setString(context, key, raw)
        }
    }
}
