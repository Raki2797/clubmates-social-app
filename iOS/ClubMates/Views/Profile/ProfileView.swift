import SwiftUI

struct ProfileView: View {
    var matchesCount: Int = SampleData.matches.count

    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var walletVM: WalletViewModel
    @State private var profile = SampleData.myProfile
    @State private var selectedMode: ProfileMode = .manage
    @State private var showEditSheet = false
    @State private var editingPromptIndex: PromptIndex? = nil
    @State private var showNewPromptSheet = false
    @State private var newPromptDraft = UserProfile.Prompt(question: PromptEditorView.questions[0], answer: "")
    @State private var showInterestPicker = false
    @State private var showPrivacy = false
    @State private var showParticipation = false
    @State private var showHelpSupport = false
    @State private var showNotificationSettings = false
    @State private var showPreferences = false
    @State private var showDeleteAccountConfirmation = false
    @State private var isDeletingAccount = false
    @State private var deleteAccountError: String?
    @State private var showCoinShop = false
    @State private var photoStoryPage = 0
    @State private var showFullProfileDetail = false
    @State private var suppressNextProfileAutosave = false
    @State private var showVerification = false
    @State private var fullProfileAppeared = false
    @State private var ringRotation: Double = 0
    @State private var orbit1Angle: Double = 0
    @State private var orbit2Angle: Double = 90
    @State private var orbit3Angle: Double = 180
    @State private var orbit4Angle: Double = 270
    @State private var orbitPulse: Bool = false
    @State private var votingHistory: [VenueVotingHistoryItem] = []
    @State private var isVotingHistoryLoading = false

    struct PromptIndex: Identifiable {
        let id: Int
    }

    private enum ProfileMode: String, CaseIterable {
        case view = "View"
        case manage = "Manage"

        var icon: String {
            switch self {
            case .view:
                return "eye.fill"
            case .manage:
                return "slider.horizontal.3"
            }
        }
    }

    private enum VerificationDisplayState: Equatable {
        case pending
        case verified
        case unverified
        case failed(reason: String)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                if session.isProfileLoading {
                    ProfileShimmerView()
                        .transition(.opacity)
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            Color.clear.frame(height: 0).trackScrollForTabBar()
                            profileHeader


                            profileModePicker
                                .padding(.horizontal, 20)
                                .padding(.top, -6)
                                .padding(.bottom, 20)
                                .zIndex(5)

                            if selectedMode == .view {
                                fullProfileView
                                    .padding(.bottom, 100)
                                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                                    .onAppear {
                                        fullProfileAppeared = false
                                        withAnimation(.spring(response: 0.55, dampingFraction: 0.8).delay(0.05)) {
                                            fullProfileAppeared = true
                                        }
                                    }
                            } else {
                                profileCompletenessStrip
                                    .padding(.horizontal, 20)
                                    .padding(.top, 4)

                                verificationCard
                                    .padding(.horizontal, 20)
                                    .padding(.top, 12)

                                statsStrip
                                    .padding(.top, 12)
                                    .padding(.horizontal, 20)

                                coinWalletCard
                                    .padding(.top, 12)
                                    .padding(.horizontal, 20)

                                if !profile.bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    bioSection.padding(.top, 24)
                                }

                                photosSection.padding(.top, 24)
                                promptsSection.padding(.top, 24)
                                interestsSection.padding(.top, 24)
                                settingsSection.padding(.top, 32).padding(.bottom, 100)
                            }
                        }
                    }
                    .coordinateSpace(name: "scrollCoord")
                    .transition(.opacity)
                }

                if showFullProfileDetail {
                    ProfileFullDetailView(profile: profile, photoStoryPage: $photoStoryPage, isPresented: $showFullProfileDetail, showActions: false)
                        .transition(
                            .asymmetric(
                                insertion: .scale(scale: 0.88, anchor: .center).combined(with: .opacity),
                                removal: .scale(scale: 0.88, anchor: .center).combined(with: .opacity)
                            )
                        )
                        .zIndex(10)
                        .ignoresSafeArea()
                }

                if showCoinShop {
                    CoinShopView(isPresented: $showCoinShop)
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .move(edge: .bottom).combined(with: .opacity)
                            )
                        )
                        .zIndex(20)
                        .ignoresSafeArea()
                }
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.82), value: showCoinShop)
            .animation(.spring(response: 0.42, dampingFraction: 0.82), value: showFullProfileDetail)
            .animation(.easeInOut(duration: 0.3), value: session.isProfileLoading)
            .animation(.spring(response: 0.35, dampingFraction: 0.86), value: selectedMode)
            .ignoresSafeArea(edges: .top)
            .navigationBarHidden(true)
            .onAppear {
                syncProfileFromSession()
                prewarmProfileImages()

                Task {
                    await session.refreshProfile()
                    await loadVotingHistory()
                }
            }
            .onChange(of: session.currentProfile) { _, newValue in
                guard let newValue, newValue != profile else { return }

                suppressNextProfileAutosave = true
                profile = newValue
                prewarmProfileImages(for: newValue)
            }
            .onChange(of: profile) { _, newValue in
                if suppressNextProfileAutosave {
                    suppressNextProfileAutosave = false
                    prewarmProfileImages(for: newValue)
                    return
                }
                guard session.currentProfile != newValue else { return }
                session.updateProfile(newValue)
                prewarmProfileImages(for: newValue)
            }
            .sheet(isPresented: $showEditSheet) {
                EditProfileView(profile: $profile)
            }
            .sheet(item: $editingPromptIndex) { i in
                if i.id < profile.prompts.count {
                    PromptEditorView(prompt: $profile.prompts[i.id])
                }
            }
            .sheet(isPresented: $showNewPromptSheet, onDismiss: {
                if !newPromptDraft.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    profile.prompts.append(newPromptDraft)
                }

                newPromptDraft = UserProfile.Prompt(question: PromptEditorView.questions[0], answer: "")
            }) {
                PromptEditorView(prompt: $newPromptDraft)
            }
            .sheet(isPresented: $showInterestPicker) {
                InterestPickerView(selected: $profile.interests)
            }
            .sheet(isPresented: $showPrivacy) {
                PrivacyView()
            }
            .sheet(isPresented: $showParticipation) {
                ParticipationView(
                    history: votingHistory,
                    isLoading: isVotingHistoryLoading,
                    onRefresh: {
                        await loadVotingHistory()
                    }
                )
            }
            .sheet(isPresented: $showHelpSupport) {
                HelpSupportView()
            }
            .sheet(isPresented: $showNotificationSettings) {
                NotificationSettingsView(notifPrefs: $profile.notificationPreferences)
            }
            .sheet(isPresented: $showPreferences) {
                PreferencesView(
                    preferences: $profile.preferences,
                    lookingFor: $profile.lookingFor,
                    isGhostMode: Binding(
                        get: { profile.isGhostMode },
                        set: { newValue in
                            guard profile.isGhostMode != newValue else { return }
                            suppressNextProfileAutosave = true
                            profile.isGhostMode = newValue
                            session.updateGhostMode(newValue)
                        }
                    )
                )
            }
            .navigationDestination(isPresented: $showVerification) {
                SelfieVerificationView(onComplete: { showVerification = false })
            }
            .alert("Delete account?", isPresented: $showDeleteAccountConfirmation) {
                Button("Cancel", role: .cancel) {}

                Button("Delete Account", role: .destructive) {
                    Task {
                        await deleteAccount()
                    }
                }
            } message: {
                Text("Your account will be deactivated now and permanently deleted after 24 hours, including your profile, check-ins, swipes, matches, messages, and sessions.")
            }
            .alert(
                "Could not delete account",
                isPresented: Binding(
                    get: { deleteAccountError != nil },
                    set: { if !$0 { deleteAccountError = nil } }
                )
            ) {
                Button("OK", role: .cancel) {
                    deleteAccountError = nil
                }
            } message: {
                Text(deleteAccountError ?? "Please try again.")
            }
            .alert(
                "Couldn't save changes",
                isPresented: Binding(
                    get: { session.profileSaveIssue != nil },
                    set: { if !$0 { session.dismissProfileSaveIssue() } }
                )
            ) {
                Button("Try Again") {
                    session.retrySync()
                }

                Button("Not Now", role: .cancel) {
                    session.dismissProfileSaveIssue()
                }
            } message: {
                Text(session.profileSaveIssue?.message ?? "Please try again.")
            }
        }
    }

    // MARK: - Header

    private var profileHeader: some View {
        VStack(spacing: 0) {
            OrbitalAvatarView(
                profile: profile,
                ringRotation: ringRotation,
                orbit1Angle: orbit1Angle,
                orbit2Angle: orbit2Angle,
                orbit3Angle: orbit3Angle,
                orbit4Angle: orbit4Angle,
                orbitPulse: orbitPulse
            )
            .padding(.top, 76)
            .padding(.bottom, 16)
            .onAppear {
                withAnimation(.linear(duration: 9).repeatForever(autoreverses: false)) {
                    ringRotation = 360
                }
                withAnimation(.linear(duration: 4.5).repeatForever(autoreverses: false)) {
                    orbit1Angle = 360
                }
                // counter-clockwise
                withAnimation(.linear(duration: 6.2).repeatForever(autoreverses: false)) {
                    orbit2Angle = -270   // 90 → -270 = one full CCW revolution
                }
                withAnimation(.linear(duration: 8.8).repeatForever(autoreverses: false)) {
                    orbit3Angle = 540   // 180 → 540 = one full CW revolution
                }
                withAnimation(.linear(duration: 3.4).repeatForever(autoreverses: false)) {
                    orbit4Angle = -90   // 270 → -90 = one full CCW revolution
                }
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                    orbitPulse = true
                }
            }

            HStack(spacing: 8) {
                Text(profile.name)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text("\(profile.age)")
                    .font(.system(size: 24, weight: .light, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))

                if profile.isVerified {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(AppTheme.primaryGradient)
                }
            }

            if let profession = cleanProfession {
                HStack(spacing: 5) {
                    Image(systemName: professionIcon)
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.purple.opacity(0.8))

                    Text(profession)
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(.white.opacity(0.55))
                }
                .padding(.top, 4)
            }

            Button(action: { openEditProfile() }) {
                HStack(spacing: 6) {
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .black))

                    Text("Edit Profile")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                }
                .foregroundStyle(AppTheme.primaryGradient)
                .padding(.horizontal, 22)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(AppTheme.pink.opacity(0.12))
                        .overlay(
                            Capsule()
                                .stroke(
                                    LinearGradient(
                                        colors: [AppTheme.pink.opacity(0.5), AppTheme.purple.opacity(0.3)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.2
                                )
                        )
                )
            }
            .buttonStyle(ScaleButtonStyle())
            .padding(.top, 14)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
        .background(meshBackground)
    }

    private var meshBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: "0D0B1E"),
                    Color(hex: "1A0D2E"),
                    Color(hex: "0D0D0F")
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            Circle()
                .fill(Color(hex: "7C3AED").opacity(0.35))
                .frame(width: 220, height: 220)
                .blur(radius: 60)
                .offset(x: -80, y: -60)

            Circle()
                .fill(AppTheme.pink.opacity(0.25))
                .frame(width: 180, height: 180)
                .blur(radius: 55)
                .offset(x: 100, y: 20)

            Circle()
                .fill(Color(hex: "C44EFF").opacity(0.18))
                .frame(width: 140, height: 140)
                .blur(radius: 40)
                .offset(x: 20, y: 80)

            Rectangle()
                .fill(Color.white.opacity(0.015))
                .blendMode(.overlay)

            LinearGradient(
                colors: [.clear, AppTheme.background],
                startPoint: .init(x: 0.5, y: 0.6),
                endPoint: .bottom
            )
        }
    }

    // MARK: - Mode Picker

    @Namespace private var pickerNamespace

    private var profileModePicker: some View {
        HStack(spacing: 0) {
            ForEach(ProfileMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        selectedMode = mode
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 12, weight: .bold))

                        Text(mode.rawValue)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(selectedMode == mode ? .white : AppTheme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background {
                        if selectedMode == mode {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(AppTheme.surfaceElevated)
                                .matchedGeometryEffect(id: "pickerSlider", in: pickerNamespace)
                                .shadow(color: .black.opacity(0.28), radius: 8, x: 0, y: 3)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.07), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 5)
    }

    // MARK: - Full Profile View

    private var fullProfileView: some View {
        VStack(alignment: .leading, spacing: 24) {
            profileHeroCard
                .opacity(fullProfileAppeared ? 1 : 0)
                .offset(y: fullProfileAppeared ? 0 : 20)
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: fullProfileAppeared)

            publicDatingIntent
                .opacity(fullProfileAppeared ? 1 : 0)
                .offset(y: fullProfileAppeared ? 0 : 24)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.10), value: fullProfileAppeared)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Hero Card (View tab)

    private var profileHeroCard: some View {
        ZStack(alignment: .bottom) {
            ProfilePhotoView(
                photo: profile.mainPhoto,
                symbolName: "person.fill",
                symbolSize: 96,
                gradientColors: [Color(hex: "111827"), Color(hex: "4A1259")],
                symbolOpacity: 0.14,
                contentMode: .fill,
                contentAlignment: .top
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            LinearGradient(
                colors: [.black.opacity(0.45), .clear],
                startPoint: .top,
                endPoint: .init(x: 0.5, y: 0.28)
            )

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Label("Public preview", systemImage: "eye.fill")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.22))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.45), lineWidth: 1))

                    if profile.isVerified {
                        Label("Verified", systemImage: "checkmark.seal.fill")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(AppTheme.green)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(AppTheme.green.opacity(0.18))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(AppTheme.green.opacity(0.65), lineWidth: 1))
                    }

                    Spacer()
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(profile.name)
                        .font(.system(size: 36, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Text("\(profile.age)")
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundColor(.white.opacity(0.72))
                }

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 16) {
                            if let profession = cleanProfession {
                                Label(profession, systemImage: professionIcon)
                                    .lineLimit(1)
                            }
                            if profile.height > 0 {
                                Label("\(profile.height) cm", systemImage: "ruler.fill")
                            }
                        }
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.82))
                    }

                    Spacer()

                    Button(action: { showFullProfileDetail = true }) {
                        ZStack {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 44, height: 44)
                                .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))

                            Image(systemName: "chevron.down")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [.clear, .black.opacity(0.28), .black.opacity(0.82)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .frame(maxWidth: .infinity)
        .frame(height: 460)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.14), AppTheme.pink.opacity(0.22), .white.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: AppTheme.pink.opacity(0.2), radius: 28, x: 0, y: 14)
    }

    private var profileCompletenessStrip: some View {
        let score = profileCompletenessScore
        let strengthLabel: String = score >= 85 ? "Excellent" : score >= 60 ? "Good" : "Getting started"
        let strengthColor: Color = score >= 85 ? AppTheme.green : score >= 60 ? AppTheme.gold : AppTheme.pink

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Label("Profile Strength", systemImage: score >= 85 ? "sparkles" : "dial.high.fill")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(AppTheme.textSecondary)

                    Text(strengthLabel)
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundColor(AppTheme.textPrimary)
                }

                Spacer()

                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.08), lineWidth: 5)
                        .frame(width: 52, height: 52)

                    Circle()
                        .trim(from: 0, to: CGFloat(score) / 100)
                        .stroke(AppTheme.primaryGradient, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .frame(width: 52, height: 52)
                        .rotationEffect(.degrees(-90))

                    Text("\(score)%")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundStyle(AppTheme.primaryGradient)
                }
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.07))

                    Capsule()
                        .fill(AppTheme.primaryGradient)
                        .frame(width: proxy.size.width * CGFloat(score) / 100)
                        .shadow(color: AppTheme.pink.opacity(0.4), radius: 6, x: 0, y: 0)
                }
            }
            .frame(height: 6)

            Text(profileCompletenessHint)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(AppTheme.textSecondary)
                .lineSpacing(2)
        }
        .padding(18)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(AppTheme.surface)

                RadialGradient(
                    colors: [strengthColor.opacity(0.1), .clear],
                    center: .topTrailing,
                    startRadius: 10,
                    endRadius: 160
                )
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(strengthColor.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Verification Card

    private var verificationCard: some View {
        let state: VerificationDisplayState
        if session.isProfileVerificationPending {
            state = .pending
        } else if profile.isVerified {
            state = .verified
        } else if let reason = profile.verificationFailureReason, reason != "spoof_detected" {
            state = .failed(reason: reason)
        } else {
            state = .unverified
        }
        return HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(verificationIconBackground(for: state))
                    .frame(width: 42, height: 42)
                Image(systemName: verificationIconName(for: state))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(verificationTitle(for: state))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
                Text(verificationSubtitle(for: state))
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(AppTheme.textSecondary)
            }

            Spacer()

            if verificationNeedsAction(state) {
                Button {
                    showVerification = true
                } label: {
                    Text("Verify")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(AppTheme.primaryGradient)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(14)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(verificationStrokeColor(for: state), lineWidth: 1)
        )
    }

    private func verificationNeedsAction(_ state: VerificationDisplayState) -> Bool {
        switch state {
        case .unverified, .failed: return true
        default: return false
        }
    }

    private func verificationIconBackground(for state: VerificationDisplayState) -> AnyShapeStyle {
        switch state {
        case .pending:
            return AnyShapeStyle(AppTheme.superLikeGradient)
        case .verified:
            return AnyShapeStyle(AppTheme.likeGradient)
        case .unverified:
            return AnyShapeStyle(AppTheme.primaryGradient)
        case .failed:
            return AnyShapeStyle(LinearGradient(colors: [AppTheme.pink, AppTheme.pink.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
    }

    private func verificationIconName(for state: VerificationDisplayState) -> String {
        switch state {
        case .pending:
            return "hourglass"
        case .verified:
            return "checkmark.shield.fill"
        case .unverified:
            return "shield.slash.fill"
        case .failed:
            return "exclamationmark.shield.fill"
        }
    }

    private func verificationTitle(for state: VerificationDisplayState) -> String {
        switch state {
        case .pending:
            return "Verification Pending"
        case .verified:
            return "Identity Verified"
        case .unverified:
            return "Not Verified"
        case .failed(let reason):
            switch reason {
            case "photo_mismatch":   return "Photos Don't Match"
            case "no_selfie":        return "Selfie Required"
            case "no_face_in_any_photo": return "No Face Detected"
            default:                 return "Verification Failed"
            }
        }
    }

    private func verificationSubtitle(for state: VerificationDisplayState) -> String {
        switch state {
        case .pending:
            return "We're reviewing your profile."
        case .verified:
            return "Your blue badge is visible to others."
        case .unverified:
            return "Verify with a selfie to get a blue badge."
        case .failed(let reason):
            switch reason {
            case "photo_mismatch":   return "Some photos didn't match your selfie — replace them or re-verify."
            case "no_selfie":        return "Take a selfie to verify your identity."
            case "no_face_in_any_photo": return "We couldn't detect a face in your photos. Try clearer ones."
            default:                 return "Something went wrong. Tap Verify to try again."
            }
        }
    }

    private func verificationStrokeColor(for state: VerificationDisplayState) -> Color {
        switch state {
        case .pending:
            return AppTheme.gold.opacity(0.35)
        case .verified:
            return AppTheme.green.opacity(0.3)
        case .unverified:
            return AppTheme.pink.opacity(0.2)
        case .failed:
            return AppTheme.pink.opacity(0.45)
        }
    }

    // MARK: - Public Bento Grid

    private var publicBentoGrid: some View {
        VStack(spacing: 10) {
            // Row 1: profession wide + height square
            HStack(spacing: 10) {
                if let profession = cleanProfession {
                    bentoCellWide(
                        icon: professionIcon,
                        label: "Job",
                        value: profession,
                        accent: AppTheme.purple,
                        delay: 0
                    )
                }

                if profile.height > 0 {
                    bentoCell(
                        icon: "ruler.fill",
                        label: "Height",
                        value: "\(profile.height)",
                        unit: "cm",
                        accent: AppTheme.green,
                        delay: 0.04
                    )
                }
            }

            // Row 2: gender square + here for wide
            HStack(spacing: 10) {
                if let gender = cleanGender {
                    bentoCell(
                        icon: "person.fill",
                        label: "Gender",
                        value: gender,
                        unit: nil,
                        accent: Color(hex: "C44EFF"),
                        delay: 0.08
                    )
                }

                if let lookingFor = cleanLookingFor {
                    bentoCellWide(
                        icon: "heart.fill",
                        label: "Here for",
                        value: lookingFor,
                        accent: AppTheme.pink,
                        delay: 0.12
                    )
                }
            }
        }
    }

    private func bentoCellWide(
        icon: String,
        label: String,
        value: String,
        accent: Color,
        delay: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .black))
                    .foregroundColor(accent)
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundColor(AppTheme.textTertiary)
                    .tracking(1.0)
            }

            Text(value)
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundColor(AppTheme.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AppTheme.surface)
                RadialGradient(
                    colors: [accent.opacity(0.15), .clear],
                    center: .topLeading,
                    startRadius: 8,
                    endRadius: 100
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(accent.opacity(0.28), lineWidth: 1)
        )
        .scaleEffect(fullProfileAppeared ? 1 : 0.9)
        .opacity(fullProfileAppeared ? 1 : 0)
        .animation(.spring(response: 0.45, dampingFraction: 0.75).delay(delay), value: fullProfileAppeared)
    }

    private func bentoCell(
        icon: String,
        label: String,
        value: String,
        unit: String?,
        accent: Color,
        delay: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .black))
                .foregroundColor(accent)

            Spacer(minLength: 4)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value)
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundColor(AppTheme.textPrimary)

                    if let unit {
                        Text(unit)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                }
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .foregroundColor(AppTheme.textTertiary)
                    .tracking(1.0)
            }
        }
        .frame(width: 100, alignment: .leading)
        .padding(14)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AppTheme.surface)
                RadialGradient(
                    colors: [accent.opacity(0.18), .clear],
                    center: .topLeading,
                    startRadius: 8,
                    endRadius: 90
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(accent.opacity(0.28), lineWidth: 1)
        )
        .scaleEffect(fullProfileAppeared ? 1 : 0.9)
        .opacity(fullProfileAppeared ? 1 : 0)
        .animation(.spring(response: 0.45, dampingFraction: 0.75).delay(delay), value: fullProfileAppeared)
    }

    private var publicBioCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            publicSectionTitle("About", icon: "quote.opening")

            Text(profile.bio)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundColor(AppTheme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(5)
        }
        .padding(18)
        .glassCard(accentColor: AppTheme.purple)
    }

    private var publicGetToKnowMe: some View {
        let promptAccents: [Color] = [AppTheme.pink, AppTheme.purple, AppTheme.green]

        return VStack(alignment: .leading, spacing: 12) {
            publicSectionTitle("Get to Know Me", icon: "text.bubble.fill")

            ForEach(Array(publicAnsweredPrompts.enumerated()), id: \.element.id) { i, prompt in
                let accent = promptAccents[i % promptAccents.count]

                HStack(alignment: .top, spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(accent.opacity(0.18))
                            .frame(width: 36, height: 36)

                        Image(systemName: "quote.opening")
                            .font(.system(size: 13, weight: .black))
                            .foregroundColor(accent)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(prompt.question)
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .foregroundColor(accent)
                            .textCase(.uppercase)
                            .tracking(0.8)

                        Text(prompt.answer)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(AppTheme.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineSpacing(3)
                    }
                }
                .padding(16)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(AppTheme.surface)
                        RadialGradient(
                            colors: [accent.opacity(0.1), .clear],
                            center: .topLeading,
                            startRadius: 10,
                            endRadius: 120
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(accent.opacity(0.22), lineWidth: 1)
                )
            }
        }
    }

    private var publicPhotoGallery: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                publicSectionTitle("Photo Story", icon: "photo.stack.fill")

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "hand.draw.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(AppTheme.textTertiary)
                    Text("Swipe")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(AppTheme.textTertiary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(AppTheme.surface)
                .clipShape(Capsule())
            }

            TabView(selection: $photoStoryPage) {
                ForEach(Array(profile.photos.enumerated()), id: \.element.id) { index, photo in
                    publicPhotoStoryCard(photo: photo, index: index)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 440)
            .compositingGroup()
            .clipShape(photoStoryCardShape)
            .background(
                photoStoryCardShape
                    .fill(AppTheme.surfaceElevated.opacity(0.92))
            )
            .overlay(
                photoStoryCardShape
                    .stroke(photoStoryBorderGradient, lineWidth: 1.25)
            )
            .shadow(color: .black.opacity(0.26), radius: 18, x: 0, y: 10)
            .shadow(color: AppTheme.pink.opacity(0.08), radius: 10, x: 0, y: 0)
            .overlay(
                photoStoryCardShape
                    .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                    .blur(radius: 1.5)
            )

            HStack(spacing: 5) {
                ForEach(0..<profile.photos.count, id: \.self) { i in
                    if i == photoStoryPage {
                        Capsule()
                            .fill(AppTheme.primaryGradient)
                            .frame(width: 22, height: 6)
                            .shadow(color: AppTheme.pink.opacity(0.55), radius: 4, x: 0, y: 0)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: photoStoryPage)
                    } else {
                        Circle()
                            .fill(Color.white.opacity(0.25))
                            .frame(width: 6, height: 6)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: photoStoryPage)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func publicPhotoStoryCard(photo: ProfilePhoto, index: Int) -> some View {
        let cardShape = photoStoryCardShape

        return ZStack(alignment: .bottom) {
            ProfilePhotoView(
                photo: photo,
                symbolName: "photo.fill",
                symbolSize: 64,
                gradientColors: [Color(hex: "121826"), Color(hex: index.isMultiple(of: 2) ? "0E4D3A" : "4A1259")],
                symbolOpacity: 0.16,
                contentMode: .fill,
                contentAlignment: .top
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(cardShape)

            LinearGradient(
                colors: [.clear, .black.opacity(0.65)],
                startPoint: .center,
                endPoint: .bottom
            )
            .clipShape(cardShape)

            HStack(alignment: .bottom) {
                if index == 0 {
                    photoSectionBadge(
                        "Main Photo",
                        systemImage: "star.fill",
                        tint: AppTheme.pink
                    )
                } else {
                    photoSectionBadge(
                        "Photo \(index + 1)",
                        tint: .white.opacity(0.18)
                    )
                }

                Spacer(minLength: 10)

                Text("\(index + 1) / \(profile.photos.count)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.72))
            }
            .padding(16)
        }
        .background(
            cardShape
                .fill(AppTheme.surfaceElevated.opacity(0.96))
        )
        .clipShape(cardShape)
    }

    private var photoStoryCardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: AppTheme.photoGridCornerRadius, style: .continuous)
    }

    private var photoStoryBorderGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.12),
                AppTheme.pink.opacity(0.22),
                AppTheme.purple.opacity(0.16),
                Color.white.opacity(0.08)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var publicInterests: some View {
        VStack(alignment: .leading, spacing: 14) {
            publicSectionTitle("Interests", icon: "sparkles")

            FlowLayout(spacing: 8) {
                ForEach(Array(profile.interests.enumerated()), id: \.element) { idx, interest in
                    interestChip(interest)
                        .opacity(fullProfileAppeared ? 1 : 0)
                        .animation(
                            .easeOut(duration: 0.4).delay(Double(idx) * 0.05),
                            value: fullProfileAppeared
                        )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(AppTheme.surface)
                RadialGradient(
                    colors: [AppTheme.purple.opacity(0.12), .clear],
                    center: .topTrailing,
                    startRadius: 20,
                    endRadius: 180
                )
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [AppTheme.purple.opacity(0.3), AppTheme.pink.opacity(0.15)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }

    private var publicDatingIntent: some View {
        VStack(alignment: .leading, spacing: 14) {
            publicSectionTitle("Discovery Preferences", icon: "slider.horizontal.3")

            HStack(spacing: 10) {
                publicPreferencePill(
                    icon: "birthday.cake.fill",
                    value: "\(profile.preferences.ageMin)-\(profile.preferences.ageMax)"
                )

                publicPreferencePill(
                    icon: "person.2.fill",
                    value: profile.preferences.genders.isEmpty ? "Everyone" : profile.preferences.genders.joined(separator: ", ")
                )
            }

            HStack(spacing: 10) {
                publicPreferencePill(
                    icon: "ruler.fill",
                    value: "\(profile.preferences.heightMin)-\(profile.preferences.heightMax) cm"
                )

                publicPreferencePill(
                    icon: "checkmark.seal.fill",
                    value: profile.preferences.verifiedOnly ? "Verified only" : "Verified optional"
                )
            }
        }
        .padding(18)
        .glassCard(accentColor: AppTheme.green)
    }

    private var publicEmptyPhotoCard: some View {
        Button(action: {
            selectedMode = .manage
            openEditProfile()
        }) {
            VStack(spacing: 10) {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryGradient)

                Text("Add more photos")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)

                Text("A fuller photo story helps your profile feel alive.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 26)
            .glassCard(accentColor: AppTheme.pink)
        }
        .buttonStyle(.plain)
    }


    private func publicPill(icon: String, title: String, tint: Color) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(tint.opacity(0.72))
            .clipShape(Capsule())
    }

    private func publicPreferencePill(icon: String, value: String) -> some View {
        Label(value, systemImage: icon)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundColor(AppTheme.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .padding(.vertical, 11)
            .background(AppTheme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func photoSectionBadge(
        _ title: String,
        systemImage: String? = nil,
        tint: Color,
        foreground: Color = .white
    ) -> some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .black))
            }

            Text(title)
                .font(.system(size: 11, weight: .black, design: .rounded))
                .tracking(0.35)
        }
        .foregroundColor(foreground)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(tint)
        .clipShape(Capsule())
    }

    private func publicSectionTitle(_ title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AppTheme.primaryGradient)

            Text(title)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundColor(AppTheme.textPrimary)
        }
    }


    // MARK: - Stats Strip

    private var statsStrip: some View {
        HStack(spacing: 10) {
            statCard(
                value: "98",
                label: "Likes",
                icon: "heart.fill",
                color: AppTheme.pink,
                gradient: LinearGradient(
                    colors: [AppTheme.pink, Color(hex: "FF4499")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )

            statCard(
                value: "\(matchesCount)",
                label: "Matches",
                icon: "checkmark.circle.fill",
                color: AppTheme.green,
                gradient: LinearGradient(
                    colors: [AppTheme.green, Color(hex: "00C8FF")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )

            statCard(
                value: "5",
                label: "Chats",
                icon: "bubble.fill",
                color: AppTheme.purple,
                gradient: LinearGradient(
                    colors: [AppTheme.purple, Color(hex: "7C3AED")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }

    private func statCard(
        value: String,
        label: String,
        icon: String,
        color: Color,
        gradient: LinearGradient
    ) -> some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.18))
                    .frame(width: 46, height: 46)

                Circle()
                    .fill(color.opacity(0.08))
                    .frame(width: 56, height: 56)
                    .blur(radius: 4)

                Image(systemName: icon)
                    .font(.system(size: 19, weight: .black))
                    .foregroundStyle(gradient)
            }

            Text(value)
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundStyle(gradient)
                .contentTransition(.numericText())

            Text(label)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(AppTheme.textSecondary)
                .textCase(.uppercase)
                .tracking(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(AppTheme.surface)

                RadialGradient(
                    colors: [color.opacity(0.12), .clear],
                    center: .top,
                    startRadius: 2,
                    endRadius: 90
                )
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [color.opacity(0.4), color.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: color.opacity(0.18), radius: 14, x: 0, y: 6)
    }

    // MARK: - Coin Wallet Card

    @State private var coinCardPulse: Bool = false

    private var coinWalletCard: some View {
        Button(action: {
            Task { await walletVM.loadWallet() }
            showCoinShop = true
        }) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(AppTheme.primaryGradient)
                        .frame(width: 50, height: 50)
                        .shadow(color: AppTheme.pink.opacity(0.45), radius: 12, x: 0, y: 4)
                        .scaleEffect(coinCardPulse ? 1.06 : 1.0)

                    CoinIcon(size: 26)
                }
                .onAppear {
                    withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                        coinCardPulse = true
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Coins")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(AppTheme.textSecondary)
                        .textCase(.uppercase)
                        .tracking(0.8)
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("\(walletVM.balance)")
                            .font(.system(size: 26, weight: .black, design: .rounded))
                            .foregroundStyle(AppTheme.primaryGradient)
                            .contentTransition(.numericText())
                        Text("available")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                }

                Spacer()

                HStack(spacing: 5) {
                    Text("Shop")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.primaryGradient)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AppTheme.primaryGradient)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(AppTheme.primaryGradient.opacity(0.1))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(AppTheme.pink.opacity(0.3), lineWidth: 1))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(AppTheme.surface)
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(AppTheme.primaryGradient.opacity(0.04))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [AppTheme.pink.opacity(0.35), AppTheme.purple.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.2
                    )
            )
            .shadow(color: AppTheme.pink.opacity(0.1), radius: 14, x: 0, y: 6)
        }
        .buttonStyle(ScaleButtonStyle())
        .task { await walletVM.loadWallet() }
    }

    // MARK: - Bio

    private var bioSection: some View {
        BioCard(bio: profile.bio)
            .padding(.horizontal, 20)
    }

    // MARK: - Photos

    private var photosSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                sectionLabel("Photos", icon: "photo.stack.fill")

                Spacer()

                Button(action: { openEditProfile() }) {
                    Text("Edit")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.primaryGradient)
                }
            }
            .padding(.horizontal, 20)

            if profile.photos.isEmpty {
                emptyPhotosCard.padding(.horizontal, 20)
            } else {
                photoHorizontalStrip
            }
        }
    }

    private let photoStripCardWidth: CGFloat = 176
    private let photoStripImageHeight: CGFloat = 214
    private let photoStripSpacing: CGFloat = 12

    private var photoHorizontalStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: photoStripSpacing) {
                ForEach(Array(profile.photos.enumerated()), id: \.element.id) { index, photo in
                    photoStripCell(photo: photo, index: index)
                }

                if profile.photos.count < 6 {
                    PhotoLibraryPickerButton(onPhotoPicked: { newPhoto in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            profile.photos.append(newPhoto)
                        }
                    }) {
                        addPhotoCell
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 4)
        }
    }

    private func photoStripCell(photo: ProfilePhoto, index: Int) -> some View {
        ZStack {
            ProfilePhotoView(
                photo: photo,
                symbolName: "photo.fill",
                symbolSize: 28,
                gradientColors: [Color(hex: "1E1B4B"), Color(hex: "7C3AED")],
                symbolOpacity: 0.2,
                contentMode: .fill,
                contentAlignment: .top
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if index == 0 {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.48)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                VStack {
                    Spacer()
                    HStack(spacing: 5) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9, weight: .black))
                        Text("Cover")
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .tracking(0.3)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(.bottom, 10)
                }
                .frame(maxWidth: .infinity)
            }

            profilePhotoUploadOverlay(for: photo)
        }
        .frame(width: photoStripCardWidth, height: photoStripImageHeight)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppTheme.surfaceElevated)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    index == 0
                        ? LinearGradient(colors: [AppTheme.pink.opacity(0.6), AppTheme.purple.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        : LinearGradient(colors: [Color.white.opacity(0.08), Color.white.opacity(0.08)], startPoint: .top, endPoint: .bottom),
                    lineWidth: index == 0 ? 1.5 : 1
                )
        )
        .shadow(color: index == 0 ? AppTheme.pink.opacity(0.2) : .black.opacity(0.15), radius: index == 0 ? 12 : 6, x: 0, y: 4)
    }

    @ViewBuilder
    private func profilePhotoUploadOverlay(for photo: ProfilePhoto) -> some View {
        if session.uploadingProfilePhotoIDs.contains(photo.id) {
            ZStack {
                Color.black.opacity(0.58)

                VStack(spacing: 8) {
                    ProgressView()
                        .tint(.white)

                    Text("Uploading")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
            }
        } else if session.failedProfilePhotoIDs.contains(photo.id) {
            Button {
                session.retrySync()
            } label: {
                ZStack {
                    Color.black.opacity(0.68)

                    VStack(spacing: 7) {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(AppTheme.gold)

                        Text("Upload failed")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(.white)

                        Text("Tap to retry")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.72))
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var addPhotoCell: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(AppTheme.pink.opacity(0.12))
                    .frame(width: 46, height: 46)

                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(AppTheme.primaryGradient)
            }

            Text("Add Photo")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(AppTheme.textSecondary)
        }
        .frame(width: photoStripCardWidth, height: photoStripImageHeight)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    AppTheme.pink.opacity(0.22),
                    style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                )
        )
    }

    private var emptyPhotosCard: some View {
        PhotoLibraryPickerButton(onPhotoPicked: replaceMainPhoto) {
            VStack(spacing: 12) {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(AppTheme.primaryGradient)

                Text("Add your first photo")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)

                Text("Show people who you really are")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(AppTheme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(
                        AppTheme.pink.opacity(0.2),
                        style: StrokeStyle(lineWidth: 1.5, dash: [6])
                    )
            )
        }
    }

    // MARK: - Prompts

    private var promptsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionLabel("Get to Know Me", icon: "text.bubble.fill")

                Spacer()

                if profile.prompts.count < 3 {
                    Button(action: {
                        newPromptDraft = UserProfile.Prompt(question: PromptEditorView.questions[0], answer: "")
                        showNewPromptSheet = true
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .bold))

                            Text("Add")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(AppTheme.primaryGradient)
                    }
                }
            }

            if profile.prompts.isEmpty {
                Button(action: {
                    newPromptDraft = UserProfile.Prompt(question: PromptEditorView.questions[0], answer: "")
                    showNewPromptSheet = true
                }) {
                    VStack(spacing: 8) {
                        Image(systemName: "text.bubble.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(AppTheme.primaryGradient)

                        Text("Answer a prompt")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(AppTheme.textPrimary)

                        Text("Give people an easy way to start a conversation.")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(AppTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .background(AppTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(AppTheme.purple.opacity(0.25), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    )
                }
                .buttonStyle(.plain)
            } else {
                ForEach(Array(profile.prompts.enumerated()), id: \.element.id) { index, prompt in
                    promptCard(prompt: prompt, index: index)
                }
            }
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private func promptCard(prompt: UserProfile.Prompt, index: Int) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text("\u{201C}")
                .font(.system(size: 52, weight: .black, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            AppTheme.pink.opacity(0.6),
                            AppTheme.purple.opacity(0.4)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .offset(y: -8)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 8) {
                Text(prompt.question)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.pink)
                    .textCase(.uppercase)
                    .tracking(0.8)

                Text(prompt.answer.isEmpty ? "Tap to answer..." : prompt.answer)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(prompt.answer.isEmpty ? AppTheme.textTertiary : AppTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(3)
            }
            .padding(.top, 6)

            Spacer()

            VStack(spacing: 14) {
                Button(action: { editingPromptIndex = PromptIndex(id: index) }) {
                    Image(systemName: "pencil")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.textTertiary)
                }
                .buttonStyle(.plain)

                Button(action: {
                    let i = index

                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        profile.prompts.remove(at: i)
                    }
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.red.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 8)
        }
        .padding(.leading, 4)
        .padding(.trailing, 16)
        .padding(.vertical, 14)
        .glassCard(accentColor: AppTheme.purple.opacity(0.6))
    }

    // MARK: - Interests

    private var interestsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                sectionLabel("Interests", icon: "sparkles")

                Spacer()

                Button(action: { showInterestPicker = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "pencil")
                            .font(.system(size: 11, weight: .bold))

                        Text("Edit")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(AppTheme.primaryGradient)
                }
            }

            FlowLayout(spacing: 8) {
                ForEach(profile.interests, id: \.self) { interest in
                    interestChip(interest)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
    }

    private func interestChip(_ interest: String) -> some View {
        let chipColors: [(Color, Color)] = [
            (AppTheme.pink, AppTheme.purple),
            (AppTheme.purple, Color(hex: "C44EFF")),
            (AppTheme.green, Color(hex: "00C8FF")),
            (Color(hex: "C44EFF"), AppTheme.pink),
        ]
        let colorPair = chipColors[abs(interest.hashValue) % chipColors.count]

        return Label(interest, systemImage: interestIcon(interest))
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(
                LinearGradient(
                    colors: [colorPair.0, colorPair.1],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(colorPair.0.opacity(0.1))
                    .overlay(
                        Capsule()
                            .stroke(colorPair.0.opacity(0.3), lineWidth: 1)
                    )
            )
    }

    private func loadVotingHistory() async {
        guard !isVotingHistoryLoading else { return }
        isVotingHistoryLoading = true
        defer { isVotingHistoryLoading = false }

        do {
            let response = try await NetworkClient.shared.venueVotingHistory()
            votingHistory = response.history.map(\.historyItem)
        } catch {
            votingHistory = []
        }
    }

    // MARK: - Settings

    private var settingsSection: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                settingsRow(
                    icon: "bell.fill",
                    label: "Notifications",
                    color: AppTheme.purple,
                    action: { showNotificationSettings = true }
                )

                Divider()
                    .background(Color.white.opacity(0.06))
                    .padding(.leading, 60)

                settingsRow(
                    icon: "slider.horizontal.3",
                    label: "Dating Preferences",
                    color: AppTheme.green,
                    action: { showPreferences = true }
                )

                Divider()
                    .background(Color.white.opacity(0.06))
                    .padding(.leading, 60)

                settingsRow(
                    icon: "trophy.fill",
                    label: "Participation",
                    color: AppTheme.gold,
                    action: { showParticipation = true }
                )

                Divider()
                    .background(Color.white.opacity(0.06))
                    .padding(.leading, 60)

                settingsRow(
                    icon: "lock.fill",
                    label: "Privacy",
                    color: AppTheme.pink,
                    action: { showPrivacy = true }
                )

                Divider()
                    .background(Color.white.opacity(0.06))
                    .padding(.leading, 60)

                settingsRow(
                    icon: "questionmark.circle.fill",
                    label: "Help & Support",
                    color: AppTheme.purple,
                    action: { showHelpSupport = true }
                )
            }
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(AppTheme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.white.opacity(0.05), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 20)

            VStack(spacing: 0) {
                Button(action: { session.signOut() }) {
                    HStack(spacing: 14) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 15))
                            .foregroundColor(AppTheme.red)
                            .frame(width: 36, height: 36)
                            .background(AppTheme.red.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                        Text("Sign Out")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundColor(AppTheme.red)

                        Spacer()
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                }

                Divider()
                    .background(Color.white.opacity(0.06))
                    .padding(.leading, 68)

                Button(action: { showDeleteAccountConfirmation = true }) {
                    HStack(spacing: 14) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 15))
                            .foregroundColor(AppTheme.red)
                            .frame(width: 36, height: 36)
                            .background(AppTheme.red.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Delete Account")
                                .font(.system(size: 16, weight: .medium, design: .rounded))
                                .foregroundColor(AppTheme.red)

                            Text("Permanently removed after 24 h")
                                .font(.system(size: 11, design: .rounded))
                                .foregroundColor(AppTheme.textTertiary)
                        }

                        Spacer()

                        if isDeletingAccount {
                            ProgressView()
                                .tint(AppTheme.red)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                }
                .disabled(isDeletingAccount)
            }
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(AppTheme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(AppTheme.red.opacity(0.12), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
    }

    private func settingsRow(
        icon: String,
        label: String,
        color: Color,
        action: (() -> Void)? = nil
    ) -> some View {
        Button(action: { action?() }) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(color.opacity(0.15))
                        .frame(width: 38, height: 38)
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.22), color.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 38, height: 38)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(color)
                }

                Text(label)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [color.opacity(0.7), AppTheme.textTertiary],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
        .buttonStyle(SettingsRowButtonStyle())
    }

    // MARK: - Cleaned Profile Values

    private var cleanProfession: String? {
        cleanProfileValue(
            profile.profession,
            invalidValues: [
                "other",
                "others",
                "na",
                "n/a",
                "none",
                "null",
                "nil",
                "prefer not to say",
                "not specified",
                "unknown",
                "-"
            ]
        )
    }

    private var cleanLookingFor: String? {
        cleanProfileValue(
            profile.lookingFor,
            invalidValues: [
                "na",
                "n/a",
                "none",
                "null",
                "nil",
                "prefer not to say",
                "not specified",
                "unknown",
                "-"
            ]
        )
    }

    private var cleanGender: String? {
        cleanProfileValue(
            profile.gender,
            invalidValues: [
                "na",
                "n/a",
                "none",
                "null",
                "nil",
                "prefer not to say",
                "not specified",
                "unknown",
                "-"
            ]
        )
    }

    private var publicAnsweredPrompts: [UserProfile.Prompt] {
        profile.prompts.filter {
            !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func cleanProfileValue(_ value: String, invalidValues: Set<String>) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return nil
        }

        guard !invalidValues.contains(trimmed.lowercased()) else {
            return nil
        }

        return trimmed
    }

    private var professionIcon: String {
        let profession = cleanProfession?.lowercased() ?? ""

        if profession.contains("chef") {
            return "fork.knife"
        }

        if profession.contains("architect") {
            return "building.2.fill"
        }

        if profession.contains("doctor") {
            return "cross.case.fill"
        }

        if profession.contains("engineer") {
            return "hammer.fill"
        }

        if profession.contains("artist") {
            return "paintpalette.fill"
        }

        if profession.contains("designer") {
            return "pencil.and.outline"
        }

        if profession.contains("teacher") {
            return "book.fill"
        }

        if profession.contains("student") {
            return "graduationcap.fill"
        }

        return "briefcase.fill"
    }

    // MARK: - Helpers

    private func sectionLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.primaryGradient)

            Text(title)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(AppTheme.textPrimary)
        }
    }

    private func replaceMainPhoto(_ newPhoto: ProfilePhoto) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            if profile.photos.isEmpty {
                profile.photos = [newPhoto]
            } else {
                profile.photos[0] = newPhoto
            }
        }
    }

    private func interestIcon(_ interest: String) -> String {
        switch interest {
        case "Baking":
            return "birthday.cake"
        case "Code":
            return "laptopcomputer"
        case "Hiking":
            return "figure.hiking"
        case "Concerts":
            return "music.note"
        case "Coffee":
            return "cup.and.saucer.fill"
        case "Vinyl":
            return "opticaldisc"
        case "Travel":
            return "airplane"
        case "Cooking":
            return "fork.knife"
        case "Yoga":
            return "figure.yoga"
        case "Books":
            return "books.vertical.fill"
        case "Surfing":
            return "figure.surfing"
        case "Dogs":
            return "pawprint.fill"
        case "Photography":
            return "camera.fill"
        case "Guitar":
            return "guitars.fill"
        case "Writing":
            return "pencil"
        case "Farmers Markets":
            return "leaf.fill"
        case "Wine":
            return "wineglass.fill"
        default:
            return "star.fill"
        }
    }

    private func syncProfileFromSession() {
        guard let currentProfile = session.currentProfile else { return }
        suppressNextProfileAutosave = true
        profile = currentProfile
    }

    private func openEditProfile() {
        prewarmProfileImages()
        showEditSheet = true
    }

    private func prewarmProfileImages(for profile: UserProfile? = nil) {
        let profile = profile ?? self.profile
        let urls = profile.photos.compactMap(\.remoteURL)

        guard !urls.isEmpty else {
            return
        }

        Task { @MainActor in
            ProfileImageCache.shared.prefetch(urls: urls)
        }
    }

    private func deleteAccount() async {
        guard !isDeletingAccount else { return }

        isDeletingAccount = true

        let didDelete = await session.deleteAccount()

        if !didDelete {
            deleteAccountError = session.authErrorMessage ?? "Please try again."
        }

        isDeletingAccount = false
    }

    private var profileCompletenessScore: Int {
        var score = 20

        if !profile.bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            score += 15
        }

        score += min(profile.photos.count, 6) * 6

        score += min(
            profile.prompts.filter {
                !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }.count,
            3
        ) * 8

        if !profile.interests.isEmpty {
            score += min(profile.interests.count, 6) * 3
        }

        if cleanProfession != nil {
            score += 5
        }

        if cleanLookingFor != nil {
            score += 4
        }

        if profile.isVerified {
            score += 6
        }

        return min(score, 100)
    }

    private var profileCompletenessHint: String {
        if profile.photos.count < 3 {
            return "Add at least three photos so viewers can understand your vibe faster."
        }

        if profile.prompts.filter({ !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }).count < 2 {
            return "Answer another prompt to give people an easy way to start a chat."
        }

        if profile.interests.count < 4 {
            return "Add a few more interests to make your profile easier to connect with."
        }

        return "Your profile has enough detail for a strong first impression."
    }

    private var hasRealProfilePhotos: Bool {
        profile.photos.count >= 2
    }
}

// MARK: - Bio card with rotating border

private struct BioCard: View {
    let bio: String
    @State private var rotation: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "quote.opening")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryGradient)

                Text("About")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
            }

            Text(bio)
                .font(.system(size: 15, design: .rounded))
                .foregroundColor(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(AppTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(
                    AngularGradient(
                        colors: [
                            AppTheme.pink,
                            AppTheme.purple,
                            Color(hex: "C44EFF"),
                            AppTheme.pink.opacity(0.2),
                            AppTheme.pink
                        ],
                        center: .center,
                        startAngle: .degrees(rotation),
                        endAngle: .degrees(rotation + 360)
                    ),
                    lineWidth: 1.5
                )
        )
        .onAppear {
            withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}

// MARK: - Glass card modifier

private struct GlassCardModifier: ViewModifier {
    let accentColor: Color

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(AppTheme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(accentColor.opacity(0.22), lineWidth: 1)
                    )
            )
    }
}

extension View {
    func glassCard(accentColor: Color) -> some View {
        modifier(GlassCardModifier(accentColor: accentColor))
    }
}

// MARK: - Orbital Avatar

private struct OrbitalAvatarView: View {
    let profile: UserProfile
    let ringRotation: Double
    let orbit1Angle: Double
    let orbit2Angle: Double
    let orbit3Angle: Double
    let orbit4Angle: Double
    let orbitPulse: Bool

    // Ring radii
    private let r1: CGFloat = 66
    private let r2: CGFloat = 82
    private let r3: CGFloat = 96
    private let r4: CGFloat = 110

    var body: some View {
        ZStack {
            // Pulsing outer halo — pink + purple dual glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [AppTheme.pink.opacity(orbitPulse ? 0.30 : 0.14), .clear],
                        center: .center,
                        startRadius: 30,
                        endRadius: 120
                    )
                )
                .frame(width: 260, height: 260)
                .blur(radius: 10)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [AppTheme.purple.opacity(orbitPulse ? 0.22 : 0.10), .clear],
                        center: .center,
                        startRadius: 50,
                        endRadius: 140
                    )
                )
                .frame(width: 300, height: 300)
                .blur(radius: 12)

            // Ring 4 — outermost, violet, dashed, thick
            Circle()
                .stroke(
                    AngularGradient(
                        colors: [
                            Color(hex: "C44EFF").opacity(0.6),
                            Color(hex: "C44EFF").opacity(0.15),
                            Color(hex: "C44EFF").opacity(0.55),
                            Color(hex: "C44EFF").opacity(0.1),
                            Color(hex: "C44EFF").opacity(0.6)
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 1.5, dash: [4, 6])
                )
                .frame(width: r4 * 2, height: r4 * 2)
                .rotationEffect(.degrees(ringRotation * 0.4))

            // Ring 3 — green, dashed
            Circle()
                .stroke(
                    AngularGradient(
                        colors: [
                            AppTheme.green.opacity(0.65),
                            AppTheme.green.opacity(0.12),
                            AppTheme.green.opacity(0.55),
                            AppTheme.green.opacity(0.08),
                            AppTheme.green.opacity(0.65)
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 1.5, dash: [5, 7])
                )
                .frame(width: r3 * 2, height: r3 * 2)
                .rotationEffect(.degrees(-ringRotation * 0.3))

            // Ring 2 — purple, dashed
            Circle()
                .stroke(
                    AngularGradient(
                        colors: [
                            AppTheme.purple.opacity(0.70),
                            AppTheme.purple.opacity(0.15),
                            AppTheme.purple.opacity(0.60),
                            AppTheme.purple.opacity(0.10),
                            AppTheme.purple.opacity(0.70)
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])
                )
                .frame(width: r2 * 2, height: r2 * 2)
                .rotationEffect(.degrees(ringRotation * 0.5))

            // Ring 1 — innermost, solid conic, glowing
            Circle()
                .stroke(
                    AngularGradient(
                        colors: [
                            AppTheme.pink,
                            AppTheme.purple,
                            Color(hex: "C44EFF"),
                            AppTheme.green,
                            AppTheme.pink.opacity(0.4),
                            AppTheme.pink
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                )
                .frame(width: r1 * 2, height: r1 * 2)
                .rotationEffect(.degrees(ringRotation))
                .blur(radius: 0.5)
                .shadow(color: AppTheme.pink.opacity(0.6), radius: 4, x: 0, y: 0)

            // Orbit ball 4 — violet, outermost
            orbitBall(
                radius: r4,
                angle: orbit4Angle,
                color: Color(hex: "C44EFF"),
                size: 10,
                glowColor: Color(hex: "C44EFF"),
                spinAngle: orbit4Angle * 4
            )

            // Orbit ball 3 — green
            orbitBall(
                radius: r3,
                angle: orbit3Angle,
                color: AppTheme.green,
                size: 9,
                glowColor: AppTheme.green,
                spinAngle: orbit3Angle * 3
            )

            // Orbit ball 2 — purple, CCW
            orbitBall(
                radius: r2,
                angle: orbit2Angle,
                color: AppTheme.purple,
                size: 11,
                glowColor: AppTheme.purple,
                spinAngle: orbit2Angle * 5
            )

            // Orbit ball 1 — pink, fastest
            orbitBall(
                radius: r1,
                angle: orbit1Angle,
                color: AppTheme.pink,
                size: 12,
                glowColor: AppTheme.pink,
                spinAngle: orbit1Angle * 6
            )

            // Avatar
            ProfileAvatar(profile: profile, size: 112)
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.25), Color.white.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )
                .shadow(color: AppTheme.pink.opacity(orbitPulse ? 0.55 : 0.28), radius: 20, x: 0, y: 0)
        }
        .frame(width: (r4 + 16) * 2, height: (r4 + 16) * 2)
    }

    private func orbitBall(
        radius: CGFloat,
        angle: Double,
        color: Color,
        size: CGFloat,
        glowColor: Color,
        spinAngle: Double
    ) -> some View {
        let radians = angle * Double.pi / 180.0
        let x = CGFloat(cos(radians)) * radius
        let y = CGFloat(sin(radians)) * radius

        // Comet tail — 3 fading blobs trailing behind the ball
        let tailRadians1 = (angle - 18) * Double.pi / 180.0
        let tailRadians2 = (angle - 34) * Double.pi / 180.0
        let tx1 = CGFloat(cos(tailRadians1)) * radius
        let ty1 = CGFloat(sin(tailRadians1)) * radius
        let tx2 = CGFloat(cos(tailRadians2)) * radius
        let ty2 = CGFloat(sin(tailRadians2)) * radius

        return ZStack {
            // Tail segment 2 (furthest)
            Circle()
                .fill(glowColor.opacity(0.20))
                .frame(width: size * 0.45, height: size * 0.45)
                .blur(radius: 2)
                .offset(x: tx2, y: ty2)

            // Tail segment 1
            Circle()
                .fill(glowColor.opacity(0.35))
                .frame(width: size * 0.65, height: size * 0.65)
                .blur(radius: 1.5)
                .offset(x: tx1, y: ty1)

            // Outer glow
            Circle()
                .fill(glowColor.opacity(0.55))
                .frame(width: size + 8, height: size + 8)
                .blur(radius: 5)
                .offset(x: x, y: y)

            // Ball body — gradient so spin is visible
            Circle()
                .fill(
                    AngularGradient(
                        colors: [
                            color,
                            Color.white.opacity(0.9),
                            color.opacity(0.5),
                            color,
                            color
                        ],
                        center: .center,
                        startAngle: .degrees(spinAngle),
                        endAngle: .degrees(spinAngle + 360)
                    )
                )
                .frame(width: size, height: size)
                // Specular glint on top
                .overlay(
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.white.opacity(0.85), .clear],
                                center: UnitPoint(x: 0.3, y: 0.25),
                                startRadius: 0,
                                endRadius: size * 0.5
                            )
                        )
                )
                .offset(x: x, y: y)
        }
    }
}

private struct ParticipationView: View {
    let history: [VenueVotingHistoryItem]
    let isLoading: Bool
    let onRefresh: () async -> Void
    @Environment(\.dismiss) private var dismiss
    private let glassStroke = Color.white.opacity(0.06)
    private let glassHighlight = Color.white.opacity(0.05)
    private let glassFill = Color.white.opacity(0.04)

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "0A0A0F").ignoresSafeArea()
                ambientGlow

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        statsGrid
                        recentActivity
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 34)
                }
                .refreshable {
                    await onRefresh()
                }
            }
            .navigationTitle("Participation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                    }
                }
            }
            .task {
                await onRefresh()
            }
        }
    }

    private var ambientGlow: some View {
        GeometryReader { proxy in
            ZStack {
                RadialGradient(
                    colors: [Color(hex: "EC4899").opacity(0.15), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: 150
                )
                .frame(width: 300, height: 300)
                .position(x: 34, y: 18)

                RadialGradient(
                    colors: [Color(hex: "8B5CF6").opacity(0.12), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: 125
                )
                .frame(width: 250, height: 250)
                .position(x: proxy.size.width - 34, y: proxy.size.height - 40)
            }
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("My Voting")
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundColor(AppTheme.textPrimary)

            Text("Your voting history & stats")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(AppTheme.textSecondary)
        }
    }

    private var statsGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ],
            spacing: 12
        ) {
            statTile(value: "\(totalVotes)", label: "Total Votes", color: AppTheme.pink)
            statTile(value: currencyText(cents: totalWonCents), label: "Total Won", color: AppTheme.gold)
            statTile(value: "\(wins)", label: "Wins", color: AppTheme.green)
            statTile(value: "\(participated)", label: "Participated", color: AppTheme.textPrimary)
        }
    }

    private var recentActivity: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RECENT ACTIVITY")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(Color.white.opacity(0.4))
                .tracking(1)

            if isLoading && history.isEmpty {
                activityPlaceholder("Loading voting activity", showsSpinner: true)
            } else if recentHistory.isEmpty {
                activityPlaceholder("Your weekend voting activity will appear here after you join or vote.")
            } else {
                ForEach(recentHistory) { item in
                    activityRow(item)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.03))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(glassStroke, lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.24), radius: 28, x: 0, y: 14)
    }

    private func statTile(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Text(value)
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(Color.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 104)
        .background(glassSurface(cornerRadius: 20, fillOpacity: 0.04, materialOpacity: 0.35))
        .shadow(color: .black.opacity(0.2), radius: 32, x: 0, y: 8)
    }

    private func activityPlaceholder(_ text: String, showsSpinner: Bool = false) -> some View {
        HStack(spacing: 10) {
            if showsSpinner {
                ProgressView()
                    .tint(AppTheme.pink)
            }
            Text(text)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(glassSurface(cornerRadius: 16, fillOpacity: 0.04, materialOpacity: 0.25))
    }

    private func activityRow(_ item: VenueVotingHistoryItem) -> some View {
        HStack(spacing: 12) {
            activityThumbnail(for: item)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.venueName)
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
                    .lineLimit(1)

                Text("\(activityDate(item.endedAt)) • \(item.category.title) competition")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(AppTheme.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 4) {
                    Text(item.userWon ? "WON" : "LOST")
                    if item.userWon {
                        Image(systemName: "trophy.fill")
                    }
                }
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundColor(item.userWon ? AppTheme.gold : AppTheme.textSecondary)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(item.userWon ? AppTheme.gold.opacity(0.15) : AppTheme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                Text(item.userWon ? "+\(currencyText(cents: item.prizeAmountCents))" : "-₹220")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundColor(item.userWon ? AppTheme.gold : AppTheme.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(glassFill)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(glassStroke, lineWidth: 1)
                )
                .overlay(alignment: .leading) {
                    LinearGradient(
                        colors: item.userWon
                            ? [Color(hex: "FFC107"), Color(hex: "FF9800")]
                            : [Color(hex: "FF453A"), Color(hex: "FF6B6B")],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(width: 3)
                }
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.22), radius: 18, x: 0, y: 8)
    }

    private func activityThumbnail(for item: VenueVotingHistoryItem) -> some View {
        ZStack {
            LinearGradient(
                colors: activityGradient(for: item.category),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: item.userWon ? "crown.fill" : "ticket.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(item.userWon ? AppTheme.gold : .white.opacity(0.86))
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: AppTheme.purple.opacity(0.18), radius: 12, x: 0, y: 6)
    }

    private func glassSurface(cornerRadius: CGFloat, fillOpacity: Double, materialOpacity: Double) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.white.opacity(fillOpacity))
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .opacity(materialOpacity)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(glassStroke, lineWidth: 1)
            )
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(glassHighlight, lineWidth: 1)
                    .blendMode(.screen)
            }
    }

    private func activityGradient(for category: VenueVotingCategory) -> [Color] {
        switch category {
        case .male:
            return [Color(hex: "2563EB"), Color(hex: "06B6D4")]
        case .female:
            return [AppTheme.pink, AppTheme.purple]
        case .lgbtq:
            return [Color(hex: "F97316"), AppTheme.purple]
        }
    }

    private var recentHistory: [VenueVotingHistoryItem] {
        history.sorted { $0.endedAt > $1.endedAt }.prefix(10).map { $0 }
    }

    private var totalVotes: Int {
        history.reduce(0) { $0 + $1.votesReceived }
    }

    private var totalWonCents: Int {
        history.reduce(0) { $0 + ($1.userWon ? $1.prizeAmountCents : 0) }
    }

    private var wins: Int {
        history.filter(\.userWon).count
    }

    private var participated: Int {
        history.filter { $0.userJoined || $0.votesCast > 0 || $0.votesReceived > 0 }.count
    }

    private func currencyText(cents: Int) -> String {
        let rupees = cents / 100
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return "₹\(formatter.string(from: NSNumber(value: rupees)) ?? "\(rupees)")"
    }

    private func activityDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

// MARK: - Button Styles

private struct SettingsRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

private struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.65), value: configuration.isPressed)
    }
}
