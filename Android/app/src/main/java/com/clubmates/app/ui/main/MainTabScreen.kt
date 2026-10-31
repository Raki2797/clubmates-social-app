package com.clubmates.app.ui.main

import androidx.compose.animation.*
import androidx.compose.animation.core.*
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Chat
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.clubmates.app.domain.model.Match
import com.clubmates.app.ui.discover.DiscoverScreen
import com.clubmates.app.ui.matches.MatchesDisplayMode
import com.clubmates.app.ui.matches.MatchesScreen
import com.clubmates.app.ui.matches.MatchesViewModel
import com.clubmates.app.ui.profile.ProfileScreen
import com.clubmates.app.ui.theme.*
import kotlinx.coroutines.*
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.sin

// ── Tab bar scroll state ──────────────────────────────────────────────────────

class TabBarController(private val scope: CoroutineScope) {
    var isCollapsed by mutableStateOf(false)
        private set
    var isHidden by mutableStateOf(false)

    private var cumulativeOffset = 0f
    private val collapseThreshold = 200f
    private var idleJob: Job? = null

    val nestedScrollConnection = object : NestedScrollConnection {
        override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset {
            update(-available.y) // positive value = user scrolling down
            return Offset.Zero
        }
    }

    private fun update(delta: Float) {
        cumulativeOffset = (cumulativeOffset + delta).coerceAtLeast(0f)

        // Scrolling down fast enough past threshold → collapse
        if (delta > 12f && cumulativeOffset > collapseThreshold && !isCollapsed) {
            idleJob?.cancel()
            collapse()
            return
        }

        // Back near top while not scrolling down → expand
        if (cumulativeOffset < 40f && isCollapsed && delta <= 0f) {
            idleJob?.cancel()
            expand()
        }

        // Any movement resets idle timer
        if (abs(delta) > 1f) {
            scheduleIdleCollapse(2500)
        }
    }

    fun forceExpand() {
        expand()
        scheduleIdleCollapse(2500)
    }

    fun signalActivity() {
        idleJob?.cancel()
        cumulativeOffset = 0f
        if (isCollapsed) expand()
        scheduleIdleCollapse(2500)
    }

    fun startInitialTimer() {
        scheduleIdleCollapse(2500)
    }

    private fun collapse() {
        if (!isCollapsed) isCollapsed = true
    }

    private fun expand() {
        if (isCollapsed) isCollapsed = false
    }

    private fun scheduleIdleCollapse(delayMs: Long) {
        idleJob?.cancel()
        idleJob = scope.launch {
            delay(delayMs)
            collapse()
        }
    }
}

val LocalTabBarController = compositionLocalOf<TabBarController?> { null }

// ── Tab definition ────────────────────────────────────────────────────────────

private sealed class Tab(val route: String, val label: String, val icon: ImageVector) {
    object Discover : Tab("tab_discover", "Venue", Icons.Default.Home)
    object Matches  : Tab("tab_matches",  "Matches", Icons.Default.Favorite)
    object Chats    : Tab("tab_chats",    "Chat",    Icons.AutoMirrored.Filled.Chat)
    object Profile  : Tab("tab_profile",  "Profile", Icons.Default.Person)
}

private val allTabs = listOf(Tab.Discover, Tab.Matches, Tab.Chats, Tab.Profile)

// ── Main screen ───────────────────────────────────────────────────────────────

@Composable
fun MainTabScreen(
    onLogout: () -> Unit,
    onEngineeringMenu: () -> Unit,
    onPreferences: () -> Unit = {},
    onNotifications: () -> Unit = {},
    onPrivacy: () -> Unit = {},
    onHelpSupport: () -> Unit = {},
    onVerify: () -> Unit = {}
) {
    val scope = rememberCoroutineScope()
    val tabBarController = remember { TabBarController(scope) }
    val navController = rememberNavController()
    val matchesViewModel: MatchesViewModel = hiltViewModel()
    val matchesState by matchesViewModel.matchesState.collectAsState()
    val chatState by matchesViewModel.chatState.collectAsState()
    val backStackEntry by navController.currentBackStackEntryAsState()
    val currentRoute = backStackEntry?.destination?.route ?: Tab.Discover.route

    val newMatchesCount = remember(matchesState.matches) { matchesState.matches.count { it.isNew } }
    val unreadChatCount = remember(matchesState.matches) { matchesState.matches.sumOf { it.unreadCount } }
    val showTabBar = chatState.match == null && !tabBarController.isHidden

    var squishRoute by remember { mutableStateOf<String?>(null) }

    val screenWidthDp = LocalConfiguration.current.screenWidthDp.dp

    fun navigateTo(route: String) {
        navController.navigate(route) {
            popUpTo(Tab.Discover.route) { saveState = true }
            launchSingleTop = true
            restoreState = true
        }
    }

    fun openMatchChat(match: Match) {
        matchesViewModel.addMatch(match)
        navigateTo(Tab.Chats.route)
        matchesViewModel.openChat(match)
    }

    LaunchedEffect(Unit) {
        tabBarController.startInitialTimer()
    }

    CompositionLocalProvider(LocalTabBarController provides tabBarController) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Background)
        ) {
            NavHost(
                navController = navController,
                startDestination = Tab.Discover.route,
                modifier = Modifier
                    .fillMaxSize()
                    .nestedScroll(tabBarController.nestedScrollConnection)
            ) {
                composable(Tab.Discover.route) {
                    DiscoverScreen(onOpenMatchChat = ::openMatchChat)
                }
                composable(Tab.Matches.route) {
                    MatchesScreen(viewModel = matchesViewModel, displayMode = MatchesDisplayMode.MATCHES)
                }
                composable(Tab.Chats.route) {
                    MatchesScreen(viewModel = matchesViewModel, displayMode = MatchesDisplayMode.CHATS)
                }
                composable(Tab.Profile.route) {
                    ProfileScreen(
                        onLogout = onLogout,
                        onEngineeringMenu = onEngineeringMenu,
                        onPreferences = onPreferences,
                        onNotifications = onNotifications,
                        onPrivacy = onPrivacy,
                        onHelpSupport = onHelpSupport,
                        onVerify = onVerify
                    )
                }
            }

            // App-wide incoming like/match banner — shown from ANY tab (mirrors iOS window-level overlay)
            val bannerState by matchesViewModel.matchesState.collectAsState()
            bannerState.incomingLikeBanner?.let { banner ->
                Box(
                    modifier = Modifier
                        .align(Alignment.TopCenter)
                        .fillMaxWidth()
                        .padding(horizontal = 20.dp)
                        .padding(top = 8.dp)
                ) {
                    AppWideBanner(
                        banner = banner,
                        onDismiss = { matchesViewModel.dismissIncomingLikeBanner() }
                    )
                }
            }

            // Floating tab bar overlay
            AnimatedVisibility(
                visible = showTabBar,
                enter = slideInVertically { it } + fadeIn(),
                exit = slideOutVertically { it } + fadeOut(),
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(bottom = 28.dp)
                    .width(screenWidthDp * 0.70f)
            ) {
                FloatingTabBar(
                    tabs = allTabs,
                    currentRoute = currentRoute,
                    isCollapsed = tabBarController.isCollapsed,
                    squishRoute = squishRoute,
                    newMatchesCount = newMatchesCount,
                    unreadChatCount = unreadChatCount,
                    onTabSelected = { tab ->
                        if (currentRoute == tab.route) {
                            squishRoute = tab.route
                            scope.launch { delay(220); squishRoute = null }
                            tabBarController.signalActivity()
                        } else {
                            tabBarController.signalActivity()
                            navigateTo(tab.route)
                        }
                    },
                    onExpandPill = { tabBarController.forceExpand() }
                )
            }
        }
    }
}

// ── Floating tab bar ──────────────────────────────────────────────────────────

@Composable
private fun FloatingTabBar(
    tabs: List<Tab>,
    currentRoute: String,
    isCollapsed: Boolean,
    squishRoute: String?,
    newMatchesCount: Int,
    unreadChatCount: Int,
    onTabSelected: (Tab) -> Unit,
    onExpandPill: () -> Unit
) {
    AnimatedContent(
        targetState = isCollapsed,
        transitionSpec = {
            (scaleIn(spring(dampingRatio = 0.75f), initialScale = 0.82f) + fadeIn()) togetherWith
            (scaleOut(targetScale = 0.82f) + fadeOut())
        },
        label = "tab_bar_mode"
    ) { collapsed ->
        if (collapsed) {
            Box(modifier = Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                CollapsedPill(
                    activeTab = tabs.find { it.route == currentRoute } ?: tabs[0],
                    onExpand = onExpandPill
                )
            }
        } else {
            ExpandedTabBar(
                tabs = tabs,
                currentRoute = currentRoute,
                squishRoute = squishRoute,
                newMatchesCount = newMatchesCount,
                unreadChatCount = unreadChatCount,
                onTabSelected = onTabSelected
            )
        }
    }
}

// ── Expanded oval bar ─────────────────────────────────────────────────────────

@Composable
private fun ExpandedTabBar(
    tabs: List<Tab>,
    currentRoute: String,
    squishRoute: String?,
    newMatchesCount: Int,
    unreadChatCount: Int,
    onTabSelected: (Tab) -> Unit
) {
    val pink   = Color(0xFFFF6B9D)
    val purple = Color(0xFFC44EFF)

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(
                Color(0xFF14141E).copy(alpha = 0.96f),
                RoundedCornerShape(50)
            )
            .border(
                width = 1.dp,
                brush = Brush.linearGradient(
                    listOf(
                        Color.White.copy(alpha = 0.14f),
                        pink.copy(alpha = 0.20f),
                        Color.White.copy(alpha = 0.06f),
                        purple.copy(alpha = 0.14f)
                    )
                ),
                shape = RoundedCornerShape(50)
            )
            .padding(horizontal = 6.dp, vertical = 3.dp),
        horizontalArrangement = Arrangement.SpaceEvenly
    ) {
        tabs.forEach { tab ->
            val badge = when (tab) {
                is Tab.Matches -> newMatchesCount
                is Tab.Chats   -> unreadChatCount
                else           -> 0
            }
            TabPillItem(
                tab = tab,
                isActive = currentRoute == tab.route,
                isSquishy = squishRoute == tab.route,
                badge = badge,
                onSelected = { onTabSelected(tab) },
                modifier = Modifier.weight(1f)
            )
        }
    }
}

@Composable
private fun TabPillItem(
    tab: Tab,
    isActive: Boolean,
    isSquishy: Boolean,
    badge: Int,
    onSelected: () -> Unit,
    modifier: Modifier = Modifier
) {
    val pink = Color(0xFFFF6B9D)

    val squishScaleX by animateFloatAsState(
        targetValue = if (isSquishy) 1.18f else 1f,
        animationSpec = spring(dampingRatio = 0.35f, stiffness = Spring.StiffnessMedium),
        label = "squish_x"
    )
    val squishScaleY by animateFloatAsState(
        targetValue = if (isSquishy) 0.72f else 1f,
        animationSpec = spring(dampingRatio = 0.35f, stiffness = Spring.StiffnessMedium),
        label = "squish_y"
    )

    Box(
        modifier = modifier
            .clickable(
                indication = null,
                interactionSource = remember { MutableInteractionSource() }
            ) { onSelected() }
            .padding(vertical = 7.dp),
        contentAlignment = Alignment.Center
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(3.dp)
        ) {
            BadgedBox(
                badge = {
                    if (badge > 0) {
                        Badge(containerColor = pink) {
                            Text(
                                if (badge > 9) "9+" else badge.toString(),
                                fontSize = 7.sp,
                                fontWeight = FontWeight.Black
                            )
                        }
                    }
                },
                modifier = Modifier.graphicsLayer { scaleX = squishScaleX; scaleY = squishScaleY }
            ) {
                Icon(
                    imageVector = tab.icon,
                    contentDescription = tab.label,
                    tint = if (isActive) pink else TextHint,
                    modifier = Modifier.size(if (isActive) 22.dp else 18.dp)
                )
            }
            Text(
                tab.label,
                fontSize = 9.sp,
                fontWeight = if (isActive) FontWeight.Bold else FontWeight.Normal,
                color = if (isActive) pink else TextHint
            )
        }
    }
}

// ── Collapsed pill ────────────────────────────────────────────────────────────

@Composable
private fun CollapsedPill(activeTab: Tab, onExpand: () -> Unit) {
    val pink   = Color(0xFFFF6B9D)
    val purple = Color(0xFFC44EFF)

    val infiniteTransition = rememberInfiniteTransition(label = "pill_spin")
    val spinAngle by infiniteTransition.animateFloat(
        initialValue = 0f,
        targetValue = 360f,
        animationSpec = infiniteRepeatable(tween(3000, easing = LinearEasing)),
        label = "spin"
    )

    Box(
        modifier = Modifier
            .size(54.dp)
            .drawBehind {
                val strokeWidth = 1.5.dp.toPx()
                val radius = size.minDimension / 2f - strokeWidth / 2f
                rotate(spinAngle, pivot = Offset(size.width / 2f, size.height / 2f)) {
                    drawCircle(
                        brush = Brush.sweepGradient(
                            listOf(pink.copy(alpha = 0.9f), purple.copy(alpha = 0.6f), pink.copy(alpha = 0.1f), pink.copy(alpha = 0.9f)),
                            center = Offset(size.width / 2f, size.height / 2f)
                        ),
                        radius = radius,
                        style = Stroke(strokeWidth)
                    )
                }
            }
            .background(Color(0xFF14141E).copy(alpha = 0.96f), CircleShape)
            .clickable(
                indication = null,
                interactionSource = remember { MutableInteractionSource() }
            ) { onExpand() },
        contentAlignment = Alignment.Center
    ) {
        Icon(
            imageVector = activeTab.icon,
            contentDescription = activeTab.label,
            tint = pink,
            modifier = Modifier.size(20.dp)
        )

        // 3 static orbit dots
        listOf(0.0, 120.0, 240.0).forEach { angleDeg ->
            val rad = Math.toRadians(angleDeg)
            val orbitR = 20.dp
            Box(
                modifier = Modifier
                    .size(3.dp)
                    .offset(
                        x = (orbitR.value * cos(rad)).dp,
                        y = (orbitR.value * sin(rad)).dp
                    )
                    .background(pink.copy(alpha = 0.65f), CircleShape)
            )
        }
    }
}

@Composable
private fun AppWideBanner(
    banner: com.clubmates.app.ui.matches.IncomingLikeBanner,
    onDismiss: () -> Unit
) {
    val pink = Color(0xFFFF6B9D)
    val gold = Color(0xFFFFB800)
    androidx.compose.animation.AnimatedVisibility(
        visible = true,
        enter = androidx.compose.animation.slideInVertically { -it } + androidx.compose.animation.fadeIn(),
        exit = androidx.compose.animation.slideOutVertically { -it } + androidx.compose.animation.fadeOut()
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .background(com.clubmates.app.ui.theme.CardBackground, androidx.compose.foundation.shape.RoundedCornerShape(14.dp))
                .border(1.dp, com.clubmates.app.ui.theme.SurfaceVariant, androidx.compose.foundation.shape.RoundedCornerShape(14.dp))
                .clickable { onDismiss() }
                .padding(horizontal = 12.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Box(
                modifier = Modifier
                    .size(28.dp)
                    .background(com.clubmates.app.ui.theme.SurfaceVariant, CircleShape),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    Icons.Default.Favorite,
                    contentDescription = null,
                    tint = if (banner.isSuperLike) gold else pink,
                    modifier = Modifier.size(14.dp)
                )
            }
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(
                    if (banner.isSuperLike) "New super like" else "New like",
                    fontSize = 12.sp, fontWeight = FontWeight.SemiBold,
                    color = com.clubmates.app.ui.theme.TextPrimary
                )
                Text(
                    "${banner.name} liked your profile",
                    fontSize = 12.sp, color = com.clubmates.app.ui.theme.TextSecondary, maxLines = 1
                )
            }
        }
    }
}
