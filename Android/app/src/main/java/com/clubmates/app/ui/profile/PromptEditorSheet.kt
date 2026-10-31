package com.clubmates.app.ui.profile

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.clubmates.app.domain.model.UserProfile
import com.clubmates.app.ui.theme.*

private val promptPink = Color(0xFFFF6B9D)
private val promptPurple = Color(0xFFC44EFF)
private val promptGradient = Brush.linearGradient(listOf(promptPink, promptPurple))

val PROMPT_QUESTIONS = listOf(
    "The way to my heart is...",
    "I'm looking for...",
    "My love language is...",
    "A fact about me that surprises people...",
    "My ideal Sunday...",
    "I'll know it's a match if...",
    "I get too excited about...",
    "My biggest green flag...",
    "Change my mind that...",
    "Two truths and a lie...",
    "My most irrational fear...",
    "I guarantee we'll get along if...",
    "The key to my heart...",
    "Unusual skill I have...",
    "Weirdly, I'm good at...",
    "First round is on me if...",
    "My go-to karaoke song is...",
    "I'm convinced that...",
    "Hot take: ...",
    "My simple pleasures are...",
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PromptEditorSheet(
    prompt: UserProfile.Prompt,
    onDismiss: () -> Unit,
    onSave: (UserProfile.Prompt) -> Unit
) {
    var question by remember { mutableStateOf(prompt.question.ifBlank { PROMPT_QUESTIONS.first() }) }
    var answer by remember { mutableStateOf(prompt.answer) }
    var showQuestionPicker by remember { mutableStateOf(false) }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = Background,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        dragHandle = null
    ) {
        Column(modifier = Modifier.fillMaxSize()) {
            // Nav bar
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(CardBackground)
                    .padding(horizontal = 20.dp, vertical = 14.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                TextButton(onClick = onDismiss) {
                    Text("Cancel", fontSize = 16.sp, color = TextSecondary)
                }
                Text("Edit Prompt", fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = TextPrimary)
                TextButton(
                    onClick = { onSave(UserProfile.Prompt(question = question, answer = answer)); onDismiss() },
                    enabled = answer.trim().isNotEmpty()
                ) {
                    Text(
                        "Done",
                        fontSize = 16.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = if (answer.trim().isNotEmpty()) promptPink else TextHint
                    )
                }
            }
            HorizontalDivider(color = Surface)

            Column(
                modifier = Modifier
                    .weight(1f)
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 20.dp)
                    .padding(top = 24.dp, bottom = 32.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp)
            ) {
                // Question selector — pink uppercase button with chevron
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(CardBackground, RoundedCornerShape(16.dp))
                        .border(1.dp, promptPink.copy(alpha = 0.25f), RoundedCornerShape(16.dp))
                        .clickable { showQuestionPicker = true }
                        .padding(18.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        question.uppercase(),
                        fontSize = 14.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = promptPink,
                        letterSpacing = 0.5.sp,
                        modifier = Modifier.weight(1f)
                    )
                    Icon(
                        Icons.AutoMirrored.Filled.KeyboardArrowRight,
                        contentDescription = "Choose question",
                        tint = TextSecondary,
                        modifier = Modifier.size(18.dp)
                    )
                }

                // Answer text field
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(min = 130.dp, max = 200.dp)
                        .background(CardBackground, RoundedCornerShape(16.dp))
                ) {
                    if (answer.isEmpty()) {
                        Text(
                            "Write your answer...",
                            fontSize = 17.sp,
                            color = TextHint,
                            modifier = Modifier.padding(18.dp)
                        )
                    }
                    OutlinedTextField(
                        value = answer,
                        onValueChange = { if (it.length <= 150) answer = it },
                        modifier = Modifier
                            .fillMaxWidth()
                            .heightIn(min = 130.dp),
                        textStyle = LocalTextStyle.current.copy(
                            fontSize = 17.sp,
                            fontWeight = FontWeight.Medium,
                            color = TextPrimary
                        ),
                        colors = OutlinedTextFieldDefaults.colors(
                            focusedBorderColor = Color.Transparent,
                            unfocusedBorderColor = Color.Transparent,
                            focusedContainerColor = Color.Transparent,
                            unfocusedContainerColor = Color.Transparent,
                            cursorColor = promptPink
                        ),
                        maxLines = 6
                    )
                }

                // Char count
                Box(modifier = Modifier.fillMaxWidth(), contentAlignment = Alignment.CenterEnd) {
                    Text(
                        "${answer.length}/150",
                        fontSize = 12.sp,
                        color = if (answer.length > 140) Nope else TextHint
                    )
                }

                // Preview card
                Column(
                    modifier = Modifier.padding(top = 14.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Text(
                        "PREVIEW",
                        fontSize = 12.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = TextHint,
                        letterSpacing = 0.8.sp
                    )
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .background(Surface, RoundedCornerShape(16.dp))
                            .border(1.dp, promptPink.copy(alpha = 0.15f), RoundedCornerShape(16.dp))
                            .padding(18.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Text(
                            question.uppercase(),
                            fontSize = 11.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = promptPink,
                            letterSpacing = 0.6.sp
                        )
                        Text(
                            answer.ifBlank { "Your answer will appear here" },
                            fontSize = 16.sp,
                            fontWeight = FontWeight.Medium,
                            color = if (answer.isBlank()) TextHint else TextPrimary
                        )
                    }
                }
            }
        }
    }

    // Question picker sheet
    if (showQuestionPicker) {
        QuestionPickerSheet(
            selected = question,
            onSelect = { question = it; showQuestionPicker = false },
            onDismiss = { showQuestionPicker = false }
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun QuestionPickerSheet(
    selected: String,
    onSelect: (String) -> Unit,
    onDismiss: () -> Unit
) {
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = Background,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = false),
        dragHandle = null
    ) {
        Column(modifier = Modifier.fillMaxHeight(0.65f)) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(CardBackground)
                    .padding(horizontal = 20.dp, vertical = 14.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text("Choose a prompt", fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = TextPrimary)
                TextButton(onClick = onDismiss) {
                    Text("Done", fontSize = 16.sp, color = promptPink, fontWeight = FontWeight.SemiBold)
                }
            }
            HorizontalDivider(color = Surface)

            LazyColumn {
                items(PROMPT_QUESTIONS) { q ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .background(CardBackground)
                            .clickable { onSelect(q) }
                            .padding(horizontal = 20.dp, vertical = 16.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            q,
                            fontSize = 15.sp,
                            color = TextPrimary,
                            modifier = Modifier.weight(1f)
                        )
                        if (q == selected) {
                            Icon(Icons.Default.Check, contentDescription = null, tint = promptPink, modifier = Modifier.size(16.dp))
                        }
                    }
                    HorizontalDivider(
                        color = Surface,
                        modifier = Modifier.padding(start = 20.dp)
                    )
                }
            }
        }
    }
}
