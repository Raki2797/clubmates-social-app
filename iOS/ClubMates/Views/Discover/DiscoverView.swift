import SwiftUI

struct DiscoverView: View {
    @ObservedObject var matchesViewModel: MatchesViewModel
    let onOpenMatchChat: (Match) -> Void

    @Environment(\.openURL) private var openURL
    @StateObject private var viewModel = DiscoverViewModel()
    @EnvironmentObject var walletVM: WalletViewModel
    @State private var showVenuePicker = false
    @State private var votingVenue: Venue?
    @State private var showSOSConfirmation = false
    @State private var showCheckOutConfirmation = false
    @State private var inviteProfile: UserProfile?
    @State private var showHereNowDetail = false
    @State private var hereNowDetailProfile: UserProfile? = nil
    @State private var hereNowDetailPhotoPage = 0
    @State private var showCoinShopFromInvite = false

    var body: some View {
        ZStack {
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
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 14)

                if viewModel.isCheckedIn {
//                    rosterSection
//                        .padding(.horizontal, 20)
//                        .padding(.bottom, 14)

                    if let currentProfile = viewModel.currentProfile {
                        let hasNext = viewModel.nextProfile != nil
                        let peekOffset: CGFloat = 60

                        ZStack(alignment: .top) {
                            // Back card — top ~20% visible, scaled in slightly
                            if let nextProfile = viewModel.nextProfile {
                                hereNowCard(for: nextProfile)
                                    .padding(.horizontal, 28)
                                    .scaleEffect(x: 0.96, y: 1.0, anchor: .top)
                                    .opacity(0.55)
                                    .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 6)
                                    .allowsHitTesting(false)
                            }

                            // Front card — floats above with a strong lift shadow
                            hereNowCard(for: currentProfile)
                                .padding(.horizontal, 16)
                                .offset(y: hasNext ? peekOffset : 0)
                                .scaleEffect(viewModel.isTransitioning ? 0.96 : 1.0, anchor: .top)
                                .opacity(viewModel.isTransitioning ? 0.7 : 1.0)
                                .shadow(color: .black.opacity(0.55), radius: 28, x: 0, y: 14)
                        }
                        .padding(.bottom, hasNext ? peekOffset : 0)
                    } else {
                        cardStack
                        Spacer(minLength: 0)
                    }

                    Spacer(minLength: 0)
                } else {
                    checkInEntry
                        .padding(.horizontal, 20)
                        .padding(.top, 14)
                    Spacer(minLength: 0)
                }
            }

            if showHereNowDetail, let profile = hereNowDetailProfile {
                ProfileFullDetailView(
                    profile: profile,
                    photoStoryPage: $hereNowDetailPhotoPage,
                    isPresented: $showHereNowDetail,
                    onPass: { viewModel.swipe(.nope) },
                    onLike: { viewModel.swipe(.like) },
                    onGift: { inviteProfile = profile }
                )
                .sheet(item: $inviteProfile) { invitee in
                    TreatInviteSheet(profile: invitee, walletVM: walletVM, onSelect: { treat in
                        viewModel.sendInvite(to: invitee, treat: treat, walletVM: walletVM)
                        inviteProfile = nil
                    }, onGetMoreCoins: {
                        inviteProfile = nil
                        showCoinShopFromInvite = true
                    })
                    .presentationDetents([.large])
                    .presentationDragIndicator(.hidden)
                    .presentationCornerRadius(28)
                }
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.88, anchor: .center).combined(with: .opacity),
                        removal: .scale(scale: 0.88, anchor: .center).combined(with: .opacity)
                    )
                )
                .zIndex(10)
                .ignoresSafeArea()
            }

            if let matched = activeMatchAlertProfile {
                MatchAlertView(
                    profile: matched,
                    onKeepSwiping: dismissActiveMatchAlert,
                    onSendMessage: { openChat(for: matched) }
                )
                .transition(.opacity)
                .zIndex(100)
            }

            if showCheckOutConfirmation {
                checkOutOverlay
                    .transition(.opacity)
                    .zIndex(200)
            }

            if showSOSConfirmation {
                sosOverlay
                    .transition(.opacity)
                    .zIndex(300)
            }

            if viewModel.sosError != nil {
                sosErrorOverlay
                    .transition(.opacity)
                    .zIndex(300)
            }

            if showCoinShopFromInvite {
                CoinShopView(isPresented: $showCoinShopFromInvite)
                    .environmentObject(walletVM)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .bottom).combined(with: .opacity)
                        )
                    )
                    .zIndex(400)
                    .ignoresSafeArea()
            }

        }
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: showCoinShopFromInvite)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showCheckOutConfirmation)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showSOSConfirmation)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.sosError)
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: showHereNowDetail)
        .sheet(isPresented: $showVenuePicker) {
            VenuePickerSheet(
                options: viewModel.selectedCityVenueOptions,
                cities: viewModel.availableCities,
                selectedCity: viewModel.selectedCity,
                activeVenueID: viewModel.activeVenue?.id,
                onSelectCity: { city in
                    viewModel.selectCity(city)
                },
                onSelectVenue: { venue in
                    viewModel.checkIn(to: venue)
                    showVenuePicker = false
                },
                onOpenVoting: { venue in
                    votingVenue = venue
                    showVenuePicker = false
                },
                onCheckOut: {
                    viewModel.checkOut()
                    showVenuePicker = false
                }
            )
        }
        .onChange(of: showVenuePicker) { _, isPresented in
            if isPresented {
                viewModel.refreshVenuesForPicker()
            }
        }
        .sheet(item: $viewModel.selectedRosterProfile) { profile in
            RosterProfileSheet(profile: profile)
        }
        .sheet(item: $votingVenue) { venue in
            VenueVotingView(venue: venue)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $inviteProfile) { profile in
            TreatInviteSheet(profile: profile, walletVM: walletVM, onSelect: { treat in
                viewModel.sendInvite(to: profile, treat: treat, walletVM: walletVM)
                inviteProfile = nil
            }, onGetMoreCoins: {
                inviteProfile = nil
                showCoinShopFromInvite = true
            })
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(28)
        }
        .alert(
            "Invite not sent",
            isPresented: Binding(
                get: { viewModel.inviteError != nil },
                set: { if !$0 { viewModel.inviteError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                viewModel.inviteError = nil
            }
        } message: {
            Text(viewModel.inviteError ?? "Please try again.")
        }
        .onAppear {
            viewModel.excludeMatchedProfiles(matchesViewModel.confirmedMatchProfileIDs)
            viewModel.refreshSafetyFilters()
            viewModel.onInsufficientCoins = { showCoinShopFromInvite = true }
        }
        .onChange(of: matchesViewModel.confirmedMatchProfileIDs) { _, profileIDs in
            viewModel.excludeMatchedProfiles(profileIDs)
        }
    }

    private var activeMatchAlertProfile: UserProfile? {
        viewModel.showMatchAlert ? viewModel.lastMatchedProfile : nil
    }

    private var activeMatchAlertMatchID: UUID? {
        viewModel.showMatchAlert ? viewModel.lastMatchedMatchID : nil
    }

    private func dismissActiveMatchAlert() {
        if viewModel.showMatchAlert {
            viewModel.showMatchAlert = false
            viewModel.lastMatchedProfile = nil
            viewModel.lastMatchedMatchID = nil
        }
    }

    private func openChat(for profile: UserProfile) {
        let match = matchesViewModel.matches.first(where: { $0.profile.id == profile.id })
            ?? matchesViewModel.addMatch(
                for: profile,
                matchId: activeMatchAlertMatchID,
                venueId: viewModel.activeVenue?.id,
                venueName: viewModel.activeVenue?.name
            )
        dismissActiveMatchAlert()
        onOpenMatchChat(match)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                if let venue = viewModel.activeVenue {
                    Text(venue.name)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(AppTheme.textPrimary)
                        .lineLimit(1)
                } else {
                    Text("Venue Discovery")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(AppTheme.textPrimary)
                }

                Spacer()

                HStack(spacing: 8) {
                    if viewModel.isCheckedIn {
                        headerButton(icon: "arrow.uturn.left", isEnabled: viewModel.canUndo) {
                            viewModel.undo()
                        }
                        headerButton(icon: "crown.fill") {
                            votingVenue = viewModel.activeVenue
                        }
                        sosHeaderButton
                        checkoutHeaderButton
                    } else {
                        headerButton(icon: "building.2.crop.circle.fill") {
                            showVenuePicker = true
                        }
                    }
                }
            }

            if let venue = viewModel.activeVenue {
                HStack(spacing: 6) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 9))
                        .foregroundColor(AppTheme.pink)
                    Text("\(venue.neighborhood), \(venue.city)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(AppTheme.textSecondary)

                    Text("•")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textTertiary)

                    HStack(spacing: 4) {
                        Circle()
                            .fill(AppTheme.green)
                            .frame(width: 6, height: 6)
                        Text("\(viewModel.currentVenueOccupancy) here now")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(AppTheme.green)
                    }
                }
            } else {
                Text("Pick a city, then check in to a club")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(AppTheme.textSecondary)
            }
        }
    }

    private func headerButton(
        icon: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isEnabled ? AppTheme.textPrimary : AppTheme.textTertiary)
                .frame(width: 36, height: 36)
                .background(AppTheme.surface)
                .clipShape(Circle())
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.6)
    }

    private var sosHeaderButton: some View {
        Button(action: {
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
            showSOSConfirmation = true
        }) {
            Image(systemName: viewModel.isSendingSOS ? "hourglass" : "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(AppTheme.red)
                .clipShape(Circle())
        }
        .disabled(viewModel.isSendingSOS)
        .opacity(viewModel.isSendingSOS ? 0.7 : 1)
        .accessibilityLabel("Emergency SOS")
    }

    private var checkoutHeaderButton: some View {
        Button(action: {
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
            showCheckOutConfirmation = true
        }) {
            Image(systemName: "rectangle.portrait.and.arrow.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AppTheme.red)
                .frame(width: 36, height: 36)
                .background(AppTheme.surface)
                .clipShape(Circle())
        }
        .accessibilityLabel("Check out")
    }

    private var checkOutOverlay: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture { showCheckOutConfirmation = false }

            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(AppTheme.primaryGradient)
                        .frame(width: 64, height: 64)
                        .shadow(color: AppTheme.pink.opacity(0.4), radius: 16, x: 0, y: 6)
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(.white)
                }
                .padding(.top, 32)

                Text("Leaving already?")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
                    .padding(.top, 20)

                Text("You'll stop appearing in this venue's live roster until you check in again.")
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundColor(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                VStack(spacing: 12) {
                    Button {
                        viewModel.checkOut()
                        showCheckOutConfirmation = false
                    } label: {
                        Text("Check Out")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(AppTheme.primaryGradient)
                            .clipShape(Capsule())
                            .shadow(color: AppTheme.pink.opacity(0.35), radius: 12, x: 0, y: 5)
                    }
                    .buttonStyle(BounceButtonStyle())

                    Button {
                        showCheckOutConfirmation = false
                    } label: {
                        Text("Stay")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundColor(AppTheme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(AppTheme.surface)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(BounceButtonStyle())
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 28)
            }
            .background(
                RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                    .fill(AppTheme.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.12), AppTheme.pink.opacity(0.2), Color.white.opacity(0.06)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.4), radius: 24, x: 0, y: 12)
            .shadow(color: AppTheme.pink.opacity(0.08), radius: 12, x: 0, y: 4)
            .padding(.horizontal, 32)
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.72), value: showCheckOutConfirmation)
    }

    private var sosOverlay: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture { showSOSConfirmation = false }

            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(colors: [AppTheme.red, Color(hex: "B91C1C")], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 64, height: 64)
                        .shadow(color: AppTheme.red.opacity(0.45), radius: 16, x: 0, y: 6)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(.white)
                }
                .padding(.top, 32)

                Text("Emergency SOS")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
                    .padding(.top, 20)

                Text("This records your current ClubMates safety context and opens the emergency phone number.")
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundColor(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                VStack(spacing: 12) {
                    Button {
                        triggerEmergencySOS()
                        showSOSConfirmation = false
                    } label: {
                        Text("Record SOS & Call 112")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(AppTheme.primaryGradient)
                            .clipShape(Capsule())
                            .shadow(color: AppTheme.pink.opacity(0.35), radius: 12, x: 0, y: 5)
                    }
                    .buttonStyle(BounceButtonStyle())

                    Button {
                        showSOSConfirmation = false
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundColor(AppTheme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(AppTheme.surface)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(BounceButtonStyle())
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 28)
            }
            .background(
                RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                    .fill(AppTheme.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.12), AppTheme.red.opacity(0.2), Color.white.opacity(0.06)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.4), radius: 24, x: 0, y: 12)
            .shadow(color: AppTheme.red.opacity(0.08), radius: 12, x: 0, y: 4)
            .padding(.horizontal, 32)
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.72), value: showSOSConfirmation)
    }

    private var sosErrorOverlay: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture { viewModel.sosError = nil }

            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(colors: [AppTheme.red, Color(hex: "B91C1C")], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 64, height: 64)
                        .shadow(color: AppTheme.red.opacity(0.45), radius: 16, x: 0, y: 6)
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(.white)
                }
                .padding(.top, 32)

                Text("SOS Could Not Be Recorded")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
                    .padding(.top, 20)

                Text(viewModel.sosError ?? "Call 112 directly if you are in immediate danger.")
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundColor(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                Button {
                    viewModel.sosError = nil
                } label: {
                    Text("OK")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(AppTheme.primaryGradient)
                        .clipShape(Capsule())
                        .shadow(color: AppTheme.pink.opacity(0.35), radius: 12, x: 0, y: 5)
                }
                .buttonStyle(BounceButtonStyle())
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 28)
            }
            .background(
                RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                    .fill(AppTheme.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.12), AppTheme.red.opacity(0.2), Color.white.opacity(0.06)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.4), radius: 24, x: 0, y: 12)
            .shadow(color: AppTheme.red.opacity(0.08), radius: 12, x: 0, y: 4)
            .padding(.horizontal, 32)
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.72), value: viewModel.sosError)
    }

    private func triggerEmergencySOS() {
        let notification = UINotificationFeedbackGenerator()
        notification.notificationOccurred(.warning)

        Task {
            await viewModel.triggerSOS()
        }

        if let url = URL(string: "tel://112") {
            openURL(url)
        }
    }

    private var checkInEntry: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(AppTheme.surface)
                    .frame(width: 104, height: 104)
                Image(systemName: "building.2.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(AppTheme.primaryGradient)
            }

            VStack(spacing: 8) {
                Text("Choose city and venue")
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
                Text("Check in to see who's at the same club and start venue-based matching.")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundColor(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: { showVenuePicker = true }) {
                HStack(spacing: 8) {
                    if viewModel.isCheckingIn {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "location.viewfinder")
                    }
                    Text(viewModel.isCheckingIn ? "Verifying location..." : "Check in now")
                }
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(AppTheme.primaryGradient)
                .clipShape(Capsule())
            }
            .disabled(viewModel.isCheckingIn)
            .opacity(viewModel.isCheckingIn ? 0.7 : 1)

            if let checkInError = viewModel.checkInError {
                Text(checkInError)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(AppTheme.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius))
    }

    private var rosterSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Here Now")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
                Spacer()
                Text("\(viewModel.currentVenueRoster.count) people")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(AppTheme.textSecondary)
            }

            if viewModel.currentVenueRoster.isEmpty {
                Text("No one has checked in yet. Keep your check-in active and we’ll show people here in real time.")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(AppTheme.textSecondary)
                    .padding(.vertical, 8)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(viewModel.currentVenueRoster) { profile in
                            rosterPerson(profile)
                        }
                    }
                }
            }

            if !viewModel.latestVenueEvent.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.gold)
                    Text(viewModel.latestVenueEvent)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(AppTheme.textSecondary)
                }
            }
        }
        .padding(12)
        .background(AppTheme.surface.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func rosterPerson(_ profile: UserProfile) -> some View {
        VStack(spacing: 6) {
            ProfileAvatar(profile: profile, size: 46)
            Text(profile.name)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(AppTheme.textSecondary)
                .lineLimit(1)
        }
        .frame(width: 54)
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.openRosterProfile(profile)
        }
    }

    private var cardStack: some View {
        GeometryReader { geo in
            ZStack {
                if let next = viewModel.nextProfile {
                    ProfileCardView(
                        profile: next,
                        dragOffset: .constant(.zero),
                        likeOpacity: 0,
                        nopeOpacity: 0,
                        superLikeOpacity: 0,
                        isTopCard: false
                    )
                    .scaleEffect(viewModel.backCardScale)
                    .offset(viewModel.backCardOffset)
                    .animation(.interactiveSpring(response: 0.35, dampingFraction: 0.86), value: viewModel.dragOffset)
                }

                if let current = viewModel.currentProfile {
                    ProfileCardView(
                        profile: current,
                        dragOffset: $viewModel.dragOffset,
                        likeOpacity: viewModel.likeOpacity,
                        nopeOpacity: viewModel.nopeOpacity,
                        superLikeOpacity: viewModel.superLikeOpacity,
                        isTopCard: true,
                        onDragChanged: { viewModel.onDragChanged($0) },
                        onDragEnded: { viewModel.onDragEnded($0) }
                    )
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            viewModel.openRosterProfile(current)
                        }
                    )
                } else {
                    emptyState
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .padding(.horizontal, 14)
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(AppTheme.surface)
                    .frame(width: 100, height: 100)
                Image(systemName: "person.3.sequence.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(AppTheme.primaryGradient)
            }
            VStack(spacing: 8) {
                Text("No new people right now")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
                Text("You’ve seen everyone currently at this venue. Stay checked in for new arrivals.")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundColor(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(32)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius))
    }

    private func hereNowCard(for profile: UserProfile) -> some View {
        VStack(spacing: 16) {
            // Inner hero card
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

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(profile.name)
                            .font(.system(size: 36, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)

                        Text("\(profile.age)")
                            .font(.system(size: 24, weight: .light, design: .rounded))
                            .foregroundColor(.white.opacity(0.72))

                        Spacer()

                        Button(action: {
                            hereNowDetailProfile = profile
                            hereNowDetailPhotoPage = 0
                            showHereNowDetail = true
                        }) {
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
                        .buttonStyle(BounceButtonStyle())
                    }

                    HStack(spacing: 16) {
                        if let profession = hereNowCleanProfession(profile) {
                            Label(profession, systemImage: hereNowProfessionIcon(profile))
                                .lineLimit(1)
                        }
                        if profile.height > 0 {
                            Label("\(profile.height) cm", systemImage: "ruler.fill")
                        }
                    }
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.82))
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
            .frame(height: 420)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            SlideActionRail(
                onPass: { viewModel.swipe(.nope) },
                onLike: { viewModel.swipe(.like) },
                onGift: { inviteProfile = profile }
            )
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(AppTheme.surfaceElevated)
        )
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
        .shadow(color: .black.opacity(0.5), radius: 24, x: 0, y: 12)
    }

    private func hereNowActionButton(
        icon: String,
        label: String,
        size: CGFloat,
        gradient: LinearGradient,
        shadowColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: size * 0.36, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: size, height: size)
                    .background(gradient)
                    .clipShape(Circle())
                    .shadow(color: shadowColor.opacity(0.45), radius: 14, x: 0, y: 7)
                Text(label)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(AppTheme.textSecondary)
            }
        }
        .buttonStyle(BounceButtonStyle())
    }

    private func hereNowCleanProfession(_ profile: UserProfile) -> String? {
        let invalid: Set<String> = ["other","others","na","n/a","none","null","nil","prefer not to say","not specified","unknown","-"]
        let t = profile.profession.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !invalid.contains(t.lowercased()) else { return nil }
        return t
    }

    private func hereNowProfessionIcon(_ profile: UserProfile) -> String {
        let p = hereNowCleanProfession(profile)?.lowercased() ?? ""
        if p.contains("chef") { return "fork.knife" }
        if p.contains("architect") { return "building.2.fill" }
        if p.contains("doctor") { return "cross.case.fill" }
        if p.contains("engineer") { return "hammer.fill" }
        if p.contains("artist") { return "paintpalette.fill" }
        if p.contains("designer") { return "pencil.and.outline" }
        if p.contains("teacher") { return "book.fill" }
        if p.contains("student") { return "graduationcap.fill" }
        return "briefcase.fill"
    }
}

private struct TreatInviteSheet: View {
    let profile: UserProfile
    @ObservedObject var walletVM: WalletViewModel
    let onSelect: (TreatInvite) -> Void
    var onGetMoreCoins: (() -> Void)? = nil

    private var someAffordable: Bool {
        TreatInvite.allCases.contains { walletVM.canAfford($0) }
    }
    private var allAffordable: Bool {
        TreatInvite.allCases.allSatisfy { walletVM.canAfford($0) }
    }

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                dragIndicator
                    .padding(.top, 10)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        headerRow
                        treatGrid
                        if !walletVM.pricing.isEmpty && !allAffordable {
                            getCoinsButton
                        }
                        refundNote
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
            }
        }
        .task { await walletVM.loadPricing(); await walletVM.loadWallet() }
    }

    private var dragIndicator: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color.white.opacity(0.2))
            .frame(width: 36, height: 4)
    }

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 14) {
            ProfilePhotoView(
                photo: profile.mainPhoto,
                symbolName: "person.fill",
                symbolSize: 24,
                gradientColors: [Color(hex: "111827"), Color(hex: "4A1259")],
                symbolOpacity: 0.3,
                contentMode: .fill,
                contentAlignment: .top
            )
            .frame(width: 52, height: 52)
            .clipShape(Circle())
            .overlay(
                Circle().stroke(
                    LinearGradient(colors: [AppTheme.pink.opacity(0.6), AppTheme.purple.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1.5
                )
            )

            VStack(alignment: .leading, spacing: 3) {
                Text("Invite \(profile.name)")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
                Text("Pick a treat to offer")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(AppTheme.textSecondary)
            }

            Spacer()

            HStack(spacing: 5) {
                CoinIcon(size: 15)
                Text("\(walletVM.balance)")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.primaryGradient)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AppTheme.surface)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(AppTheme.pink.opacity(0.25), lineWidth: 1)
            )
        }
    }

    private var treatGrid: some View {
        VStack(spacing: 10) {
            ForEach(TreatInvite.allCases) { treat in
                treatCard(treat)
            }
        }
    }

    private func treatCard(_ treat: TreatInvite) -> some View {
        let cost = walletVM.costFor(treat)
        let canAfford = walletVM.canAfford(treat)

        return Button {
            if canAfford { onSelect(treat) }
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(canAfford ? AnyShapeStyle(AppTheme.primaryGradient.opacity(0.15)) : AnyShapeStyle(Color.white.opacity(0.04)))
                        .frame(width: 50, height: 50)
                    TreatIcon(treat: treat, size: 30, isEnabled: canAfford)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(treat.title)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(canAfford ? AppTheme.textPrimary : AppTheme.textTertiary)
                    Text(treatFlavor(treat))
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(canAfford ? AppTheme.textSecondary : AppTheme.textTertiary.opacity(0.6))
                }

                Spacer()

                if !canAfford, let cost {
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 3) {
                            CoinIcon(size: 13)
                            Text("\(cost)")
                                .font(.system(size: 13, weight: .black, design: .rounded))
                                .foregroundColor(AppTheme.pink.opacity(0.7))
                        }
                        Text("need \(cost - walletVM.balance) more")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                } else if let cost {
                    HStack(spacing: 4) {
                        CoinIcon(size: 14)
                        Text("\(cost)")
                            .font(.system(size: 14, weight: .black, design: .rounded))
                            .foregroundStyle(AppTheme.primaryGradient)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(AppTheme.primaryGradient.opacity(0.1))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(AppTheme.pink.opacity(0.3), lineWidth: 1))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(canAfford ? AppTheme.surface : AppTheme.surface.opacity(0.4))
                    if canAfford {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(AppTheme.primaryGradient.opacity(0.03))
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(
                        canAfford
                            ? LinearGradient(colors: [AppTheme.pink.opacity(0.2), AppTheme.purple.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [Color.white.opacity(0.05), Color.white.opacity(0.03)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(BounceButtonStyle())
        .disabled(!canAfford)
    }

    private func treatFlavor(_ treat: TreatInvite) -> String {
        switch treat {
        case .drink: return "A round of drinks on you"
        case .dessert: return "Sweet ending to the night"
        case .coffee: return "A relaxed morning together"
        case .starter: return "Kick things off with bites"
        }
    }

    private var getCoinsButton: some View {
        Button {
            onGetMoreCoins?()
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(AppTheme.primaryGradient)
                        .frame(width: 32, height: 32)
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .black))
                        .foregroundColor(.white)
                }
                Text("Get more coins")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryGradient)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(AppTheme.textTertiary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(AppTheme.primaryGradient.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(BounceButtonStyle())
    }

    private var refundNote: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.counterclockwise.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(AppTheme.green.opacity(0.7))
            Text("Coins refunded if invite is declined")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(AppTheme.textTertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(AppTheme.green.opacity(0.07))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(AppTheme.green.opacity(0.2), lineWidth: 1))
    }
}

private struct IncomingLikeToast: View {
    let banner: MatchesViewModel.IncomingLikeBanner

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: banner.treat == nil ? (banner.isSuperLike ? "star.fill" : "heart.fill") : "gift.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(banner.isSuperLike ? AppTheme.gold : AppTheme.pink)
                .frame(width: 28, height: 28)
                .background(AppTheme.surfaceElevated)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(banner.treat == nil ? (banner.isSuperLike ? "New super like" : "New like") : "New invite")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
                Text(
                    banner.treat.map { "\(banner.name) wants to \($0.notificationNoun)" }
                        ?? "\(banner.name) liked your profile"
                )
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
    }
}

private struct RosterProfileSheet: View {
    let profile: UserProfile
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            AppTheme.background.ignoresSafeArea()

            ProfileCardView(
                profile: profile,
                dragOffset: .constant(.zero),
                likeOpacity: 0,
                nopeOpacity: 0,
                superLikeOpacity: 0,
                isTopCard: false
            )
            .padding(.horizontal, 16)
            .padding(.top, 24)
            .padding(.bottom, 16)

            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary)
                    .frame(width: 34, height: 34)
                    .background(AppTheme.surface)
                    .clipShape(Circle())
            }
            .padding(.top, 12)
            .padding(.trailing, 20)
        }
    }
}

private struct VenuePickerSheet: View {
    let options: [DiscoverViewModel.VenueOption]
    let cities: [String]
    let selectedCity: String
    let activeVenueID: UUID?
    let onSelectCity: (String) -> Void
    let onSelectVenue: (Venue) -> Void
    let onOpenVoting: (Venue) -> Void
    let onCheckOut: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedNeighborhood = Self.allFilterValue
    @State private var selectedMusic = Self.allFilterValue
    @State private var selectedVibe = Self.allFilterValue
    @State private var venueSearchText = ""

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        header
                        cityPicker
                            .padding(.bottom, 4)
                        filterPanel
                        searchField

                        if filteredOptions.isEmpty {
                            emptyCityState
                        } else {
                            ForEach(filteredOptions) { option in
                                venueCard(option)
                            }
                        }

                        if activeVenueID != nil {
                            Button(action: {
                                onCheckOut()
                                dismiss()
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "rectangle.portrait.and.arrow.right")
                                    Text("Check out of venue")
                                }
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundColor(AppTheme.red)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(AppTheme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                            .padding(.top, 6)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(AppTheme.primaryGradient)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Check in")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
                Text("Find the right spot before you start swiping.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button("Done") { dismiss() }
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .frame(height: 40)
                .background(AppTheme.primaryGradient)
                .clipShape(Capsule())
                .buttonStyle(.plain)
        }
        .padding(.bottom, 4)
    }

    private var filteredOptions: [DiscoverViewModel.VenueOption] {
        options.filter { option in
            let venue = option.venue
            let matchesNeighborhood = selectedNeighborhood == Self.allFilterValue || venue.neighborhood == selectedNeighborhood
            let matchesMusic = selectedMusic == Self.allFilterValue || Self.musicTokens(for: venue).contains(selectedMusic)
            let matchesVibe = selectedVibe == Self.allFilterValue || Self.vibeCategory(for: venue) == selectedVibe
            let matchesSearch = normalizedVenueSearchText.isEmpty
                || venue.name.localizedCaseInsensitiveContains(normalizedVenueSearchText)
            return matchesNeighborhood && matchesMusic && matchesVibe && matchesSearch
        }
    }

    private var neighborhoodOptions: [String] {
        Self.filterValues(options.map(\.venue.neighborhood))
    }

    private var musicOptions: [String] {
        Self.filterValues(options.flatMap { Self.musicTokens(for: $0.venue) })
    }

    private var vibeOptions: [String] {
        Self.filterValues(options.map { Self.vibeCategory(for: $0.venue) })
    }

    private var hasActiveFilters: Bool {
        selectedNeighborhood != Self.allFilterValue
            || selectedMusic != Self.allFilterValue
            || selectedVibe != Self.allFilterValue
    }

    private var hasSearchQuery: Bool {
        !normalizedVenueSearchText.isEmpty
    }

    private var normalizedVenueSearchText: String {
        venueSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var cityPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("City")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(AppTheme.textSecondary)

                Spacer()

                Text(venueCountSummary)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(AppTheme.textTertiary)
            }

            Menu {
                ForEach(cityPickerCities, id: \.self) { city in
                    Button(action: {
                        resetFilters()
                        venueSearchText = ""
                        onSelectCity(city)
                    }) {
                        if city == selectedCity {
                            Label(city, systemImage: "checkmark")
                        } else {
                            Text(city)
                        }
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "building.2.crop.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppTheme.primaryGradient)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedCity.isEmpty ? "Select city" : selectedCity)
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundColor(AppTheme.textPrimary)
                            .lineLimit(1)

                        Text("\(cityPickerCities.count) cities available")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(AppTheme.textTertiary)
                    }

                    Spacer()

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(AppTheme.textTertiary)
                }
                .padding(.horizontal, 14)
                .frame(height: 58)
                .background(AppTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(AppTheme.pink.opacity(0.18), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppTheme.surface, lineWidth: 1)
        )
    }

    private var cityPickerCities: [String] {
        cities.isEmpty ? [selectedCity] : cities
    }

    private var venueCountSummary: String {
        if options.count >= 30 {
            return "30+ venues"
        }

        return "\(options.count) venues"
    }

    private var filterPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Filters")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(AppTheme.textSecondary)

                Spacer()

                if hasActiveFilters {
                    Button("Clear") { resetFilters() }
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.primaryGradient)
                        .buttonStyle(.plain)
                }
            }

            HStack(spacing: 8) {
                filterMenu(
                    title: "Area",
                    icon: "mappin.and.ellipse",
                    selection: selectedNeighborhood,
                    values: neighborhoodOptions,
                    onSelect: { selectedNeighborhood = $0 }
                )

                filterMenu(
                    title: "Music",
                    icon: "music.note",
                    selection: selectedMusic,
                    values: musicOptions,
                    onSelect: { selectedMusic = $0 }
                )

                filterMenu(
                    title: "Vibe",
                    icon: "sparkles",
                    selection: selectedVibe,
                    values: vibeOptions,
                    onSelect: { selectedVibe = $0 }
                )
            }
        }
        .padding(14)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppTheme.surface, lineWidth: 1)
        )
    }

    private func filterMenu(
        title: String,
        icon: String,
        selection: String,
        values: [String],
        onSelect: @escaping (String) -> Void
    ) -> some View {
        Menu {
            ForEach(values, id: \.self) { value in
                Button(action: { onSelect(value) }) {
                    if value == selection {
                        Label(value, systemImage: "checkmark")
                    } else {
                        Text(value)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(selection == Self.allFilterValue ? AnyShapeStyle(AppTheme.textTertiary) : AnyShapeStyle(AppTheme.primaryGradient))

                Text(selection == Self.allFilterValue ? title : selection)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(selection == Self.allFilterValue ? AppTheme.textSecondary : AppTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(AppTheme.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .padding(.horizontal, 8)
            .background(selection == Self.allFilterValue ? AppTheme.surface : AppTheme.pink.opacity(0.12))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(selection == Self.allFilterValue ? AppTheme.surfaceElevated.opacity(0.75) : AppTheme.pink.opacity(0.28), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppTheme.textTertiary)

            TextField("Search venue name", text: $venueSearchText)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(AppTheme.textPrimary)
                .textInputAutocapitalization(.words)
                .disableAutocorrection(true)
                .submitLabel(.search)

            if hasSearchQuery {
                Button(action: { venueSearchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppTheme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(hasSearchQuery ? AppTheme.pink.opacity(0.28) : AppTheme.surface, lineWidth: 1)
        )
    }

    private var emptyCityState: some View {
        VStack(spacing: 12) {
            Image(systemName: hasActiveFilters || hasSearchQuery ? "line.3.horizontal.decrease.circle" : "building.2.crop.circle")
                .font(.system(size: 28))
                .foregroundColor(AppTheme.textTertiary)

            Text(emptyStateTitle)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(AppTheme.textSecondary)

            if hasActiveFilters || hasSearchQuery {
                Button("Clear search and filters") {
                    resetFilters()
                    venueSearchText = ""
                }
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryGradient)
                    .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var emptyStateTitle: String {
        if hasSearchQuery {
            return "No venues named \"\(normalizedVenueSearchText)\""
        }

        if hasActiveFilters {
            return "No venues match these filters"
        }

        return "No venues in \(selectedCity) yet"
    }

    private func venueCard(_ option: DiscoverViewModel.VenueOption) -> some View {
        let isActive = activeVenueID == option.venue.id

        return VStack(spacing: 12) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(option.venue.gradient)
                        .frame(width: 48, height: 48)
                    Image(systemName: option.venue.symbolName)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(option.venue.name)
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundColor(AppTheme.textPrimary)
                        if isActive {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(AppTheme.green)
                        }
                    }
                    Text("\(option.venue.neighborhood) • \(option.venue.music)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(AppTheme.textSecondary)
                    Text(option.venue.vibe)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(AppTheme.textTertiary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        compactTag("Weekend Voting")
                        compactTag(Self.vibeCategory(for: option.venue))
                        compactTag(Self.musicTokens(for: option.venue).first ?? option.venue.music)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(option.occupancy)")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundColor(AppTheme.textPrimary)
                    Text("here now")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(AppTheme.textTertiary)
                }
            }

            HStack(spacing: 8) {
                Button(action: {
                    onSelectVenue(option.venue)
                    dismiss()
                }) {
                    Label(isActive ? "Checked In" : "Check In", systemImage: isActive ? "checkmark.circle.fill" : "location.viewfinder")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundColor(isActive ? AppTheme.green : .white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(isActive ? AnyShapeStyle(AppTheme.surface) : AnyShapeStyle(AppTheme.primaryGradient))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isActive)

                Button(action: {
                    onOpenVoting(option.venue)
                    dismiss()
                }) {
                    Label("Weekend Voting", systemImage: "crown.fill")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundColor(AppTheme.pink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(AppTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isActive ? AppTheme.pink.opacity(0.55) : AppTheme.surface, lineWidth: isActive ? 2 : 1)
        )
    }

    private func compactTag(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundColor(AppTheme.textTertiary)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(AppTheme.surface.opacity(0.8))
            .clipShape(Capsule())
    }

    private func resetFilters() {
        selectedNeighborhood = Self.allFilterValue
        selectedMusic = Self.allFilterValue
        selectedVibe = Self.allFilterValue
    }

    private static let allFilterValue = "All"

    private static func filterValues(_ values: [String]) -> [String] {
        [allFilterValue] + Array(Set(values.filter { !$0.isEmpty })).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    private static func musicTokens(for venue: Venue) -> [String] {
        venue.music
            .split(separator: "/")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func vibeCategory(for venue: Venue) -> String {
        let text = "\(venue.vibe) \(venue.music) \(venue.name)".lowercased()

        if text.contains("brew") || text.contains("beer") { return "Brewery" }
        if text.contains("rooftop") || text.contains("sky") { return "Rooftop" }
        if text.contains("live") || text.contains("jazz") || text.contains("rock") { return "Live" }
        if text.contains("club") || text.contains("edm") || text.contains("dance") { return "Club" }
        if text.contains("cocktail") { return "Cocktails" }
        if text.contains("pub") { return "Pub" }
        if text.contains("lounge") { return "Lounge" }
        return "Social"
    }
}

struct BounceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.87 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.55), value: configuration.isPressed)
    }
}
