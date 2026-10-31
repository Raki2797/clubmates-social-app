import Foundation

struct APIUserProfile: Decodable {
    struct Prompt: Decodable {
        let id: UUID?
        let question: String
        let answer: String
    }

    struct Photo: Decodable {
        let id: UUID
        let storageKey: String
        let cdnUrl: String
        let position: Int
    }

    struct APIPreferences: Decodable {
        let ageMin: Int?
        let ageMax: Int?
        let genders: [String]?
        let heightMin: Int?
        let heightMax: Int?
        let verifiedOnly: Bool?
    }

    struct APINotificationPreferences: Decodable {
        let enabled: Bool?
        let newMatch: Bool?
        let newMessage: Bool?
        let likedYou: Bool?
        let superLike: Bool?
        let venueActivity: Bool?
    }

    let id: UUID
    let phone: String?
    let name: String
    let age: Int
    let bio: String
    let profession: String
    let gender: String
    let height: Int
    let interests: [String]
    let isVerified: Bool
    let isGhostMode: Bool?
    let profileCompleted: Bool?
    let verificationSelfieUrl: String?
    let verificationFailureReason: String?
    let verificationMismatchedPhotoIds: [String]?
    let prompts: [Prompt]?
    let photos: [Photo]?
    let photoUrl: String?
    let distance: Double?
    let hasSuperLikedMe: Bool?
    let lookingFor: String?
    let preferences: APIPreferences?
    let notificationPreferences: APINotificationPreferences?

    var userProfile: UserProfile {
        let profilePhotos = (photos ?? [])
            .sorted { $0.position < $1.position }
            .compactMap { photo -> ProfilePhoto? in
                guard let url = URL(string: photo.cdnUrl) else { return nil }
                return ProfilePhoto(id: photo.id, remoteURL: url)
            }
        let compactPhoto = photoUrl.flatMap(URL.init(string:)).map { [ProfilePhoto(remoteURL: $0)] } ?? []

        let prefs = DatePreferences(
            ageMin: preferences?.ageMin ?? 18,
            ageMax: preferences?.ageMax ?? 60,
            genders: preferences?.genders ?? [],
            heightMin: preferences?.heightMin ?? 140,
            heightMax: preferences?.heightMax ?? 220,
            verifiedOnly: preferences?.verifiedOnly ?? false
        )

        let notifPrefs = NotificationPreferences(
            enabled: notificationPreferences?.enabled ?? true,
            newMatch: notificationPreferences?.newMatch ?? true,
            newMessage: notificationPreferences?.newMessage ?? true,
            likedYou: notificationPreferences?.likedYou ?? true,
            superLike: notificationPreferences?.superLike ?? true,
            venueActivity: notificationPreferences?.venueActivity ?? true
        )

        return UserProfile(
            id: id,
            name: name.isEmpty ? "New ClubMate" : name,
            age: age,
            bio: bio,
            distance: distance ?? 0,
            prompts: (prompts ?? []).map { prompt in
                UserProfile.Prompt(
                    id: prompt.id ?? UUID(),
                    question: prompt.question,
                    answer: prompt.answer
                )
            },
            photos: profilePhotos.isEmpty ? compactPhoto : profilePhotos,
            interests: interests,
            profession: profession,
            gender: gender,
            height: height,
            isVerified: isVerified,
            isGhostMode: isGhostMode ?? false,
            lookingFor: lookingFor ?? "",
            preferences: prefs,
            notificationPreferences: notifPrefs,
            verificationFailureReason: verificationFailureReason,
            verificationMismatchedPhotoIds: verificationMismatchedPhotoIds ?? []
        )
    }
}

struct APIVenue: Decodable {
    let id: UUID
    let name: String
    let city: String?
    let neighborhood: String
    let vibe: String
    let music: String
    let symbolName: String
    let gradientHex: [String]
    let latitude: Double?
    let longitude: Double?
    let checkinRadiusMeters: Int?
    let occupancy: Int

    var venue: Venue {
        Venue(
            id: id,
            name: name,
            city: city ?? "Hyderabad",
            neighborhood: neighborhood,
            vibe: vibe,
            music: music,
            symbolName: symbolName,
            gradientHex: gradientHex,
            latitude: latitude,
            longitude: longitude,
            checkinRadiusMeters: checkinRadiusMeters ?? 200
        )
    }
}

struct APIVenueVotingEntry: Decodable {
    let entryId: UUID
    let joinedAt: Date
    let voteCount: Int
    let rank: Int
    let hasVoted: Bool
    let isWinnerEligible: Bool
    let profile: APIUserProfile

    var entry: VenueVotingEntry {
        VenueVotingEntry(
            entryId: entryId,
            joinedAt: joinedAt,
            voteCount: voteCount,
            rank: rank,
            hasVoted: hasVoted,
            isWinnerEligible: isWinnerEligible,
            profile: profile.userProfile
        )
    }
}

struct APIVenueVotingCompetition: Decodable {
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
    let entries: [APIVenueVotingEntry]
    let userEntryId: UUID?
    let userVotesUsed: Int
    let userVotesRemaining: Int
    let totalVotes: Int
    let winner: APIVenueVotingEntry?

    var competition: VenueVotingCompetition {
        VenueVotingCompetition(
            id: id,
            venueId: venueId,
            category: category,
            title: title,
            phase: phase,
            prizeAmountCents: prizeAmountCents,
            entryFeeCents: entryFeeCents,
            platformFeeCents: platformFeeCents,
            maxVotesPerVoter: maxVotesPerVoter,
            registrationClosesAt: registrationClosesAt,
            startsAt: startsAt,
            endsAt: endsAt,
            entries: entries.map(\.entry),
            userEntryId: userEntryId,
            userVotesUsed: userVotesUsed,
            userVotesRemaining: userVotesRemaining,
            totalVotes: totalVotes,
            winner: winner?.entry
        )
    }
}

struct VenueVotingResponse: Decodable {
    let venueId: UUID
    let venueName: String
    let competitions: [APIVenueVotingCompetition]
}

struct VenueVotingCompetitionResponse: Decodable {
    let competition: APIVenueVotingCompetition
}

struct VenueVotingRestartResponse: Decodable {
    let competitions: [APIVenueVotingCompetition]
}

struct APIVenueVotingHistoryItem: Decodable {
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

    var historyItem: VenueVotingHistoryItem {
        VenueVotingHistoryItem(
            id: id,
            venueId: venueId,
            venueName: venueName,
            category: category,
            title: title,
            prizeAmountCents: prizeAmountCents,
            endedAt: endedAt,
            totalVotes: totalVotes,
            votesCast: votesCast,
            votesReceived: votesReceived,
            userJoined: userJoined,
            userWon: userWon
        )
    }
}

struct VenueVotingHistoryResponse: Decodable {
    let history: [APIVenueVotingHistoryItem]
}

struct APIMatch: Decodable {
    let id: UUID
    let venueId: UUID?
    let venueName: String?
    let profile: APIUserProfile
    let lastMessage: String
    let lastMessageAt: Date
    let unreadCount: Int
    let isNew: Bool
    let updatedAt: Date?
    let deletedAt: Date?

    var match: Match {
        Match(
            id: id,
            venueId: venueId,
            venueName: venueName,
            profile: profile.userProfile,
            lastMessage: lastMessage,
            lastMessageTime: lastMessageAt,
            isNew: isNew,
            unreadCount: unreadCount
        )
    }
}

struct APIMessage: Decodable {
    let id: UUID
    let matchId: UUID
    let body: String
    let isFromMe: Bool
    let senderId: UUID
    let isRead: Bool
    let createdAt: Date
    let deletedAt: Date?

    var chatMessage: ChatMessage {
        ChatMessage(id: id, text: body, isFromMe: isFromMe, timestamp: createdAt)
    }
}

struct APIAuthUser: Decodable {
    let id: UUID
    let phone: String
    let profileCompleted: Bool
}

struct APIAuthResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let user: APIAuthUser
    let isNewUser: Bool?
    let restored: Bool?
}

struct OTPResponse: Decodable {
    let ok: Bool
    let userExists: Bool?
    let deletionScheduledAt: Date?
    let devCode: String?
}

struct AccountStatusResponse: Decodable {
    let userExists: Bool
    let deletionScheduledAt: Date?
}

struct UserResponse: Decodable {
    let user: APIUserProfile
}

struct VenuesResponse: Decodable {
    let venues: [APIVenue]
}

struct RosterResponse: Decodable {
    let roster: [APIUserProfile]
}

struct DiscoverResponse: Decodable {
    let profiles: [APIUserProfile]
}

struct SwipeResponse: Decodable {
    let isMatch: Bool
    let matchId: UUID?
}

struct IncomingSwipe: Decodable {
    let profile: APIUserProfile
    let direction: String
    let createdAt: Date
    let venueId: UUID?
}

struct IncomingSwipesResponse: Decodable {
    let swipes: [IncomingSwipe]
}

struct APITreatInvite: Decodable {
    let id: UUID
    let venueId: UUID?
    let treatType: TreatInvite
    let intent: String
    let createdAt: Date
    let profile: APIUserProfile?
}

struct TreatInviteResponse: Decodable {
    let invite: APITreatInvite?
    let isMatch: Bool
    let matchId: UUID?
}

struct IncomingTreatInvitesResponse: Decodable {
    let invites: [APITreatInvite]
}

struct AcceptTreatInviteResponse: Decodable {
    let matchId: UUID
}

struct MatchesResponse: Decodable {
    let matches: [APIMatch]
    let total: Int?
    let page: Int?
    let limit: Int?
}

struct MessagesResponse: Decodable {
    let messages: [APIMessage]
    let total: Int?
    let page: Int?
    let limit: Int?
}

struct MessageResponse: Decodable {
    let message: APIMessage
}

struct ProfilePhotoResponse: Decodable {
    let photo: APIUserProfile.Photo
}

struct AccountDeletionResponse: Decodable {
    let ok: Bool
    let deletionScheduledAt: Date
}

struct VerificationSelfieResponse: Decodable {
    let ok: Bool
    let selfieUrl: String?
}

struct FaceVerificationComparison: Decodable {
    let samePerson: Bool
    let confidence: Double
    let distance: Double
    let threshold: Double
    let model: String
    let detectorBackend: String
    let similarityMetric: String

    private enum CodingKeys: String, CodingKey {
        case samePerson = "same_person"
        case confidence
        case distance
        case threshold
        case model
        case detectorBackend = "detector_backend"
        case similarityMetric = "similarity_metric"
    }
}

struct EmbeddingResponse: Decodable {
    let ok: Bool
    let embedding: [Double]
    let model: String
    let dims: Int
}

struct SOSEventResponse: Decodable {
    let id: UUID
    let userId: UUID
    let venueId: UUID?
    let matchId: UUID?
    let latitude: Double?
    let longitude: Double?
    let accuracyMeters: Double?
    let source: String
    let message: String?
    let status: String
    let createdAt: Date
}

struct SOSResponse: Decodable {
    let ok: Bool
    let emergencyNumber: String
    let event: SOSEventResponse
}

struct HiddenUsersResponse: Decodable {
    let userIds: [UUID]
}

struct WalletResponse: Decodable {
    let balance: Int
    let createdAt: Date

    var wallet: Wallet { Wallet(balance: balance, createdAt: createdAt) }
}

struct CoinPackagesResponse: Decodable {
    let packages: [CoinPackage]
}

struct PurchaseResponse: Decodable {
    let ok: Bool
    let coinsAdded: Int
    let newBalance: Int
    let transactionId: UUID
}

struct TransactionsResponse: Decodable {
    let transactions: [CoinTransaction]
    let hasMore: Bool
}

struct TreatPricingResponse: Decodable {
    let pricing: [TreatPricing]
}

struct InsufficientCoinsError: Decodable {
    let error: String
    let required: Int
    let balance: Int
}

struct ChatRealtimeEvent: Decodable {
    let type: String
    let message: APIMessage?
    let matchId: UUID?
    let tempId: UUID?
    let serverId: UUID?
    let readerId: UUID?
    let upToMessageId: UUID?
    let userId: UUID?
    let online: Bool?
    let userIds: [UUID]?
    let profile: APIUserProfile?
    let direction: String?
    let isMatch: Bool?
    let venueId: UUID?
    let inviteId: UUID?
    let treatType: TreatInvite?
    let intent: String?
    let createdAt: Date?
    let status: String?
}

struct APIProfileUpdateRequest: Encodable {
    struct Prompt: Encodable {
        let question: String
        let answer: String
    }

    struct Preferences: Encodable {
        let ageMin: Int
        let ageMax: Int
        let genders: [String]
        let heightMin: Int
        let heightMax: Int
        let verifiedOnly: Bool
    }

    struct NotifPreferences: Encodable {
        let enabled: Bool
        let newMatch: Bool
        let newMessage: Bool
        let likedYou: Bool
        let superLike: Bool
        let venueActivity: Bool
    }

    let name: String
    let age: Int
    let bio: String
    let profession: String
    let gender: String
    let height: Int
    let interests: [String]
    let prompts: [Prompt]
    let lookingFor: String
    let isGhostMode: Bool
    let preferences: Preferences
    let notificationPreferences: NotifPreferences

    init(profile: UserProfile) {
        name = profile.name
        age = profile.age
        bio = profile.bio
        profession = profile.profession
        gender = profile.gender
        height = profile.height
        interests = profile.interests
        prompts = profile.prompts.map { Prompt(question: $0.question, answer: $0.answer) }
        lookingFor = profile.lookingFor
        isGhostMode = profile.isGhostMode
        preferences = Preferences(
            ageMin: profile.preferences.ageMin,
            ageMax: profile.preferences.ageMax,
            genders: profile.preferences.genders,
            heightMin: profile.preferences.heightMin,
            heightMax: profile.preferences.heightMax,
            verifiedOnly: profile.preferences.verifiedOnly
        )
        notificationPreferences = NotifPreferences(
            enabled: profile.notificationPreferences.enabled,
            newMatch: profile.notificationPreferences.newMatch,
            newMessage: profile.notificationPreferences.newMessage,
            likedYou: profile.notificationPreferences.likedYou,
            superLike: profile.notificationPreferences.superLike,
            venueActivity: profile.notificationPreferences.venueActivity
        )
    }
}

// Sends only fields that differ from the previous profile — used by PATCH /users/me
struct APIProfilePatchRequest: Encodable {
    var name: String?
    var age: Int?
    var bio: String?
    var profession: String?
    var gender: String?
    var height: Int?
    var interests: [String]?
    var lookingFor: String?
    var isGhostMode: Bool?
    var prompts: [APIProfileUpdateRequest.Prompt]?
    var preferences: APIProfileUpdateRequest.Preferences?
    var notificationPreferences: APIProfileUpdateRequest.NotifPreferences?

    var hasChanges: Bool {
        name != nil ||
            age != nil ||
            bio != nil ||
            profession != nil ||
            gender != nil ||
            height != nil ||
            interests != nil ||
            lookingFor != nil ||
            isGhostMode != nil ||
            prompts != nil ||
            preferences != nil ||
            notificationPreferences != nil
    }

    init(profile: UserProfile, previous: UserProfile) {
        if profile.name != previous.name { name = profile.name }
        if profile.age != previous.age { age = profile.age }
        if profile.bio != previous.bio { bio = profile.bio }
        if profile.profession != previous.profession { profession = profile.profession }
        if profile.gender != previous.gender { gender = profile.gender }
        if profile.height != previous.height { height = profile.height }
        if profile.interests != previous.interests { interests = profile.interests }
        if profile.lookingFor != previous.lookingFor { lookingFor = profile.lookingFor }
        if profile.isGhostMode != previous.isGhostMode { isGhostMode = profile.isGhostMode }

        // Always send prompts if they changed (backend replaces them atomically)
        if profile.prompts.map({ $0.question + $0.answer }) != previous.prompts.map({ $0.question + $0.answer }) {
            prompts = profile.prompts.map { APIProfileUpdateRequest.Prompt(question: $0.question, answer: $0.answer) }
        }

        if profile.preferences != previous.preferences {
            let p = profile.preferences
            preferences = APIProfileUpdateRequest.Preferences(
                ageMin: p.ageMin, ageMax: p.ageMax, genders: p.genders,
                heightMin: p.heightMin, heightMax: p.heightMax, verifiedOnly: p.verifiedOnly
            )
        }

        if profile.notificationPreferences != previous.notificationPreferences {
            let n = profile.notificationPreferences
            notificationPreferences = APIProfileUpdateRequest.NotifPreferences(
                enabled: n.enabled, newMatch: n.newMatch, newMessage: n.newMessage,
                likedYou: n.likedYou, superLike: n.superLike, venueActivity: n.venueActivity
            )
        }
    }
}

struct APISOSRequest: Encodable {
    let venueId: UUID?
    let matchId: UUID?
    let latitude: Double?
    let longitude: Double?
    let accuracyMeters: Double?
    let source: String
    let message: String?
}

struct APIBlockRequest: Encodable {
    let blockedUserId: UUID
}

struct APIReportRequest: Encodable {
    let reportedUserId: UUID
    let matchId: UUID?
    let category: String
    let reason: String
    let details: String?
}

enum SafetyVisibilityStore {
    static let didChangeNotification = Notification.Name("SafetyVisibilityStoreDidChange")

    private static let storageKey = "clubmates.hidden_user_ids"

    static func hide(_ userId: UUID) {
        var ids = hiddenUserIDs()
        let inserted = ids.insert(userId).inserted
        guard inserted else { return }

        UserDefaults.standard.set(ids.map(\.uuidString), forKey: storageKey)
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    static func hide(_ userIds: [UUID]) {
        guard !userIds.isEmpty else { return }

        var ids = hiddenUserIDs()
        let oldCount = ids.count
        ids.formUnion(userIds)
        guard ids.count != oldCount else { return }

        UserDefaults.standard.set(ids.map(\.uuidString), forKey: storageKey)
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    static func replace(with userIds: [UUID]) {
        let newIDs = Set(userIds)
        let currentIDs = hiddenUserIDs()
        guard newIDs != currentIDs else { return }

        UserDefaults.standard.set(newIDs.map(\.uuidString), forKey: storageKey)
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    static func isHidden(_ userId: UUID) -> Bool {
        hiddenUserIDs().contains(userId)
    }

    static func visibleProfiles(_ profiles: [UserProfile]) -> [UserProfile] {
        let ids = hiddenUserIDs()
        return profiles.filter { !ids.contains($0.id) }
    }

    private static func hiddenUserIDs() -> Set<UUID> {
        let rawValues = UserDefaults.standard.stringArray(forKey: storageKey) ?? []
        return Set(rawValues.compactMap(UUID.init(uuidString:)))
    }
}
