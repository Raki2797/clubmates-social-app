package com.clubmates.app.ui.profile

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.clubmates.app.ui.theme.*

private val interestPink = Color(0xFFFF6B9D)
private val interestPurple = Color(0xFFC44EFF)
private val interestGradient = Brush.linearGradient(listOf(interestPink, interestPurple))

private val INTEREST_CATEGORIES = listOf(
    "Creative" to listOf("Photography", "Painting", "Drawing", "Ceramics", "Knitting", "Writing", "Illustration", "Design"),
    "Music" to listOf("Vinyl", "Jazz", "Indie", "Concerts", "Karaoke", "Guitar", "Piano", "Hip-hop"),
    "Food & Drink" to listOf("Cooking", "Baking", "Coffee", "Wine", "Brunch", "Sushi", "Farmers Markets", "Cocktails"),
    "Active" to listOf("Yoga", "Running", "Hiking", "Surfing", "Climbing", "Tennis", "Cycling", "Swimming"),
    "Mind" to listOf("Books", "Podcasts", "Film", "Travel", "Languages", "Chess", "History", "Science"),
    "Social" to listOf("Stand-up", "Trivia", "Board Games", "Thrifting", "Art Galleries", "Darts", "Karaoke"),
    "Outdoors" to listOf("Camping", "Dogs", "Gardening", "Stargazing", "Beach", "Road Trips", "Mountains", "Sailing"),
    "Tech & Gaming" to listOf("Code", "Gaming", "Anime", "Crypto", "AI", "Robotics", "VR", "Podcasts"),
)

private const val MAX_INTERESTS = 8

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun InterestPickerSheet(
    selected: Set<String>,
    onDismiss: () -> Unit,
    onConfirm: (Set<String>) -> Unit
) {
    var current by remember { mutableStateOf(selected) }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = Background,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        dragHandle = null
    ) {
        Column(modifier = Modifier.fillMaxSize()) {
            // Nav bar: title left, Done right
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(CardBackground)
                    .padding(horizontal = 20.dp, vertical = 14.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    "Interests",
                    fontSize = 18.sp,
                    fontWeight = FontWeight.Bold,
                    color = TextPrimary
                )
                TextButton(onClick = { onConfirm(current) }) {
                    Text(
                        "Done",
                        fontSize = 16.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = interestPink
                    )
                }
            }
            HorizontalDivider(color = Surface)

            Column(
                modifier = Modifier
                    .weight(1f)
                    .verticalScroll(rememberScrollState())
                    .padding(top = 16.dp, bottom = 40.dp),
                verticalArrangement = Arrangement.spacedBy(28.dp)
            ) {
                // Selection count pill
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 20.dp),
                    contentAlignment = Alignment.CenterEnd
                ) {
                    Text(
                        "${current.size}/$MAX_INTERESTS selected",
                        fontSize = 13.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = if (current.size >= MAX_INTERESTS) interestPink else TextSecondary,
                        modifier = Modifier
                            .background(Surface, RoundedCornerShape(50))
                            .padding(horizontal = 14.dp, vertical = 7.dp)
                    )
                }

                // Category sections
                INTEREST_CATEGORIES.forEach { (category, items) ->
                    Column(
                        modifier = Modifier.padding(horizontal = 20.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        Text(
                            category.uppercase(),
                            fontSize = 13.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = TextSecondary,
                            letterSpacing = 0.8.sp
                        )
                        FlowRow(
                            horizontalArrangement = Arrangement.spacedBy(10.dp),
                            verticalArrangement = Arrangement.spacedBy(10.dp)
                        ) {
                            items.forEach { item ->
                                InterestChip(
                                    label = item,
                                    isSelected = item in current,
                                    isDisabled = item !in current && current.size >= MAX_INTERESTS,
                                    onClick = {
                                        current = if (item in current) {
                                            current - item
                                        } else if (current.size < MAX_INTERESTS) {
                                            current + item
                                        } else current
                                    }
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun InterestChip(
    label: String,
    isSelected: Boolean,
    isDisabled: Boolean,
    onClick: () -> Unit
) {
    val scale = if (isSelected) 1.03f else 1f
    Box(
        modifier = Modifier
            .scale(scale)
            .then(
                if (isSelected) {
                    Modifier.background(interestGradient, RoundedCornerShape(50))
                } else {
                    Modifier
                        .background(
                            Surface.copy(alpha = if (isDisabled) 0.5f else 1f),
                            RoundedCornerShape(50)
                        )
                        .border(1.dp, TextHint.copy(alpha = 0.2f), RoundedCornerShape(50))
                }
            )
            .clickable(enabled = !isDisabled, onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 9.dp)
    ) {
        Text(
            label,
            fontSize = 14.sp,
            fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Medium,
            color = when {
                isSelected -> Color.White
                isDisabled -> TextHint
                else -> TextPrimary
            }
        )
    }
}
