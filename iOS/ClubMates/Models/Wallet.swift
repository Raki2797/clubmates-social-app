import Foundation

struct Wallet: Codable {
    let balance: Int
    let createdAt: Date
}

struct CoinPackage: Identifiable, Codable {
    let id: UUID
    let slug: String
    let coins: Int
    let priceInr: Int
    let bonusPct: Int

    var formattedPrice: String {
        let rupees = Double(priceInr) / 100.0
        return "₹\(Int(rupees))"
    }
}

struct CoinTransaction: Identifiable, Codable {
    let id: UUID
    let type: String
    let amount: Int
    let balanceAfter: Int
    let metadata: CoinTransactionMetadata?
    let createdAt: Date

    struct CoinTransactionMetadata: Codable {
        let treatType: String?
        let slug: String?
        let priceInr: Int?
    }

    var isCredit: Bool { amount > 0 }

    var typeLabel: String {
        switch type {
        case "purchase": return "Purchase"
        case "welcome_bonus": return "Welcome Bonus"
        case "invite_sent": return "Invite Sent"
        case "invite_received": return "Invite Accepted"
        case "invite_refund": return "Invite Refund"
        case "admin_credit": return "Credit"
        case "admin_debit": return "Debit"
        default: return type
        }
    }
}

struct TreatPricing: Codable {
    let treatType: String
    let senderCost: Int
    let receiverCredit: Int
}
