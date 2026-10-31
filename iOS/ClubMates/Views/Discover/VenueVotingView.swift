import SwiftUI

struct VenueVotingView: View {
    let venue: Venue
    @StateObject private var viewModel = VenueVotingViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var now = Date()
    @State private var entryLayout: EntryLayout = .grid

    private enum EntryLayout: String, CaseIterable, Identifiable {
        case grid
        case list

        var id: String { rawValue }
        var title: String { rawValue.capitalized }
        var icon: String {
            switch self {
            case .grid: return "square.grid.2x2.fill"
            case .list: return "list.bullet"
            }
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "090915"), Color(hex: "1A0D22"), AppTheme.background],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    categoryTabs

                    if viewModel.isLoading && viewModel.competitions.isEmpty {
                        loadingState
                    } else if let competition = viewModel.selectedCompetition {
                        competitionContent(competition)
                    } else {
                        emptyState
                    }

                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 34)
            }
        }
        .task {
            viewModel.load(venue: venue)
            viewModel.connectRealtime(venue: venue)
        }
        .onDisappear {
            viewModel.stopRealtime()
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { tick in
            now = tick
        }
        .alert(
            "Voting update failed",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "Please try again.")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(AppTheme.red)
                        .frame(width: 7, height: 7)
                    Text("WEEKEND VOTING")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .foregroundColor(AppTheme.red)
                }

                Text(venue.name)
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Text("Saturday and Sunday competitions for Male, Female, and LGBTQ")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(AppTheme.textSecondary)

                Button {
                    viewModel.restartDemo(venue: venue)
                    now = Date()
                } label: {
                    HStack(spacing: 6) {
                        if viewModel.isRestarting {
                            ProgressView()
                                .scaleEffect(0.72)
                                .tint(AppTheme.pink)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text(viewModel.isRestarting ? "Restarting..." : "Restart demo")
                    }
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundColor(AppTheme.pink)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(AppTheme.surface)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isRestarting)
            }

            Spacer()

            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary)
                    .frame(width: 34, height: 34)
                    .background(AppTheme.surface)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var categoryTabs: some View {
        HStack(spacing: 8) {
            ForEach(VenueVotingCategory.allCases) { category in
                Button {
                    viewModel.selectedCategory = category
                } label: {
                    Text(category.title)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(viewModel.selectedCategory == category ? .white : AppTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(viewModel.selectedCategory == category ? AnyShapeStyle(AppTheme.primaryGradient) : AnyShapeStyle(AppTheme.surface))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(AppTheme.cardBackground)
        .clipShape(Capsule())
    }

    @ViewBuilder
    private func competitionContent(_ competition: VenueVotingCompetition) -> some View {
        statusPanel(competition)

        switch effectivePhase(for: competition) {
        case .registration:
            registrationPanel(competition)
        case .live:
            liveVotingPanel(competition)
        case .ended:
            winnerPanel(competition)
        }
    }

    private func statusPanel(_ competition: VenueVotingCompetition) -> some View {
        HStack(spacing: 12) {
            metricTile(
                icon: "trophy.fill",
                label: "Prize Pool",
                value: rupees(competition.prizeAmountCents),
                tint: AppTheme.gold
            )
            metricTile(
                icon: "person.3.fill",
                label: "Entries",
                value: "\(competition.entries.count)",
                tint: AppTheme.green
            )
            metricTile(
                icon: "heart.fill",
                label: "Total Votes",
                value: "\(competition.totalVotes)",
                tint: AppTheme.pink
            )
        }
    }

    private func metricTile(icon: String, label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(tint)
            Text(value)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundColor(AppTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(AppTheme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.surface, lineWidth: 1)
        )
    }

    private func registrationPanel(_ competition: VenueVotingCompetition) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            venuePreview

            VStack(alignment: .leading, spacing: 12) {
                detailRow(icon: "clock.fill", title: "Voting Time", value: "\(time(competition.startsAt)) - \(time(competition.endsAt))")
                detailRow(icon: "trophy.fill", title: "Prize Money", value: "Winner takes \(rupees(competition.prizeAmountCents))")
                detailRow(icon: "person.3.fill", title: "Voting Limit", value: "1 vote per competition")
            }

            if now < competition.startsAt {
                countdownBanner("Voting starts in \(countdown(to: competition.startsAt))")
            } else {
                urgencyBanner("Registration closes at \(time(competition.registrationClosesAt))")
            }
            paymentSummary(competition)

            Button {
                viewModel.join(venue: venue)
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isJoining {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: competition.userEntryId == nil ? "heart.fill" : "checkmark.circle.fill")
                    }
                    Text(competition.userEntryId == nil ? "Pay \(rupees(competition.entryFeeCents + competition.platformFeeCents)) & Join" : "Already Joined")
                }
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(AppTheme.primaryGradient)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .disabled(viewModel.isJoining || competition.userEntryId != nil)
            .buttonStyle(.plain)
        }
        .votingCard()
    }

    private var venuePreview: some View {
        ZStack(alignment: .bottomLeading) {
            venue.gradient
            LinearGradient(colors: [.clear, .black.opacity(0.76)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 3) {
                Text(venue.name)
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                Text("\(venue.neighborhood), \(venue.city)")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.78))
            }
            .padding(14)
        }
        .frame(height: 132)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func detailRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(AppTheme.pink)
                .frame(width: 30, height: 30)
                .background(AppTheme.pink.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
                Text(value)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(AppTheme.textSecondary)
            }
            Spacer()
        }
    }

    private func urgencyBanner(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
            Text(text)
            Spacer()
        }
        .font(.system(size: 12, weight: .bold, design: .rounded))
        .foregroundColor(AppTheme.red)
        .padding(12)
        .background(AppTheme.red.opacity(0.16))
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(AppTheme.red.opacity(0.45), lineWidth: 1)
        )
    }

    private func countdownBanner(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "timer")
            Text(text)
            Spacer()
        }
        .font(.system(size: 13, weight: .black, design: .rounded))
        .foregroundColor(.white)
        .padding(12)
        .background(AppTheme.primaryGradient)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private func paymentSummary(_ competition: VenueVotingCompetition) -> some View {
        VStack(spacing: 10) {
            summaryRow("Entry Fee", rupees(competition.entryFeeCents))
            summaryRow("Platform Fee", rupees(competition.platformFeeCents))
            Divider().overlay(AppTheme.surface)
            summaryRow("Total", rupees(competition.entryFeeCents + competition.platformFeeCents), isTotal: true)
        }
        .padding(14)
        .background(AppTheme.surface.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func summaryRow(_ label: String, _ value: String, isTotal: Bool = false) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundColor(isTotal ? AppTheme.pink : AppTheme.textPrimary)
        }
        .font(.system(size: isTotal ? 14 : 12, weight: isTotal ? .black : .semibold, design: .rounded))
        .foregroundColor(isTotal ? AppTheme.textPrimary : AppTheme.textSecondary)
    }

    private func liveVotingPanel(_ competition: VenueVotingCompetition) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Vote for your favorite")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundColor(AppTheme.textSecondary)
                    Spacer()
                    Text("Ends in \(countdown(to: competition.endsAt))")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(AppTheme.pink)
                }

                entryLayoutToggle
            }

            if competition.entries.isEmpty {
                Text("No entries yet for \(competition.category.title).")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(AppTheme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                    .background(AppTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                if competition.userVotesRemaining == 0 {
                    voteUsedBanner
                }

                if entryLayout == .grid {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10)
                        ],
                        spacing: 10
                    ) {
                        ForEach(competition.entries) { entry in
                            gridEntryCard(entry, canVote: competition.userVotesRemaining > 0)
                        }
                    }
                } else {
                    ForEach(competition.entries) { entry in
                        entryCard(entry, canVote: competition.userVotesRemaining > 0)
                    }
                }
            }
        }
    }

    private var entryLayoutToggle: some View {
        HStack(spacing: 6) {
            ForEach(EntryLayout.allCases) { layout in
                Button {
                    entryLayout = layout
                } label: {
                    Label(layout.title, systemImage: layout.icon)
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundColor(entryLayout == layout ? .white : AppTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(entryLayout == layout ? AnyShapeStyle(AppTheme.primaryGradient) : AnyShapeStyle(AppTheme.surface))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(AppTheme.cardBackground)
        .clipShape(Capsule())
    }

    private var voteUsedBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
            Text("Your vote is locked for this competition")
            Spacer()
        }
        .font(.system(size: 12, weight: .bold, design: .rounded))
        .foregroundColor(AppTheme.green)
        .padding(12)
        .background(AppTheme.green.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(AppTheme.green.opacity(0.32), lineWidth: 1)
        )
    }

    private func entryCard(_ entry: VenueVotingEntry, canVote: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                ProfilePhotoView(
                    photo: entry.profile.mainPhoto,
                    symbolName: "person.fill",
                    symbolSize: 72,
                    gradientColors: [Color(hex: "15151F"), Color(hex: "3A244A")],
                    symbolOpacity: 0.16,
                    contentMode: .fill,
                    contentAlignment: .top
                )
                .frame(height: 300)

                HStack {
                    Text("#\(entry.rank)")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundColor(.black)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(AppTheme.gold)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                    Spacer()

                    Label("\(entry.voteCount) votes", systemImage: "flame.fill")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(Color.black.opacity(0.56))
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .padding(12)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(alignment: .leading, spacing: 10) {
                Text(entry.profile.name)
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
                Text("Age \(entry.profile.age)")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(AppTheme.textSecondary)

                HStack(spacing: 8) {
                    Button {} label: {
                        Label("Skip", systemImage: "hand.thumbsdown")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(AppTheme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .background(AppTheme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button {
                        viewModel.vote(entry: entry)
                    } label: {
                        Label(voteButtonTitle(entry: entry, canVote: canVote), systemImage: voteButtonIcon(entry: entry, canVote: canVote))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .background(AppTheme.primaryGradient)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .disabled(!canVote || entry.hasVoted || viewModel.isVoting)
                    .opacity((!canVote || entry.hasVoted) ? 0.62 : 1)
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
        }
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(entry.rank == 1 ? AppTheme.gold.opacity(0.5) : AppTheme.surface, lineWidth: 1)
        )
    }

    private func gridEntryCard(_ entry: VenueVotingEntry, canVote: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                ProfilePhotoView(
                    photo: entry.profile.mainPhoto,
                    symbolName: "person.fill",
                    symbolSize: 44,
                    gradientColors: [Color(hex: "15151F"), Color(hex: "3A244A")],
                    symbolOpacity: 0.16,
                    contentMode: .fill,
                    contentAlignment: .top
                )
                .frame(height: 170)

                HStack(alignment: .top) {
                    Text("#\(entry.rank)")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundColor(.black)
                        .padding(.horizontal, 8)
                        .frame(height: 26)
                        .background(AppTheme.gold)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    Spacer()

                    Label("\(entry.voteCount)", systemImage: "flame.fill")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .frame(height: 26)
                        .background(Color.black.opacity(0.56))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .padding(9)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text(entry.profile.name)
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text("Age \(entry.profile.age)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(AppTheme.textSecondary)

                HStack(spacing: 7) {
                    Button {} label: {
                        Image(systemName: "hand.thumbsdown")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(AppTheme.textSecondary)
                            .frame(width: 40, height: 38)
                            .background(AppTheme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button {
                        viewModel.vote(entry: entry)
                    } label: {
                        Label(voteButtonTitle(entry: entry, canVote: canVote), systemImage: voteButtonIcon(entry: entry, canVote: canVote))
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .background(AppTheme.primaryGradient)
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }
                    .disabled(!canVote || entry.hasVoted || viewModel.isVoting)
                    .opacity((!canVote || entry.hasVoted) ? 0.62 : 1)
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
        }
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(entry.rank == 1 ? AppTheme.gold.opacity(0.5) : AppTheme.surface, lineWidth: 1)
        )
    }

    private func voteButtonTitle(entry: VenueVotingEntry, canVote: Bool) -> String {
        if entry.hasVoted { return "Voted" }
        return canVote ? "Vote" : "Vote Used"
    }

    private func voteButtonIcon(entry: VenueVotingEntry, canVote: Bool) -> String {
        if entry.hasVoted { return "checkmark" }
        return canVote ? "heart.fill" : "lock.fill"
    }

    private func winnerPanel(_ competition: VenueVotingCompetition) -> some View {
        VStack(spacing: 18) {
            if let winner = resolvedWinner(for: competition) {
                Text("WINNER")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundColor(.black)
                    .padding(.horizontal, 18)
                    .frame(height: 34)
                    .background(AppTheme.gold)
                    .clipShape(Capsule())

                ProfilePhotoView(
                    photo: winner.profile.mainPhoto,
                    symbolName: "person.fill",
                    symbolSize: 44,
                    gradientColors: [Color(hex: "2A1A24"), Color(hex: "5A2D13")],
                    symbolOpacity: 0.18
                )
                .frame(width: 112, height: 112)
                .clipShape(Circle())
                .overlay(Circle().stroke(AppTheme.gold, lineWidth: 3))

                VStack(spacing: 5) {
                    Text(winner.profile.name)
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundColor(AppTheme.textPrimary)
                    Text("Age \(winner.profile.age)")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(AppTheme.textSecondary)
                }

                HStack(spacing: 26) {
                    winnerMetric("\(winner.voteCount)", "Total Votes")
                    winnerMetric(winRate(winner, competition), "Win Rate")
                }

                VStack(spacing: 6) {
                    Text("PRIZE MONEY")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .foregroundColor(AppTheme.textTertiary)
                    Text(rupees(competition.prizeAmountCents))
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundColor(AppTheme.gold)
                    Text("Awarded to the winner")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(AppTheme.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(AppTheme.gold.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(AppTheme.gold.opacity(0.5), lineWidth: 1)
                )

                resultsBreakdown(competition)
            } else {
                noWinnerPanel(competition)
            }
        }
        .votingCard()
    }

    private func noWinnerPanel(_ competition: VenueVotingCompetition) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "trophy")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(AppTheme.gold)
                .frame(width: 58, height: 58)
                .background(AppTheme.gold.opacity(0.12))
                .clipShape(Circle())

            Text("No winner yet")
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundColor(AppTheme.textPrimary)

            Text("At least one vote is required before a winner can be shown.")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(AppTheme.textSecondary)
                .multilineTextAlignment(.center)

            resultsBreakdown(competition)
        }
    }

    private func resultsBreakdown(_ competition: VenueVotingCompetition) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Results")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundColor(AppTheme.textSecondary)

            ForEach(competition.entries.sorted {
                if $0.voteCount == $1.voteCount {
                    return $0.joinedAt < $1.joinedAt
                }
                return $0.voteCount > $1.voteCount
            }) { entry in
                HStack(spacing: 10) {
                    Text("#\(entry.rank)")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundColor(entry.rank == 1 ? .black : AppTheme.textSecondary)
                        .frame(width: 34, height: 26)
                        .background(entry.rank == 1 ? AppTheme.gold : AppTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.profile.name)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(AppTheme.textPrimary)
                            .lineLimit(1)
                        if !entry.isWinnerEligible {
                            Text("Not eligible for winner")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundColor(AppTheme.red)
                        }
                    }

                    Spacer()

                    Text("\(entry.voteCount) votes")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundColor(AppTheme.gold)
                }
                .padding(10)
                .background(AppTheme.surface.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func resolvedWinner(for competition: VenueVotingCompetition) -> VenueVotingEntry? {
        if let winner = competition.winner, winner.isWinnerEligible, winner.voteCount > 0 {
            return winner
        }

        return competition.entries.filter { $0.isWinnerEligible && $0.voteCount > 0 }.sorted {
            if $0.voteCount == $1.voteCount {
                return $0.joinedAt < $1.joinedAt
            }
            return $0.voteCount > $1.voteCount
        }.first
    }

    private func winnerMetric(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundColor(AppTheme.gold)
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(AppTheme.textTertiary)
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("My Voting")
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundColor(AppTheme.textPrimary)

            if viewModel.history.isEmpty {
            Text("Your voting history will appear here after weekend competitions end.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(AppTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(AppTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                ForEach(viewModel.history) { item in
                    HStack(spacing: 12) {
                        Image(systemName: item.userWon ? "crown.fill" : "ticket.fill")
                            .foregroundColor(item.userWon ? AppTheme.gold : AppTheme.textSecondary)
                            .frame(width: 36, height: 36)
                            .background(AppTheme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.venueName)
                                .font(.system(size: 13, weight: .black, design: .rounded))
                                .foregroundColor(AppTheme.textPrimary)
                            Text("\(item.category.title) competition")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundColor(AppTheme.textSecondary)
                            Text("\(voteCountText(item.totalVotes)) cast")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundColor(AppTheme.textTertiary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(item.userWon ? "Won" : "Votes received")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(AppTheme.textTertiary)
                            Text(item.userWon ? rupees(item.prizeAmountCents) : "\(item.votesReceived)")
                                .font(.system(size: 13, weight: .black, design: .rounded))
                                .foregroundColor(item.userWon ? AppTheme.gold : AppTheme.textPrimary)
                        }
                    }
                    .padding(12)
                    .background(AppTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(item.userWon ? AppTheme.gold.opacity(0.42) : AppTheme.surface, lineWidth: 1)
                    )
                }
            }
        }
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView().tint(AppTheme.pink)
            Text("Loading weekend voting")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .votingCard()
    }

    private var emptyState: some View {
        Text("Weekend voting is not available for this venue yet.")
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundColor(AppTheme.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 34)
            .votingCard()
    }

    private func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    private func effectivePhase(for competition: VenueVotingCompetition) -> VenueVotingPhase {
        if now >= competition.endsAt {
            return .ended
        }
        if now >= competition.startsAt {
            return .live
        }
        return .registration
    }

    private func countdown(to date: Date) -> String {
        let remainingSeconds = max(0, Int(date.timeIntervalSince(now).rounded(.up)))
        if remainingSeconds < 60 {
            return "\(remainingSeconds)s"
        }

        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        if minutes < 60 {
            return String(format: "%d:%02d", minutes, seconds)
        }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return String(format: "%dh %02dm", hours, remainingMinutes)
    }

    private func rupees(_ cents: Int) -> String {
        "₹\(cents / 100)"
    }

    private func winRate(_ winner: VenueVotingEntry, _ competition: VenueVotingCompetition) -> String {
        guard competition.totalVotes > 0 else { return "0%" }
        return "\(Int((Double(winner.voteCount) / Double(competition.totalVotes) * 100).rounded()))%"
    }

    private func voteCountText(_ count: Int) -> String {
        count == 1 ? "1 vote" : "\(count) votes"
    }
}

private extension View {
    func votingCard() -> some View {
        self
            .padding(14)
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(AppTheme.surface, lineWidth: 1)
            )
    }
}
