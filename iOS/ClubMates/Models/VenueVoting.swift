import Foundation

enum VenueVotingCategory: String, CaseIterable, Identifiable, Codable {
    case male
    case female
    case lgbtq

    var id: String { rawValue }

    var title: String {
        switch self {
        case .male: return "Male"
        case .female: return "Female"
        case .lgbtq: return "LGBTQ"
        }
    }
}

enum VenueVotingPhase: String, Codable {
    case registration
    case live
    case ended
}

struct VenueVotingEntry: Identifiable, Hashable {
    let entryId: UUID
    let joinedAt: Date
    let voteCount: Int
    let rank: Int
    let hasVoted: Bool
    let isWinnerEligible: Bool
    let profile: UserProfile

    var id: UUID { entryId }
}

struct VenueVotingCompetition: Identifiable, Hashable {
    let id: UUID
    let venueId: UUID
    let category: VenueVotingCategory
    let title: String
    let phase: VenueVotingPhase
    let prizeAmountCents: Int
    let entryFeeCents: Int
    let platformFeeCents: Int
    let maxVotesPerVoter: Int
    let registrationClosesAt: Date
    let startsAt: Date
    let endsAt: Date
    let entries: [VenueVotingEntry]
    let userEntryId: UUID?
    let userVotesUsed: Int
    let userVotesRemaining: Int
    let totalVotes: Int
    let winner: VenueVotingEntry?
}

struct VenueVotingHistoryItem: Identifiable, Hashable {
    let id: UUID
    let venueId: UUID
    let venueName: String
    let category: VenueVotingCategory
    let title: String
    let prizeAmountCents: Int
    let endedAt: Date
    let totalVotes: Int
    let votesCast: Int
    let votesReceived: Int
    let userJoined: Bool
    let userWon: Bool
}
