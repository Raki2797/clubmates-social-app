import SwiftUI

@MainActor
class WalletViewModel: ObservableObject {
    @Published var balance: Int = 0
    @Published var packages: [CoinPackage] = []
    @Published var transactions: [CoinTransaction] = []
    @Published var pricing: [TreatPricing] = []
    @Published var isLoading: Bool = false
    @Published var isPurchasing: Bool = false
    @Published var purchaseError: String?
    @Published var hasMoreTransactions: Bool = false

    private let api: NetworkClient

    init(api: NetworkClient = .shared) {
        self.api = api
    }

    func loadWallet() async {
        do {
            let response = try await api.wallet()
            balance = response.balance
        } catch {}
    }

    func loadPackages() async {
        do {
            let response = try await api.coinPackages()
            packages = response.packages
        } catch {}
    }

    func loadPricing() async {
        do {
            let response = try await api.treatPricing()
            pricing = response.pricing
        } catch {}
    }

    func loadTransactions(reset: Bool = false) async {
        if reset { transactions = [] }
        let before = reset ? nil : transactions.last?.createdAt.iso8601String
        do {
            let response = try await api.coinTransactions(limit: 20, before: before)
            if reset {
                transactions = response.transactions
            } else {
                transactions.append(contentsOf: response.transactions)
            }
            hasMoreTransactions = response.hasMore
        } catch {}
    }

    func purchase(slug: String) async {
        guard !isPurchasing else { return }
        isPurchasing = true
        purchaseError = nil
        defer { isPurchasing = false }
        do {
            let response = try await api.purchaseCoins(packageSlug: slug)
            balance = response.newBalance
            await loadTransactions(reset: true)
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    func loadAll() async {
        isLoading = true
        defer { isLoading = false }
        async let w: () = loadWallet()
        async let p: () = loadPackages()
        async let pr: () = loadPricing()
        async let t: () = loadTransactions(reset: true)
        _ = await (w, p, pr, t)
    }

    func costFor(_ treat: TreatInvite) -> Int? {
        pricing.first(where: { $0.treatType == treat.rawValue })?.senderCost
    }

    func canAfford(_ treat: TreatInvite) -> Bool {
        guard let cost = costFor(treat) else { return true }
        return balance >= cost
    }
}

private extension Date {
    var iso8601String: String {
        ISO8601DateFormatter().string(from: self)
    }
}
