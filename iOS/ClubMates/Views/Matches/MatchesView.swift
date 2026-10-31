import SwiftUI

struct MatchesView: View {
    private enum MatchesTab {
        case forYou
        case connected
    }

    private enum ConnectedLayout {
        case list
        case grid
    }

    enum DisplayMode {
        case matches
        case chats

        var screenTitle: String {
            switch self {
            case .matches:
                return "Matches"
            case .chats:
                return "Chat"
            }
        }

        var searchPlaceholder: String {
            switch self {
            case .matches:
                return "Search matches"
            case .chats:
                return "Search by name or message"
            }
        }
    }

    @Binding var isChatThreadPresented: Bool
    @ObservedObject var viewModel: MatchesViewModel
    let displayMode: DisplayMode
    @State private var isSearchVisible = false
    @State private var searchText = ""
    @State private var pendingUnmatch: Match?
    @State private var selectedMatchesTab: MatchesTab = .forYou
    @State private var connectedLayout: ConnectedLayout = .list
    @State private var toastMessage: String?
    @State private var toastTask: Task<Void, Never>?
    @FocusState private var isSearchFieldFocused: Bool

    private let accentGradient = LinearGradient(
        colors: [Color(hex: "EC4899"), Color(hex: "8B5CF6")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    var body: some View {
        NavigationStack {
            ZStack {
                screenBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    header

                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            Color.clear.frame(height: 0).trackScrollForTabBar()
                            switch displayMode {
                            case .matches:
                                newMatchesSection
                            case .chats:
                                messagesSection
                            }
                        }
                    }
                    .refreshable {
                        await viewModel.refreshMatchesNow()
                    }
                    .coordinateSpace(name: "scrollCoord")
                }

                if let toastMessage {
                    VStack {
                        Spacer()
                        toastView(toastMessage)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 18)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(20)
                }
            }
            .navigationDestination(item: $viewModel.selectedMatch) { match in
                ChatView(match: match, viewModel: viewModel)
                    .onAppear {
                        isChatThreadPresented = true
                    }
                    .onDisappear {
                        isChatThreadPresented = false
                        viewModel.closeChat()
                    }
            }
            .confirmationDialog(
                unmatchDialogTitle,
                isPresented: isUnmatchConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button("Unmatch", role: .destructive) {
                    if let pendingUnmatch {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                            viewModel.unmatch(pendingUnmatch)
                        }
                    }
                    pendingUnmatch = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingUnmatch = nil
                }
            } message: {
                Text("This removes the conversation and chat history from Matches.")
            }
        }
    }

    private var screenBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: "0A0A0F"),
                    Color(hex: "10091D"),
                    Color(hex: "0A0A0F")
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            Circle()
                .fill(Color(hex: "EC4899").opacity(0.22))
                .frame(width: 260, height: 260)
                .blur(radius: 72)
                .offset(x: -120, y: -120)
            Circle()
                .fill(Color(hex: "8B5CF6").opacity(0.24))
                .frame(width: 280, height: 280)
                .blur(radius: 80)
                .offset(x: 140, y: 300)
            Rectangle()
                .fill(Color.white.opacity(0.015))
                .blendMode(.overlay)
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            HStack(alignment: displayMode == .matches ? .top : .center) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(screenTitle)
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundColor(AppTheme.textPrimary)

                    if displayMode == .matches {
                        Text(matchesSubtitle)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(Color.white.opacity(0.5))
                    }
                }

                Spacer()

                Button(action: toggleSearch) {
                    Image(systemName: showsSearchField ? "xmark" : "magnifyingglass")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary)
                        .frame(width: 42, height: 42)
                        .background(glassFill)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(glassStroke, lineWidth: 1)
                        )
                }
            }

            if showsSearchField {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary)

                    TextField(searchPlaceholder, text: $searchText)
                        .foregroundColor(AppTheme.textPrimary)
                        .font(.system(size: 15, design: .rounded))
                        .focused($isSearchFieldFocused)
                        .textInputAutocapitalization(.words)
                        .disableAutocorrection(true)

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(AppTheme.textTertiary)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(glassFill)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(glassStroke, lineWidth: 1)
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if displayMode == .matches {
                matchesSegmentedControl
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: showsSearchField)
    }

    private var newMatchesSection: some View {
        Group {
            switch selectedMatchesTab {
            case .forYou:
                forYouSection
            case .connected:
                connectedSection
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 24)
    }

    private var forYouSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(title: "Pending Invites", trailing: filteredPendingLikes.isEmpty ? nil : "View All")

            if filteredPendingLikes.isEmpty {
                sectionPlaceholder(
                    title: trimmedSearchText.isEmpty ? "Nothing waiting right now" : "No requests found",
                    subtitle: trimmedSearchText.isEmpty
                        ? "Incoming likes and venue invites will appear here for quick decisions."
                        : "Try another name or clear search to see all requests.",
                    symbolName: trimmedSearchText.isEmpty ? "tray.fill" : "magnifyingglass"
                )
                .padding(.horizontal, 20)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(filteredPendingLikes) { match in
                        pendingInviteCard(match)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .trailing)),
                                removal: .opacity.combined(with: .move(edge: .leading))
                            ))
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: filteredPendingLikes.map(\.id))
    }

    private var connectedSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("\(filteredRealMatches.count) Connected")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.5))
                    .textCase(.uppercase)
                    .tracking(1.2)

                Spacer()

                connectedLayoutToggle
            }
            .padding(.horizontal, 20)

            if filteredRealMatches.isEmpty {
                sectionPlaceholder(
                    title: trimmedSearchText.isEmpty ? "No connected matches yet" : "No connections found",
                    subtitle: trimmedSearchText.isEmpty
                        ? "Accept an invite or match with someone to start a connection."
                        : "No confirmed matches match that search.",
                    symbolName: trimmedSearchText.isEmpty ? "person.2.fill" : "magnifyingglass"
                )
                .padding(.horizontal, 20)
            } else {
                switch connectedLayout {
                case .list:
                    connectedList
                case .grid:
                    connectedGrid
                }
            }
        }
    }

    private var matchesSegmentedControl: some View {
        HStack(spacing: 0) {
            matchesTabButton(.forYou, title: "For You", count: filteredPendingLikes.count)
            matchesTabButton(.connected, title: "Connected", count: nil)
        }
        .padding(5)
        .background(glassFill)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(glassStroke, lineWidth: 1)
        )
    }

    private func matchesTabButton(_ tab: MatchesTab, title: String, count: Int?) -> some View {
        Button {
            withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.3)) {
                selectedMatchesTab = tab
            }
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(selectedMatchesTab == tab ? .white : Color.white.opacity(0.52))
                    .lineLimit(1)

                if let count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .frame(minWidth: 22, minHeight: 22)
                        .background(Color(hex: "FF453A"))
                        .clipShape(Capsule())
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background {
                if selectedMatchesTab == tab {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(accentGradient)
                        .shadow(color: Color(hex: "EC4899").opacity(0.32), radius: 16, x: 0, y: 8)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var connectedLayoutToggle: some View {
        HStack(spacing: 8) {
            connectedLayoutButton(.grid, title: "Grid")
            connectedLayoutButton(.list, title: "List")
        }
    }

    private func connectedLayoutButton(_ layout: ConnectedLayout, title: String) -> some View {
        Button {
            withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.25)) {
                connectedLayout = layout
            }
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(connectedLayout == layout ? .white : Color.white.opacity(0.55))
                .frame(height: 38)
                .padding(.horizontal, 16)
                .background {
                    if connectedLayout == layout {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(accentGradient)
                    } else {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.clear)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(connectedLayout == layout ? .clear : Color.white.opacity(0.1), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func sectionHeader(title: String, trailing: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(Color.white.opacity(0.5))
                .textCase(.uppercase)
                .tracking(1.2)

            Spacer()

            if let trailing {
                Button(trailing) {}
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "EC4899"))
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
    }


    private func pendingInviteCard(_ match: Match) -> some View {
        let invite = viewModel.pendingTreatInvite(for: match)
        let isOnline = viewModel.isUserOnline(match.profile.id)

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                avatarTile(profile: match.profile, size: 56, radius: 16, border: accentGradient)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("\(match.profile.name), \(match.profile.age)")
                            .font(.system(size: 17, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)

                        if isNew(match) {
                            Text("NEW")
                                .font(.system(size: 10, weight: .black, design: .rounded))
                                .foregroundColor(Color(hex: "EC4899"))
                                .padding(.horizontal, 8)
                                .frame(height: 22)
                                .background(Color(hex: "EC4899").opacity(0.16))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        Spacer(minLength: 4)
                        onlineLabel(isOnline)
                    }

                    Text(pendingDescription(for: match, invite: invite))
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.5))
                        .lineLimit(1)

                    if hasVenueName(match) {
                        venueTag(for: match)
                    }
                }
            }

            HStack(spacing: 12) {
                Spacer(minLength: 70)
                pendingActionButton(title: "Decline", style: .secondary) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                        if invite != nil {
                            viewModel.reviewTreatInvite(match, accept: false)
                        } else {
                            viewModel.reviewIncomingLike(match, decision: .nope)
                        }
                    }
                    showToast("Invite declined")
                }

                pendingActionButton(title: "Accept", style: .primary) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                        if invite != nil {
                            viewModel.reviewTreatInvite(match, accept: true)
                        } else {
                            viewModel.reviewIncomingLike(match, decision: .like)
                        }
                        selectedMatchesTab = .connected
                    }
                    showToast("You and \(match.profile.name) are now connected")
                }
            }
            .padding(.top, 18)
        }
        .padding(18)
        .background(glassFill)
        .background(.ultraThinMaterial.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(accentGradient)
                .frame(width: 3)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(glassStroke, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.handleNewMatchTap(match)
        }
    }

    private enum PendingActionStyle {
        case primary
        case secondary
    }

    private func pendingActionButton(title: String, style: PendingActionStyle, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(style == .primary ? .white : Color.white.opacity(0.6))
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background {
                    if style == .primary {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(accentGradient)
                            .shadow(color: Color(hex: "EC4899").opacity(0.25), radius: 14, x: 0, y: 7)
                    } else {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.clear)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(style == .primary ? .clear : Color.white.opacity(0.1), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var connectedList: some View {
        LazyVStack(spacing: 12) {
            ForEach(filteredRealMatches) { match in
                connectedListCard(match)
            }
        }
        .padding(.horizontal, 20)
    }

    private func connectedListCard(_ match: Match) -> some View {
        let isOnline = viewModel.isUserOnline(match.profile.id)

        return HStack(alignment: .center, spacing: 14) {
            avatarTile(profile: match.profile, size: 64, radius: 18, border: nil)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Text("\(match.profile.name), \(match.profile.age)")
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    onlineLabel(isOnline)
                }

                Text(matchContext(for: match))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.5))
                    .lineLimit(1)

                HStack(spacing: 10) {
                    Button {
                        viewModel.openChat(for: match)
                    } label: {
                        Text("Start Chat")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .background(accentGradient)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button {
                        requestUnmatch(match)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(Color.white.opacity(0.62))
                            .frame(width: 44, height: 42)
                            .background(Color.white.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(glassFill)
        .background(.ultraThinMaterial.opacity(0.28))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(glassStroke, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.handleNewMatchTap(match)
        }
        .contextMenu {
            Button(role: .destructive) {
                requestUnmatch(match)
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    private var connectedGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
            spacing: 12
        ) {
            ForEach(filteredRealMatches) { match in
                connectedGridCard(match)
            }
        }
        .padding(.horizontal, 20)
    }


    private func connectedGridCard(_ match: Match) -> some View {
        let isOnline = viewModel.isUserOnline(match.profile.id)

        return GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                ProfilePhotoView(
                    photo: match.profile.mainPhoto,
                    symbolName: "person.fill",
                    symbolSize: 56,
                    gradientColors: profileGradientColors(for: match.profile),
                    symbolOpacity: 0.14,
                    contentMode: .fill,
                    contentAlignment: .top
                )
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()

                VStack(spacing: 0) {
                    Spacer()
                    LinearGradient(
                        colors: [
                            Color(hex: "0A0A0F").opacity(0.95),
                            Color(hex: "0A0A0F").opacity(0.6),
                            .clear
                        ],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                    .frame(height: proxy.size.height * 0.6)
                }

                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(match.profile.name)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)

                        Text("\(match.profile.age)")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(Color.white.opacity(0.5))
                    }

                    Text(matchContext(for: match))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.4))
                        .lineLimit(1)
                        .padding(.top, 3)
                        .padding(.bottom, 10)

                    Button {
                        viewModel.openChat(for: match)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "bubble.left")
                                .font(.system(size: 12, weight: .bold))
                            Text("Chat")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(accentGradient)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 0) {
                    Button {
                        viewModel.handleNewMatchTap(match)
                    } label: {
                        Color.clear
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Spacer()
                        .frame(height: 112)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack {
                    HStack {
                        Spacer()
                        Circle()
                            .fill(isOnline ? Color(hex: "30D158") : Color.white.opacity(0.24))
                            .frame(width: 12, height: 12)
                            .overlay(Circle().stroke(Color(hex: "0A0A0F").opacity(0.8), lineWidth: 2))
                            .shadow(
                                color: isOnline ? Color(hex: "30D158").opacity(0.5) : .clear,
                                radius: 8
                            )
                    }
                    Spacer()
                }
                .padding(.top, 10)
                .padding(.trailing, 10)
            }
        }
        .aspectRatio(3/4, contentMode: .fit)
        .background(glassFill)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(glassStroke, lineWidth: 1)
        )
        .contextMenu {
            Button(role: .destructive) {
                requestUnmatch(match)
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }


    private func profileGradientColors(for profile: UserProfile) -> [Color] {
        let sets: [[String]] = [
            ["1E1B4B", "7C3AED"],
            ["0F172A", "0E7490"],
            ["1A1A2E", "BE185D"],
            ["0C1445", "1D4ED8"],
            ["14532D", "047857"]
        ]
        let g = sets[abs(profile.name.hashValue) % sets.count]
        return [Color(hex: g[0]), Color(hex: g[1])]
    }


    private var messagesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Conversations")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(AppTheme.textSecondary)
                .textCase(.uppercase)
                .tracking(0.8)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

            if filteredMessageMatches.isEmpty {
                sectionPlaceholder(
                    title: trimmedSearchText.isEmpty ? "No conversations yet" : "No conversations found",
                    subtitle: trimmedSearchText.isEmpty
                        ? "Start a chat from your matches and conversations will live here."
                        : "No threads match that search right now.",
                    symbolName: trimmedSearchText.isEmpty ? "bubble.left.and.bubble.right.fill" : "tray.fill"
                )
                .padding(.horizontal, 20)
            } else {
                ForEach(filteredMessageMatches) { match in
                    SwipeToUnmatchRow(
                        match: match,
                        onOpen: { viewModel.openChat(for: match) },
                        onUnmatch: { requestUnmatch(match) }
                    ) {
                        messageRow(match)
                    }
                }
            }
        }
    }

    private func messageRow(_ match: Match) -> some View {
        HStack(spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                ProfileAvatar(profile: match.profile, size: 58)
                if match.unreadCount > 0 {
                    Text("\(match.unreadCount)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(width: 20, height: 20)
                        .background(AppTheme.pink)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(AppTheme.background, lineWidth: 2))
                        .offset(x: 4, y: 4)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(match.profile.name)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(AppTheme.textPrimary)
                    Spacer()
                    Text(match.lastMessageTime, style: .relative)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(AppTheme.textTertiary)
                }
                Text(match.lastMessage.isEmpty ? "Say hi! 👋" : match.lastMessage)
                    .font(.system(size: 14, design: .rounded))
                    .foregroundColor(match.unreadCount > 0 ? AppTheme.textPrimary : AppTheme.textSecondary)
                    .fontWeight(match.unreadCount > 0 ? .medium : .regular)
                    .lineLimit(1)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(AppTheme.textTertiary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            match.unreadCount > 0 ? AppTheme.cardBackground : Color.clear
        )
    }

    private func avatarTile(
        profile: UserProfile,
        size: CGFloat,
        radius: CGFloat,
        border: LinearGradient?
    ) -> some View {
        ZStack(alignment: .bottomTrailing) {
            ProfilePhotoView(
                photo: profile.mainPhoto,
                symbolName: "person.fill",
                symbolSize: size * 0.36,
                gradientColors: profileGradientColors(for: profile),
                symbolOpacity: 0.18,
                contentMode: .fill,
                contentAlignment: .top
            )
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                if let border {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(border, lineWidth: 1.6)
                }
            }
        }
    }

    private func onlineLabel(_ isOnline: Bool) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(isOnline ? Color(hex: "30D158") : Color.white.opacity(0.35))
                .frame(width: 7, height: 7)
            Text(isOnline ? "ONLINE" : "Offline")
                .font(.system(size: 10, weight: .black, design: .rounded))
        }
        .foregroundColor(isOnline ? Color(hex: "30D158") : Color.white.opacity(0.4))
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(Color.white.opacity(isOnline ? 0.07 : 0.035))
        .clipShape(Capsule())
    }

    private func venueTag(for match: Match) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 12, weight: .bold))
            Text(venueText(for: match))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .lineLimit(1)
        }
        .foregroundColor(Color.white.opacity(0.42))
    }

    private func pendingDescription(for match: Match, invite: APITreatInvite?) -> String {
        if let invite {
            return "Sent a \(invite.treatType.inviteLabel) invite • \(relativeShortTime(match.lastMessageTime))"
        }
        if match.lastMessage.localizedCaseInsensitiveContains("super") {
            return "Sent a superlike • \(relativeShortTime(match.lastMessageTime))"
        }
        return "Sent a like • \(relativeShortTime(match.lastMessageTime))"
    }

    private func venueText(for match: Match) -> String {
        if let venueName = match.venueName, !venueName.isEmpty {
            return venueName
        }
        return ""
    }

    private func hasVenueName(_ match: Match) -> Bool {
        !venueText(for: match).isEmpty
    }

    private func matchContext(for match: Match) -> String {
        let venue = venueText(for: match)
        if venue.isEmpty {
            return "Connected • \(relativeShortTime(match.lastMessageTime))"
        }
        return "Matched at \(venue) • \(relativeShortTime(match.lastMessageTime))"
    }

    private func isNew(_ match: Match) -> Bool {
        Date().timeIntervalSince(match.lastMessageTime) < 3600
    }

    private func relativeShortTime(_ date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 60 { return "Now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        let days = hours / 24
        return "\(days)d ago"
    }

    private var glassFill: Color {
        Color.white.opacity(0.04)
    }

    private var glassStroke: Color {
        Color.white.opacity(0.06)
    }

    private var matchesSubtitle: String {
        let count = filteredPendingLikes.count
        if count == 1 {
            return "1 person waiting for you"
        }
        if count > 0 {
            return "\(count) people waiting for you"
        }
        if filteredRealMatches.isEmpty {
            return "New connections will appear here"
        }
        return "\(filteredRealMatches.count) connected"
    }

    private func toastView(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(accentGradient)

            Text(message)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(2)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(Color(hex: "17171D").opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(glassStroke, lineWidth: 1)
        )
    }

    private func showToast(_ message: String) {
        toastTask?.cancel()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
            toastMessage = message
        }
        toastTask = Task {
            do {
                try await Task.sleep(nanoseconds: 2_200_000_000)
            } catch {
                return
            }
            await MainActor.run {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                    toastMessage = nil
                }
            }
        }
    }

    private func toggleSearch() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
            if showsSearchField {
                searchText = ""
                isSearchVisible = false
                isSearchFieldFocused = false
            } else {
                isSearchVisible = true
            }
        }

        if isSearchVisible {
            DispatchQueue.main.async {
                isSearchFieldFocused = true
            }
        }
    }

    private func sectionPlaceholder(title: String, subtitle: String, symbolName: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AppTheme.surfaceElevated)
                    .frame(width: 54, height: 54)

                Image(systemName: symbolName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryGradient)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(AppTheme.textSecondary)
            }

            Spacer()
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AppTheme.surface, lineWidth: 1)
        )
    }

    private var filteredMatches: [Match] {
        guard !trimmedSearchText.isEmpty else { return viewModel.matches }

        return viewModel.matches.filter { match in
            match.profile.name.localizedCaseInsensitiveContains(trimmedSearchText)
                || match.lastMessage.localizedCaseInsensitiveContains(trimmedSearchText)
        }
    }

    private var filteredPendingLikes: [Match] {
        Self.pendingLikeMatches(filteredMatches, isPending: viewModel.isPendingIncomingLike)
    }

    private var filteredRealMatches: [Match] {
        Self.realMatches(filteredMatches, isPending: viewModel.isPendingIncomingLike)
    }

    private var filteredMessageMatches: [Match] {
        Self.conversationMatches(filteredMatches, isPending: viewModel.isPendingIncomingLike)
    }

    private var showsSearchField: Bool {
        isSearchVisible || !trimmedSearchText.isEmpty
    }

    private var screenTitle: String {
        displayMode.screenTitle
    }

    private var searchPlaceholder: String {
        displayMode.searchPlaceholder
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func requestUnmatch(_ match: Match) {
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
        pendingUnmatch = match
    }

    private var isUnmatchConfirmationPresented: Binding<Bool> {
        Binding(
            get: { pendingUnmatch != nil },
            set: { isPresented in
                if !isPresented {
                    pendingUnmatch = nil
                }
            }
        )
    }

    private var unmatchDialogTitle: String {
        if let pendingUnmatch {
            return "Unmatch \(pendingUnmatch.profile.name)?"
        }

        return "Unmatch?"
    }

    static func visibleMatches(_ matches: [Match]) -> [Match] {
        matches
    }

    static func pendingLikeMatches(_ matches: [Match], isPending: (Match) -> Bool) -> [Match] {
        matches.filter(isPending)
    }

    static func realMatches(_ matches: [Match], isPending: (Match) -> Bool) -> [Match] {
        matches.filter { !isPending($0) }
    }

    static func conversationMatches(_ matches: [Match], isPending: (Match) -> Bool = { _ in false }) -> [Match] {
        matches.filter { !$0.isNew && !isPending($0) }
    }

    static func pendingLikeMatch(
        for profileID: UUID,
        in matches: [Match],
        isPending: (Match) -> Bool
    ) -> Match? {
        matches.first { match in
            match.profile.id == profileID && isPending(match)
        }
    }

    static func messageMatch(
        for profileID: UUID,
        in matches: [Match],
        isPending: (Match) -> Bool
    ) -> Match? {
        matches.first { match in
            match.profile.id == profileID && !isPending(match)
        }
    }
}


private struct SwipeToUnmatchRow<Content: View>: View {
    let match: Match
    let onOpen: () -> Void
    let onUnmatch: () -> Void
    let content: () -> Content

    @State private var settledOffset: CGFloat = 0
    @State private var dragTranslation: CGFloat = 0

    private let actionWidth: CGFloat = 104

    init(
        match: Match,
        onOpen: @escaping () -> Void,
        onUnmatch: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.match = match
        self.onOpen = onOpen
        self.onUnmatch = onUnmatch
        self.content = content
    }

    var body: some View {
        ZStack {
            content()
                .opacity(0)
                .overlay(swipeBackground)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            content()
                .background(AppTheme.background)
                .offset(x: rowOffset)
                .contentShape(Rectangle())
                .onTapGesture {
                    if settledOffset == 0 {
                        onOpen()
                    } else {
                        resetRow()
                    }
                }
                .simultaneousGesture(rowDrag)
        }
        .clipped()
        .accessibilityAction(named: Text("Unmatch")) {
            onUnmatch()
        }
    }

    private var swipeBackground: some View {
        HStack(spacing: 0) {
            swipeAction
                .opacity(rowOffset > 8 ? 1 : 0)

            Spacer(minLength: 0)

            swipeAction
                .opacity(rowOffset < -8 ? 1 : 0)
        }
        .background(AppTheme.red.opacity(0.18 + (0.82 * revealProgress)))
    }

    private var swipeAction: some View {
        Button {
            resetRow()
            onUnmatch()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "person.crop.circle.badge.xmark")
                    .font(.system(size: 18, weight: .semibold))
                Text("Unmatch")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .foregroundColor(.white)
            .frame(width: actionWidth)
            .frame(maxHeight: .infinity)
        }
        .buttonStyle(.plain)
    }

    private var rowDrag: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                dragTranslation = value.translation.width
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else {
                    resetRow()
                    return
                }

                let proposedOffset = settledOffset + value.translation.width
                let predictedOffset = settledOffset + value.predictedEndTranslation.width
                let shouldRequestUnmatch = abs(proposedOffset) > actionWidth * 1.15
                    || abs(predictedOffset) > actionWidth * 1.55

                if shouldRequestUnmatch {
                    resetRow()
                    onUnmatch()
                } else if proposedOffset > actionWidth * 0.45 {
                    settleRow(at: actionWidth)
                } else if proposedOffset < -actionWidth * 0.45 {
                    settleRow(at: -actionWidth)
                } else {
                    resetRow()
                }
            }
    }

    private var rowOffset: CGFloat {
        max(-actionWidth * 1.2, min(actionWidth * 1.2, settledOffset + dragTranslation))
    }

    private var revealProgress: Double {
        min(1, Double(abs(rowOffset) / actionWidth))
    }

    private func settleRow(at offset: CGFloat) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            settledOffset = offset
            dragTranslation = 0
        }
    }

    private func resetRow() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            settledOffset = 0
            dragTranslation = 0
        }
    }
}
