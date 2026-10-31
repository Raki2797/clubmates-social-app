import SwiftUI
import UIKit

private func overlayTrace(_ message: String) {
    #if DEBUG
    print("[OverlayTrace] \(message)")
    #endif
}

@MainActor
private final class GlobalInteractionOverlay {
    static let shared = GlobalInteractionOverlay()

    private var window: UIWindow?

    func showToast<Content: View>(_ content: Content) {
        guard let scene = activeWindowScene() else {
            overlayTrace("showToast failed: no foreground scene")
            return
        }

        let bounds = scene.coordinateSpace.bounds
        let overlayWindow = configuredWindow(for: scene)
        overlayWindow.frame = CGRect(
            x: bounds.minX,
            y: bounds.minY,
            width: bounds.width,
            height: min(160, bounds.height)
        )
        setRootView(
            AnyView(
                VStack(spacing: 0) {
                    content
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                    Spacer(minLength: 0)
                }
            ),
            on: overlayWindow
        )
        overlayTrace("toast window visible frame=\(overlayWindow.frame)")
    }

    func showFullScreen<Content: View>(_ content: Content) {
        guard let scene = activeWindowScene() else { return }

        let overlayWindow = configuredWindow(for: scene)
        overlayWindow.frame = scene.coordinateSpace.bounds
        setRootView(AnyView(content), on: overlayWindow)
    }

    func hide() {
        overlayTrace("hiding overlay")
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
    }

    private func configuredWindow(for scene: UIWindowScene) -> UIWindow {
        if let window, window.windowScene === scene {
            return window
        }

        let overlayWindow = UIWindow(windowScene: scene)
        overlayWindow.backgroundColor = .clear
        overlayWindow.windowLevel = .alert + 1
        overlayWindow.isHidden = false
        window = overlayWindow
        return overlayWindow
    }

    private func setRootView(_ view: AnyView, on window: UIWindow) {
        let host = UIHostingController(rootView: view)
        host.view.backgroundColor = .clear
        window.rootViewController = host
        window.isHidden = false
    }

    private func activeWindowScene() -> UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
    }
}

// MARK: - Scroll collapse environment

class TabBarScrollState: ObservableObject {
    @Published var isCollapsed = false
    @Published var isHidden = false

    private var lastOffset: CGFloat = 0
    private var idleTimer: DispatchWorkItem?
    // How far down before we consider "not at top"
    private let collapseThreshold: CGFloat = 60

    // Called on every scroll offset change
    func update(offset: CGFloat) {
        let delta = offset - lastOffset
        lastOffset = offset

        // Scrolling down past threshold → collapse
        if delta > 8 && offset > collapseThreshold && !isCollapsed {
            cancelIdleTimer()
            collapse()
            return
        }

        // Reached the very top while NOT scrolling down → expand
        if offset < 10 && isCollapsed && delta <= 0 {
            cancelIdleTimer()
            expand()
        }

        // Any movement resets the idle timer (including at top, so bar collapses after resting)
        if abs(delta) > 1 {
            scheduleIdleCollapse(after: 2.5)
        }
    }

    // Call once on appear to start the initial idle countdown
    func startInitialTimer() {
        scheduleIdleCollapse(after: 2.5)
    }

    // Called when user taps the collapsed pill to re-open
    func forceExpand() {
        expand()
        scheduleIdleCollapse(after: 2.5)
    }

    // Called whenever user taps any tab (activity signal — keeps bar open, resets timer)
    func signalActivity() {
        cancelIdleTimer()
        if isCollapsed { expand() }
        scheduleIdleCollapse(after: 2.5)
    }

    private func collapse() {
        guard !isCollapsed else { return }
        withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
            isCollapsed = true
        }
    }

    private func expand() {
        guard isCollapsed else { return }
        withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
            isCollapsed = false
        }
    }

    private func scheduleIdleCollapse(after delay: Double) {
        cancelIdleTimer()
        let work = DispatchWorkItem { [weak self] in
            self?.collapse()
        }
        idleTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelIdleTimer() {
        idleTimer?.cancel()
        idleTimer = nil
    }
}

// MARK: - TabBarState Environment Key

private struct TabBarStateKey: EnvironmentKey {
    static let defaultValue: TabBarScrollState? = nil
}

extension EnvironmentValues {
    var tabBarState: TabBarScrollState? {
        get { self[TabBarStateKey.self] }
        set { self[TabBarStateKey.self] = newValue }
    }
}

// MARK: - Scroll offset preference key

struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Scroll tracking modifier

struct ScrollOffsetTracker: ViewModifier {
    @EnvironmentObject var tabBarState: TabBarScrollState

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: ScrollOffsetKey.self,
                        value: geo.frame(in: .named("scrollCoord")).minY
                    )
                }
            )
            .onPreferenceChange(ScrollOffsetKey.self) { value in
                tabBarState.update(offset: -value)
            }
    }
}

extension View {
    func trackScrollForTabBar() -> some View {
        modifier(ScrollOffsetTracker())
    }
}

// MARK: - Main tab view

struct MainTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: Tab = .discover
    @State private var loadedTabs: Set<Tab> = [.discover]
    @State private var matchesDisplayMode: MatchesView.DisplayMode = .matches
    @State private var isChatThreadPresented = false
    @StateObject private var matchesViewModel = MatchesViewModel()
    @StateObject private var walletViewModel = WalletViewModel()
    @StateObject private var tabBarState = TabBarScrollState()
    @State private var globalMatchAlertProfile: UserProfile?
    @State private var globalMatchAlertMatchID: UUID?
    @State private var incomingProfilePhotoPage: Int = 0
    // Per-tab squish state for same-tab tap feedback
    @State private var squishTab: Tab? = nil

    enum Tab: Int, Hashable {
        case discover, matches, chats, profile

        var icon: String {
            switch self {
            case .discover: return "building.2.fill"
            case .matches:  return "heart.fill"
            case .chats:    return "bubble.left.and.bubble.right.fill"
            case .profile:  return "person.fill"
            }
        }

        var label: String {
            switch self {
            case .discover: return "Venue"
            case .matches:  return "Matches"
            case .chats:    return "Chat"
            case .profile:  return "Profile"
            }
        }
    }

    var body: some View {
        GeometryReader { screen in
            ZStack(alignment: .bottom) {
                AppTheme.background.ignoresSafeArea()

                tabContentStack
                    .environmentObject(tabBarState)
                    .environmentObject(walletViewModel)
                    .environment(\.tabBarState, tabBarState)

                if shouldShowTabBar {
                    floatingTabBar
                        .frame(width: screen.size.width * 0.70)
                        .padding(.bottom, 8)
                        .zIndex(100)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if let profile = matchesViewModel.selectedIncomingLikeProfile {
                    incomingProfileOverlay(profile: profile)
                        .transition(
                            .asymmetric(
                                insertion: .scale(scale: 0.88, anchor: .center).combined(with: .opacity),
                                removal: .scale(scale: 0.88, anchor: .center).combined(with: .opacity)
                            )
                        )
                        .zIndex(200)
                        .ignoresSafeArea()
                }
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: shouldShowTabBar)
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: matchesViewModel.selectedIncomingLikeProfile != nil)
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await matchesViewModel.resumeRealtimeAndSync() }
        }
        .onChange(of: selectedTab) { _, newTab in
            if newTab == .matches || newTab == .chats {
                matchesViewModel.incomingLikeBanner = nil
            }
            guard
                scenePhase == .active,
                newTab == .matches || newTab == .chats
            else { return }
            Task { await matchesViewModel.refreshMatchesNow() }
        }
        .onChange(of: matchesViewModel.incomingLikeBanner?.id) { _, _ in
            overlayTrace(
                "banner changed id=\(matchesViewModel.incomingLikeBanner?.id.uuidString ?? "nil") "
                    + "tab=\(selectedTab)"
            )
            updateGlobalInteractionOverlay()
        }
        .onChange(of: globalMatchAlertProfile?.id) { _, _ in
            updateGlobalInteractionOverlay()
        }
        .onAppear {
            tabBarState.startInitialTimer()
            guard scenePhase == .active else { return }
            Task { await matchesViewModel.resumeRealtimeAndSync() }
        }
        .onDisappear {
            GlobalInteractionOverlay.shared.hide()
        }
    }

    // MARK: - Floating Tab Bar

    private var floatingTabBar: some View {
        let collapsed = tabBarState.isCollapsed

        return ZStack {
            // Collapsed — single icon pill
            if collapsed {
                collapsedPill
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.7).combined(with: .opacity),
                            removal: .scale(scale: 0.7).combined(with: .opacity)
                        )
                    )
            } else {
                // Expanded — full oval
                expandedBar
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.85).combined(with: .opacity),
                            removal: .scale(scale: 0.85).combined(with: .opacity)
                        )
                    )
            }
        }
        .animation(.spring(response: 0.36, dampingFraction: 0.78), value: collapsed)
    }

    private var expandedBar: some View {
        HStack(spacing: 0) {
            ForEach([Tab.discover, .matches, .chats, .profile], id: \.self) { tab in
                tabPill(tab: tab)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            ZStack {
                Capsule()
                    .fill(.ultraThinMaterial)
                Capsule()
                    .fill(AppTheme.cardBackground.opacity(0.86))
                Capsule()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.16),
                                AppTheme.pink.opacity(0.20),
                                Color.white.opacity(0.07),
                                AppTheme.purple.opacity(0.16)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: .black.opacity(0.32), radius: 20, x: 0, y: 7)
        .shadow(color: AppTheme.pink.opacity(0.10), radius: 10, x: 0, y: 3)
    }

    private var collapsedPill: some View {
        Button {
            tabBarState.forceExpand()
        } label: {
            ZStack {
                // Active tab icon
                Image(systemName: selectedTab.icon)
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(AppTheme.primaryGradient)

                // 3 dot indicators around the edge
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(AppTheme.pink.opacity(0.65))
                        .frame(width: 3, height: 3)
                        .offset(y: -18)
                        .rotationEffect(.degrees(Double(i) * 120))
                }
            }
            .frame(width: 46, height: 46)
            .background(
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                    Circle()
                        .fill(AppTheme.cardBackground.opacity(0.88))
                    Circle()
                        .stroke(
                            AngularGradient(
                                colors: [
                                    AppTheme.pink.opacity(0.7),
                                    AppTheme.purple.opacity(0.5),
                                    Color(hex: "C44EFF").opacity(0.6),
                                    AppTheme.pink.opacity(0.7)
                                ],
                                center: .center
                            ),
                            lineWidth: 1.2
                        )
                }
            )
            .shadow(color: AppTheme.pink.opacity(0.35), radius: 18, x: 0, y: 6)
            .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }

    private func tabPill(tab: Tab) -> some View {
        let isActive = selectedTab == tab
        let count = badgeCount(for: tab)
        let isSquishy = squishTab == tab

        return Button {
            if isActive {
                // Same-tab tap — jelly squish feedback
                tabBarState.signalActivity()
                withAnimation(.spring(response: 0.18, dampingFraction: 0.35)) {
                    squishTab = tab
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.45)) {
                        squishTab = nil
                    }
                }
            } else {
                tabBarState.signalActivity()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
                    if let displayMode = Self.matchesDisplayMode(for: tab) {
                        matchesDisplayMode = displayMode
                    }
                    loadedTabs = Self.loadedTabs(afterSelecting: tab, current: loadedTabs)
                    selectedTab = tab
                }
            }
        } label: {
            VStack(spacing: 3) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: tab.icon)
                        // Active: 22pt full weight. Inactive: 17pt regular — clear size hierarchy
                        .font(.system(size: isActive ? 22 : 17, weight: isActive ? .bold : .regular))
                        .foregroundStyle(
                            isActive
                                ? AnyShapeStyle(AppTheme.primaryGradient)
                                : AnyShapeStyle(AppTheme.textTertiary)
                        )
                        // Squish: compress vertically, widen slightly like a rubber stamp
                        .scaleEffect(
                            x: isSquishy ? 1.18 : 1,
                            y: isSquishy ? 0.72 : 1
                        )
                        .animation(.spring(response: 0.22, dampingFraction: 0.38), value: isSquishy)

                    if count > 0 {
                        Text(count > 9 ? "9+" : "\(count)")
                            .font(.system(size: 7, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .frame(minWidth: 13, minHeight: 13)
                            .padding(.horizontal, 2)
                            .background(AppTheme.pink)
                            .clipShape(Capsule())
                            .offset(x: 8, y: -6)
                    }
                }
                .frame(height: 24)

                Text(tab.label)
                    .font(.system(size: 9, weight: isActive ? .bold : .regular, design: .rounded))
                    .foregroundStyle(
                        isActive
                            ? AnyShapeStyle(AppTheme.primaryGradient)
                            : AnyShapeStyle(AppTheme.textTertiary)
                    )
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
    }

    private func badgeCount(for tab: Tab) -> Int {
        switch tab {
        case .matches: return newMatchesCount
        case .chats:   return unreadChatCount
        default:       return 0
        }
    }

    private var shouldShowTabBar: Bool {
        !tabBarState.isHidden && !((selectedTab == .matches || selectedTab == .chats) && isChatThreadPresented)
    }

    @ViewBuilder
    private func incomingProfileOverlay(profile: UserProfile) -> some View {
        let pendingMatch = MatchesView.pendingLikeMatch(
            for: profile.id,
            in: matchesViewModel.matches,
            isPending: matchesViewModel.isPendingIncomingLike
        )
        let messageMatch = MatchesView.messageMatch(
            for: profile.id,
            in: matchesViewModel.matches,
            isPending: matchesViewModel.isPendingIncomingLike
        )
        let treatInvite = pendingMatch.flatMap { matchesViewModel.pendingTreatInvite(for: $0) }

        ProfileFullDetailView(
            profile: profile,
            photoStoryPage: $incomingProfilePhotoPage,
            isPresented: Binding(
                get: { matchesViewModel.selectedIncomingLikeProfile != nil },
                set: { if !$0 { matchesViewModel.selectedIncomingLikeProfile = nil } }
            ),
            showActions: false,
            onPass: {
                if treatInvite != nil, let pendingMatch {
                    matchesViewModel.reviewTreatInvite(pendingMatch, accept: false)
                } else if let pendingMatch {
                    matchesViewModel.reviewIncomingLike(pendingMatch, decision: .nope)
                }
                matchesViewModel.selectedIncomingLikeProfile = nil
            },
            onLike: {
                if treatInvite != nil, let pendingMatch {
                    matchesViewModel.reviewTreatInvite(pendingMatch, accept: true)
                } else if let pendingMatch {
                    matchesViewModel.reviewIncomingLike(pendingMatch, decision: .like)
                } else if let messageMatch {
                    openMatchChat(messageMatch)
                }
                matchesViewModel.selectedIncomingLikeProfile = nil
            }
        )
        .onDisappear {
            incomingProfilePhotoPage = 0
        }
    }

    private func openMatchChat(_ match: Match) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            matchesDisplayMode = .chats
            loadedTabs = Self.loadedTabs(afterSelecting: .chats, current: loadedTabs)
            selectedTab = .chats
        }
        DispatchQueue.main.async {
            matchesViewModel.openChat(for: match)
        }
    }

    private func handleIncomingBannerTap() {
        guard let banner = matchesViewModel.incomingLikeBanner else { return }

        if banner.isMatch {
            presentGlobalMatchAlertIfNeeded()
            return
        }

        guard let profile = banner.profile else { return }
        matchesViewModel.incomingLikeBanner = nil
        matchesViewModel.presentProfileSheet(for: profile)
    }

    private func presentGlobalMatchAlertIfNeeded() {
        guard globalMatchAlertProfile == nil else { return }
        guard let banner = matchesViewModel.incomingLikeBanner, banner.isMatch else { return }
        guard let profile = banner.profile else { return }

        globalMatchAlertProfile = profile
        globalMatchAlertMatchID = banner.matchId
        matchesViewModel.incomingLikeBanner = nil
    }

    private func dismissGlobalMatchAlert() {
        globalMatchAlertProfile = nil
        globalMatchAlertMatchID = nil
    }

    private func openGlobalMatchChat() {
        guard let profile = globalMatchAlertProfile else { return }

        let match = matchesViewModel.matches.first(where: { $0.profile.id == profile.id })
            ?? matchesViewModel.addMatch(for: profile, matchId: globalMatchAlertMatchID)
        dismissGlobalMatchAlert()
        openMatchChat(match)
    }

    private func updateGlobalInteractionOverlay() {
        if let profile = globalMatchAlertProfile {
            GlobalInteractionOverlay.shared.showFullScreen(
                MatchAlertView(
                    profile: profile,
                    onKeepSwiping: dismissGlobalMatchAlert,
                    onSendMessage: openGlobalMatchChat
                )
            )
            return
        }

        guard let banner = matchesViewModel.incomingLikeBanner else {
            overlayTrace("no banner; hiding")
            GlobalInteractionOverlay.shared.hide()
            return
        }

        if banner.isMatch {
            overlayTrace("presenting full-screen match sender=\(banner.profileId)")
            presentGlobalMatchAlertIfNeeded()
            return
        }

        overlayTrace("presenting like toast sender=\(banner.profileId)")
        GlobalInteractionOverlay.shared.showToast(
            IncomingLikeToast(banner: banner) {
                handleIncomingBannerTap()
            }
        )
    }

    @ViewBuilder
    private var tabContentStack: some View {
        ZStack {
            if loadedTabs.contains(.discover) {
                tabLayer(isActive: selectedTab == .discover) {
                    DiscoverView(
                        matchesViewModel: matchesViewModel,
                        onOpenMatchChat: openMatchChat
                    )
                }
            }

            if loadedTabs.contains(.matches) || loadedTabs.contains(.chats) {
                tabLayer(isActive: selectedTab == .matches || selectedTab == .chats) {
                    MatchesView(
                        isChatThreadPresented: $isChatThreadPresented,
                        viewModel: matchesViewModel,
                        displayMode: matchesDisplayMode
                    )
                }
            }

            if loadedTabs.contains(.profile) {
                tabLayer(isActive: selectedTab == .profile) {
                    ProfileView(matchesCount: matchesViewModel.matches.count)
                }
            }
        }
    }

    private func tabLayer<Content: View>(
        isActive: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(isActive ? 1 : 0)
            .allowsHitTesting(isActive)
            .accessibilityHidden(!isActive)
            .zIndex(isActive ? 1 : 0)
    }

    private var unreadChatCount: Int { Self.unreadChatCount(in: matchesViewModel.matches) }
    private var newMatchesCount: Int { Self.newMatchesCount(in: matchesViewModel.matches) }

    static func unreadChatCount(in matches: [Match]) -> Int {
        matches.reduce(0) { $0 + $1.unreadCount }
    }
    static func newMatchesCount(in matches: [Match]) -> Int {
        matches.filter(\.isNew).count
    }
    static func loadedTabs(afterSelecting tab: Tab, current: Set<Tab>) -> Set<Tab> {
        current.union([tab])
    }
    static func matchesDisplayMode(for tab: Tab) -> MatchesView.DisplayMode? {
        switch tab {
        case .matches: return .matches
        case .chats:   return .chats
        case .discover, .profile: return nil
        }
    }
}

// MARK: - Incoming like toast

private struct IncomingLikeToast: View {
    let banner: MatchesViewModel.IncomingLikeBanner
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: bannerIcon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(bannerIconColor)
                .frame(width: 28, height: 28)
                .background(AppTheme.surfaceElevated)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
                Text(message)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(AppTheme.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.surface, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture(perform: onTap)
    }

    private var bannerIcon: String {
        if banner.isMatch { return "sparkles" }
        if banner.treat != nil { return "gift.fill" }
        return banner.isSuperLike ? "star.fill" : "heart.fill"
    }
    private var bannerIconColor: Color {
        if banner.isMatch { return AppTheme.green }
        if banner.treat != nil { return AppTheme.gold }
        return banner.isSuperLike ? AppTheme.gold : AppTheme.pink
    }
    private var title: String {
        if banner.isMatch { return "New match" }
        if banner.treat != nil { return "New invite" }
        return banner.isSuperLike ? "New super like" : "New like"
    }
    private var message: String {
        if banner.isMatch { return "You matched with \(banner.name)" }
        if let treat = banner.treat { return "\(banner.name) wants to \(treat.notificationNoun)" }
        return "\(banner.name) liked your profile"
    }
}
