import SwiftUI

struct CoinShopView: View {
    @EnvironmentObject var walletVM: WalletViewModel
    var isPresented: Binding<Bool>? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.tabBarState) private var tabBarState

    @State private var pulseScale: CGFloat = 1.0
    @State private var sparkleOpacity: [Double] = [0.6, 0.3, 0.8, 0.4, 0.7, 0.5]
    @State private var sparkleOffset: [CGFloat] = [0, 0, 0, 0, 0, 0]
    @State private var showingHistory = false
    @State private var showingWithdrawNotice = false

    private let sparklePositions: [(CGFloat, CGFloat)] = [
        (-44, -30), (42, -34), (-58, 4), (56, 12), (-32, 38), (34, 36)
    ]

    private func closeView() {
        if let binding = isPresented {
            binding.wrappedValue = false
        } else {
            dismiss()
        }
    }

    var body: some View {
        ZStack {
            background
            ScrollView(showsIndicators: false) {
                VStack(spacing: 28) {
                    heroSection
                    quickActions
                    packagesSection
                    if !walletVM.transactions.isEmpty {
                        transactionsSection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 48)
            }
        }
        .task { await walletVM.loadAll() }
        .navigationBarHidden(true)
        .onAppear { tabBarState?.isHidden = true }
        .onDisappear { tabBarState?.isHidden = false }
        .fullScreenCover(isPresented: $showingHistory) {
            CoinHistoryView(transactions: walletVM.transactions)
        }
        .alert("Withdrawals coming soon", isPresented: $showingWithdrawNotice) {
            Button("Got it", role: .cancel) {}
        } message: {
            Text("Your coin balance is safe here. Cash withdrawals can be connected when the payout flow is ready.")
        }
        .overlay(alignment: .topLeading) {
            Button(action: { closeView() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
            }
            .padding(.top, 54)
            .padding(.leading, 20)
        }
    }

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "0D0B1E"), Color(hex: "180B29"), Color(hex: "0D0D0F")],
                startPoint: .top,
                endPoint: .bottom
            )
            Circle()
                .fill(Color(hex: "7C3AED").opacity(0.24))
                .frame(width: 280, height: 280)
                .blur(radius: 80)
                .offset(x: -60, y: -100)
            Circle()
                .fill(AppTheme.pink.opacity(0.18))
                .frame(width: 220, height: 220)
                .blur(radius: 68)
                .offset(x: 128, y: 80)
        }
        .ignoresSafeArea()
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(AppTheme.pink.opacity(0.34))
                    .frame(width: 132, height: 132)
                    .blur(radius: 34)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "FF8CC2"), Color(hex: "B95CFF"), Color(hex: "5271FF")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 78, height: 78)
                    .scaleEffect(pulseScale)
                    .shadow(color: AppTheme.pink.opacity(0.45), radius: 24, x: 0, y: 10)

                Circle()
                    .fill(Color.white.opacity(0.16))
                    .frame(width: 56, height: 56)

                Text("C")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundColor(.white)

                ForEach(0..<6, id: \.self) { i in
                    Circle()
                        .fill(i == 1 ? AppTheme.gold : Color.white)
                        .frame(width: i == 1 ? 12 : 4, height: i == 1 ? 12 : 4)
                        .opacity(sparkleOpacity[i])
                        .offset(x: sparklePositions[i].0, y: sparklePositions[i].1 + sparkleOffset[i])
                }
            }
            .frame(height: 120)
            .onAppear {
                withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                    pulseScale = 1.06
                }
                for i in 0..<6 {
                    withAnimation(.easeInOut(duration: Double.random(in: 1.6...2.8)).repeatForever(autoreverses: true).delay(Double(i) * 0.3)) {
                        sparkleOpacity[i] = i % 2 == 0 ? 0.15 : 0.9
                        sparkleOffset[i] = i % 2 == 0 ? -6 : 6
                    }
                }
            }

            VStack(spacing: 6) {
                Text("YOUR BALANCE")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundColor(.white.opacity(0.48))
                    .tracking(2.5)

                Text("\(walletVM.balance)")
                    .font(.system(size: 56, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, Color(hex: "FFB8D8")],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .contentTransition(.numericText())

                Text("≈ ₹\(walletVM.balance) value")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.34))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 62)
        .padding(.bottom, 30)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                AppTheme.pink.opacity(0.28),
                                AppTheme.purple.opacity(0.20),
                                Color(hex: "315BFF").opacity(0.14)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.black.opacity(0.12))
                Circle()
                    .fill(AppTheme.pink.opacity(0.26))
                    .frame(width: 180, height: 180)
                    .blur(radius: 58)
                    .offset(x: -92, y: -70)
                Circle()
                    .fill(Color(hex: "315BFF").opacity(0.20))
                    .frame(width: 170, height: 170)
                    .blur(radius: 62)
                    .offset(x: 96, y: 78)
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
        )
        .shadow(color: AppTheme.pink.opacity(0.14), radius: 28, x: 0, y: 18)
    }

    private var quickActions: some View {
        HStack(spacing: 12) {
            Button {
                Task {
                    if let firstPackage = walletVM.packages.first {
                        await walletVM.purchase(slug: firstPackage.slug)
                    }
                }
            } label: {
                Label("Add Coins", systemImage: "plus")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(AppTheme.primaryGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: AppTheme.pink.opacity(0.34), radius: 16, x: 0, y: 8)
            }
            .disabled(walletVM.packages.isEmpty || walletVM.isPurchasing)
            .buttonStyle(BounceButtonStyle())

            Button {
                showingWithdrawNotice = true
            } label: {
                Label("Withdraw", systemImage: "square.and.arrow.up")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.86))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.white.opacity(0.045))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.09), lineWidth: 1)
                    )
            }
            .buttonStyle(BounceButtonStyle())
        }
    }

    // MARK: - Packages

    private var packagesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Get Coins")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
                Spacer()
                Text("Popular")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.34))
                if walletVM.isLoading && walletVM.packages.isEmpty {
                    ProgressView().tint(AppTheme.pink).scaleEffect(0.8)
                }
            }

            if walletVM.packages.isEmpty && !walletVM.isLoading {
                Text("No packages available right now.")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundColor(AppTheme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                VStack(spacing: 12) {
                    ForEach(Array(walletVM.packages.enumerated()), id: \.element.id) { index, package in
                        packageCard(package, index: index)
                    }
                }
            }
        }
    }

    private func packageCard(_ package: CoinPackage, index: Int) -> some View {
        let isBestValue = index == 1 && walletVM.packages.count >= 2
        let isPurchasing = walletVM.isPurchasing

        return ZStack(alignment: .topTrailing) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(AppTheme.primaryGradient.opacity(0.20))
                        .frame(width: 52, height: 52)
                    Text("C")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundColor(AppTheme.pink)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("\(package.coins) Coins")
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .foregroundColor(AppTheme.textPrimary)
                    if package.bonusPct > 0 {
                        Text("Save \(package.bonusPct)%")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.40))
                    } else {
                        Text("Basic pack")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.40))
                    }
                }

                Spacer()

                Button {
                    Task { await walletVM.purchase(slug: package.slug) }
                } label: {
                    Group {
                        if isPurchasing {
                            ProgressView().tint(.white)
                                .frame(width: 74, height: 42)
                        } else {
                            Text(package.formattedPrice)
                                .font(.system(size: 15, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                                .frame(width: 74, height: 42)
                        }
                    }
                    .background(AppTheme.primaryGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: AppTheme.pink.opacity(0.4), radius: 8, x: 0, y: 3)
                }
                .disabled(isPurchasing)
                .buttonStyle(BounceButtonStyle())
            }
            .padding(18)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.white.opacity(0.045))
                    if isBestValue {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(AppTheme.primaryGradient.opacity(0.08))
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(
                        isBestValue
                            ? LinearGradient(colors: [AppTheme.pink.opacity(0.6), AppTheme.purple.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [Color.white.opacity(0.08), Color.white.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: isBestValue ? 1.5 : 1
                    )
            )
            .shadow(color: isBestValue ? AppTheme.pink.opacity(0.16) : .black.opacity(0.10), radius: 18, x: 0, y: 8)

            if isBestValue {
                Text("BEST VALUE")
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .foregroundColor(Color(hex: "1C1322"))
                    .tracking(1.5)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        LinearGradient(colors: [Color(hex: "FFD93D"), Color(hex: "FFB000")], startPoint: .leading, endPoint: .trailing)
                    )
                    .clipShape(Capsule())
                    .shadow(color: AppTheme.gold.opacity(0.42), radius: 8, x: 0, y: 3)
                    .offset(x: -16, y: -10)
            }
        }
    }

    // MARK: - Transactions

    private var transactionsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("History")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
                Spacer()
                Button {
                    showingHistory = true
                } label: {
                    Text("View All")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(AppTheme.pink)
                }
            }

            VStack(spacing: 10) {
                ForEach(walletVM.transactions.prefix(4)) { tx in
                    transactionRow(tx)
                }
            }
        }
    }

    private func transactionRow(_ tx: CoinTransaction) -> some View {
        HStack(spacing: 14) {
            transactionIcon(tx)

            VStack(alignment: .leading, spacing: 2) {
                Text(tx.typeLabel)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
                Text(tx.createdAt, format: .dateTime.month(.abbreviated).day().year())
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.white.opacity(0.40))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(tx.isCredit ? "+\(tx.amount)" : "\(tx.amount)")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundColor(txColor(for: tx))
                Text("\(tx.balanceAfter) total")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundColor(.white.opacity(0.32))
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func transactionIcon(_ tx: CoinTransaction) -> some View {
        let color = txColor(for: tx)

        return ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(color.opacity(0.15))
                .frame(width: 48, height: 48)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(color.opacity(0.20), lineWidth: 1)
                )
            Image(systemName: txIcon(for: tx))
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(color)
        }
    }

    private func txIcon(for tx: CoinTransaction) -> String {
        switch tx.type {
        case "purchase": return "creditcard.fill"
        case "welcome_bonus", "admin_credit": return "gift.fill"
        case "invite_sent": return "mappin.and.ellipse"
        case "invite_received": return "checkmark"
        case "invite_refund": return "arrow.counterclockwise"
        default: return tx.isCredit ? "checkmark" : "mappin.and.ellipse"
        }
    }

    private func txColor(for tx: CoinTransaction) -> Color {
        switch tx.type {
        case "purchase": return Color(hex: "3B82F6")
        case "welcome_bonus", "admin_credit", "invite_received", "invite_refund": return Color(hex: "30D158")
        case "admin_debit", "invite_sent": return Color(hex: "EC4899")
        default: return tx.isCredit ? Color(hex: "30D158") : Color(hex: "EC4899")
        }
    }
}

private struct CoinHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    let transactions: [CoinTransaction]
    @State private var selectedFilter: CoinHistoryFilter = .all

    private var filteredTransactions: [CoinTransaction] {
        transactions.filter { selectedFilter.includes($0) }
    }

    private var groupedTransactions: [(month: Date, transactions: [CoinTransaction])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredTransactions) { tx in
            let components = calendar.dateComponents([.year, .month], from: tx.createdAt)
            return calendar.date(from: components) ?? tx.createdAt
        }

        return grouped
            .map { ($0.key, $0.value.sorted { $0.createdAt > $1.createdAt }) }
            .sorted { $0.0 > $1.0 }
    }

    var body: some View {
        ZStack {
            historyBackground
            VStack(spacing: 18) {
                header
                filters
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        ForEach(groupedTransactions, id: \.month) { group in
                            monthSection(group)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 44)
                }
            }
            .padding(.top, 54)
        }
    }

    private var historyBackground: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "0D0B1E"), Color(hex: "160B23"), Color(hex: "0D0D0F")],
                startPoint: .top,
                endPoint: .bottom
            )
            Circle()
                .fill(AppTheme.pink.opacity(0.18))
                .frame(width: 240, height: 240)
                .blur(radius: 76)
                .offset(x: 120, y: -130)
            Circle()
                .fill(AppTheme.purple.opacity(0.16))
                .frame(width: 260, height: 260)
                .blur(radius: 86)
                .offset(x: -120, y: 380)
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            Text("History")
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundColor(.white)

            Spacer()

            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white.opacity(0.78))
                .frame(width: 36, height: 36)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(.horizontal, 20)
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(CoinHistoryFilter.allCases, id: \.self) { filter in
                    Button {
                        selectedFilter = filter
                    } label: {
                        Text(filter.title)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(selectedFilter == filter ? .white : .white.opacity(0.50))
                            .padding(.horizontal, 16)
                            .frame(height: 38)
                            .background {
                                if selectedFilter == filter {
                                    AppTheme.primaryGradient
                                } else {
                                    Color.white.opacity(0.055)
                                }
                            }
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(selectedFilter == filter ? 0 : 0.08), lineWidth: 1)
                            )
                    }
                    .buttonStyle(BounceButtonStyle())
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func monthSection(_ group: (month: Date, transactions: [CoinTransaction])) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text(group.month, format: .dateTime.month(.wide).year())
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundColor(.white.opacity(0.50))
                    .textCase(.uppercase)
                Spacer()
                Text("Net: \(netAmountText(group.transactions))")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.38))
            }

            ForEach(group.transactions) { tx in
                historyTransactionCard(tx)
            }
        }
    }

    private func historyTransactionCard(_ tx: CoinTransaction) -> some View {
        let color = txColor(for: tx)

        return HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(color.opacity(0.15))
                    .frame(width: 48, height: 48)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(color.opacity(0.22), lineWidth: 1)
                    )
                Image(systemName: txIcon(for: tx))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(color)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(tx.typeLabel)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(historyDetail(for: tx))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.40))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 5) {
                Text(tx.amount > 0 ? "+\(tx.amount)" : "\(tx.amount)")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundColor(color)
                Text("Bal: \(tx.balanceAfter)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.32))
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func netAmountText(_ transactions: [CoinTransaction]) -> String {
        let net = transactions.reduce(0) { $0 + $1.amount }
        return net >= 0 ? "+\(net)" : "\(net)"
    }

    private func historyDetail(for tx: CoinTransaction) -> String {
        let date = tx.createdAt.formatted(.dateTime.month(.abbreviated).day())
        switch tx.type {
        case "purchase":
            return "UPI · \(date)"
        case "invite_received":
            return "Invite reward · \(date)"
        case "invite_sent":
            return "Venue invite · \(date)"
        case "welcome_bonus":
            return "Welcome reward · \(date)"
        case "invite_refund":
            return "Refund · \(date)"
        default:
            return "\(tx.typeLabel) · \(date)"
        }
    }

    private func txIcon(for tx: CoinTransaction) -> String {
        switch tx.type {
        case "purchase": return "creditcard.fill"
        case "welcome_bonus", "admin_credit": return "gift.fill"
        case "invite_sent": return "mappin.and.ellipse"
        case "invite_received": return "checkmark"
        case "invite_refund": return "arrow.counterclockwise"
        default: return tx.isCredit ? "checkmark" : "mappin.and.ellipse"
        }
    }

    private func txColor(for tx: CoinTransaction) -> Color {
        switch tx.type {
        case "purchase": return Color(hex: "3B82F6")
        case "welcome_bonus", "admin_credit", "invite_received", "invite_refund": return Color(hex: "30D158")
        case "admin_debit", "invite_sent": return Color(hex: "EC4899")
        default: return tx.isCredit ? Color(hex: "30D158") : Color(hex: "EC4899")
        }
    }
}

private enum CoinHistoryFilter: CaseIterable {
    case all
    case received
    case sent
    case purchases

    var title: String {
        switch self {
        case .all: return "All"
        case .received: return "Received"
        case .sent: return "Sent"
        case .purchases: return "Purchases"
        }
    }

    func includes(_ tx: CoinTransaction) -> Bool {
        switch self {
        case .all:
            return true
        case .received:
            return tx.amount > 0 && tx.type != "purchase"
        case .sent:
            return tx.amount < 0
        case .purchases:
            return tx.type == "purchase"
        }
    }
}
