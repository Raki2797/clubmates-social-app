import Foundation

struct ProfilePhoto: Identifiable, Hashable, Codable {
    let id: UUID
    var source: Source

    enum Source: Hashable, Codable {
        case systemName(String)
        case imageData(Data)
        case remoteURL(URL)

        private enum CodingKeys: String, CodingKey {
            case type
            case value
        }

        private enum SourceType: String, Codable {
            case systemName
            case imageData
            case remoteURL
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(SourceType.self, forKey: .type)

            switch type {
            case .systemName:
                self = .systemName(try container.decode(String.self, forKey: .value))
            case .imageData:
                self = .imageData(try container.decode(Data.self, forKey: .value))
            case .remoteURL:
                self = .remoteURL(try container.decode(URL.self, forKey: .value))
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)

            switch self {
            case .systemName(let name):
                try container.encode(SourceType.systemName, forKey: .type)
                try container.encode(name, forKey: .value)
            case .imageData(let data):
                try container.encode(SourceType.imageData, forKey: .type)
                try container.encode(data, forKey: .value)
            case .remoteURL(let url):
                try container.encode(SourceType.remoteURL, forKey: .type)
                try container.encode(url, forKey: .value)
            }
        }
    }

    init(id: UUID = UUID(), source: Source) {
        self.id = id
        self.source = source
    }

    init(systemName: String) {
        self.init(source: .systemName(systemName))
    }

    init(imageData: Data) {
        self.init(source: .imageData(imageData))
    }

    init(id: UUID = UUID(), remoteURL: URL) {
        self.init(id: id, source: .remoteURL(remoteURL))
    }

    var imageData: Data? {
        guard case let .imageData(data) = source else { return nil }
        return data
    }

    var systemName: String? {
        guard case let .systemName(name) = source else { return nil }
        return name
    }

    var remoteURL: URL? {
        guard case let .remoteURL(url) = source else { return nil }
        return url
    }

    var isRealImage: Bool {
        imageData != nil || remoteURL != nil
    }
}

struct NotificationPreferences: Hashable, Codable {
    var enabled: Bool
    var newMatch: Bool
    var newMessage: Bool
    var likedYou: Bool
    var superLike: Bool
    var venueActivity: Bool

    static let `default` = NotificationPreferences(
        enabled: true, newMatch: true, newMessage: true,
        likedYou: true, superLike: true, venueActivity: true
    )

    init(
        enabled: Bool = true, newMatch: Bool = true, newMessage: Bool = true,
        likedYou: Bool = true, superLike: Bool = true, venueActivity: Bool = true
    ) {
        self.enabled = enabled
        self.newMatch = newMatch
        self.newMessage = newMessage
        self.likedYou = likedYou
        self.superLike = superLike
        self.venueActivity = venueActivity
    }
}

struct DatePreferences: Hashable, Codable {
    var ageMin: Int
    var ageMax: Int
    var genders: [String]
    var heightMin: Int
    var heightMax: Int
    var verifiedOnly: Bool

    static let `default` = DatePreferences(
        ageMin: 18,
        ageMax: 60,
        genders: [],
        heightMin: 140,
        heightMax: 220,
        verifiedOnly: false
    )

    init(
        ageMin: Int = 18,
        ageMax: Int = 60,
        genders: [String] = [],
        heightMin: Int = 140,
        heightMax: Int = 220,
        verifiedOnly: Bool = false
    ) {
        self.ageMin = ageMin
        self.ageMax = ageMax
        self.genders = genders
        self.heightMin = heightMin
        self.heightMax = heightMax
        self.verifiedOnly = verifiedOnly
    }
}

struct UserProfile: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var age: Int
    var bio: String
    var distance: Double
    var prompts: [Prompt]
    var photos: [ProfilePhoto]
    var interests: [String]
    var profession: String
    var gender: String
    var height: Int
    var isVerified: Bool
    var isGhostMode: Bool
    var lookingFor: String
    var preferences: DatePreferences
    var notificationPreferences: NotificationPreferences
    var verificationFailureReason: String?
    var verificationMismatchedPhotoIds: [String]

    struct Prompt: Identifiable, Hashable, Codable {
        let id: UUID
        var question: String
        var answer: String

        init(id: UUID = UUID(), question: String, answer: String) {
            self.id = id
            self.question = question
            self.answer = answer
        }
    }

    init(
        id: UUID = UUID(),
        name: String,
        age: Int,
        bio: String,
        distance: Double,
        prompts: [Prompt] = [],
        photos: [ProfilePhoto] = [],
        interests: [String] = [],
        profession: String = "Student",
        gender: String = "Male",
        height: Int = 170,
        isVerified: Bool = false,
        isGhostMode: Bool = false,
        lookingFor: String = "",
        preferences: DatePreferences = .default,
        notificationPreferences: NotificationPreferences = .default,
        verificationFailureReason: String? = nil,
        verificationMismatchedPhotoIds: [String] = []
    ) {
        self.id = id
        self.name = name
        self.age = age
        self.bio = bio
        self.distance = distance
        self.prompts = prompts
        self.photos = photos
        self.interests = interests
        self.profession = profession
        self.gender = gender
        self.height = height
        self.isVerified = isVerified
        self.isGhostMode = isGhostMode
        self.lookingFor = lookingFor
        self.preferences = preferences
        self.notificationPreferences = notificationPreferences
        self.verificationFailureReason = verificationFailureReason
        self.verificationMismatchedPhotoIds = verificationMismatchedPhotoIds
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, age, bio, distance, prompts, photos, interests, profession, gender, height
        case isVerified, isGhostMode, lookingFor, preferences, notificationPreferences
        case verificationFailureReason, verificationMismatchedPhotoIds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        age = try container.decode(Int.self, forKey: .age)
        bio = try container.decode(String.self, forKey: .bio)
        distance = try container.decode(Double.self, forKey: .distance)
        prompts = try container.decodeIfPresent([Prompt].self, forKey: .prompts) ?? []
        photos = try container.decodeIfPresent([ProfilePhoto].self, forKey: .photos) ?? []
        interests = try container.decodeIfPresent([String].self, forKey: .interests) ?? []
        profession = try container.decodeIfPresent(String.self, forKey: .profession) ?? ""
        gender = try container.decodeIfPresent(String.self, forKey: .gender) ?? ""
        height = try container.decodeIfPresent(Int.self, forKey: .height) ?? 170
        isVerified = try container.decodeIfPresent(Bool.self, forKey: .isVerified) ?? false
        isGhostMode = try container.decodeIfPresent(Bool.self, forKey: .isGhostMode) ?? false
        lookingFor = try container.decodeIfPresent(String.self, forKey: .lookingFor) ?? ""
        preferences = try container.decodeIfPresent(DatePreferences.self, forKey: .preferences) ?? .default
        notificationPreferences = try container.decodeIfPresent(NotificationPreferences.self, forKey: .notificationPreferences) ?? .default
        verificationFailureReason = try container.decodeIfPresent(String.self, forKey: .verificationFailureReason)
        verificationMismatchedPhotoIds = try container.decodeIfPresent([String].self, forKey: .verificationMismatchedPhotoIds) ?? []
    }

    var mainPhoto: ProfilePhoto? {
        photos.first
    }

    var extraPhotos: [ProfilePhoto] {
        Array(photos.dropFirst())
    }
}

struct Match: Identifiable, Hashable, Codable {
    let id: UUID
    let venueId: UUID?
    let venueName: String?
    let profile: UserProfile
    var lastMessage: String
    var lastMessageTime: Date
    var isNew: Bool
    var unreadCount: Int

    init(
        id: UUID = UUID(),
        venueId: UUID? = nil,
        venueName: String? = nil,
        profile: UserProfile,
        lastMessage: String = "",
        lastMessageTime: Date = Date(),
        isNew: Bool = true,
        unreadCount: Int = 0
    ) {
        self.id = id
        self.venueId = venueId
        self.venueName = venueName
        self.profile = profile
        self.lastMessage = lastMessage
        self.lastMessageTime = lastMessageTime
        self.isNew = isNew
        self.unreadCount = unreadCount
    }
}

enum TreatInvite: String, CaseIterable, Identifiable, Codable {
    case drink
    case dessert
    case coffee
    case starter

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .drink: return "🥂"
        case .dessert: return "🍰"
        case .coffee: return "☕"
        case .starter: return "🍟"
        }
    }

    var title: String {
        switch self {
        case .drink: return "Drink"
        case .dessert: return "Dessert"
        case .coffee: return "Coffee"
        case .starter: return "Starter"
        }
    }

    var inviteLabel: String {
        switch self {
        case .drink: return "drink"
        case .dessert: return "dessert"
        case .coffee: return "coffee"
        case .starter: return "starter"
        }
    }

    var notificationNoun: String {
        switch self {
        case .drink: return "buy a drink"
        case .dessert: return "buy dessert"
        case .coffee: return "buy a coffee"
        case .starter: return "buy a starter"
        }
    }
}

struct ChatMessage: Identifiable, Codable, Equatable {
    let id: UUID
    var text: String
    var isFromMe: Bool
    var timestamp: Date

    init(id: UUID = UUID(), text: String, isFromMe: Bool, timestamp: Date = Date()) {
        self.id = id
        self.text = text
        self.isFromMe = isFromMe
        self.timestamp = timestamp
    }
}
