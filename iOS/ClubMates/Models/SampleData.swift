import Foundation

struct SampleData {
    static let profiles: [UserProfile] = [
        UserProfile(
            name: "Aria",
            age: 26,
            bio: "Chasing sunsets and coffee shop playlists.",
            distance: 2.3,
            prompts: [
                .init(question: "The way to my heart is...", answer: "A good vinyl record and homemade pasta"),
                .init(question: "I'm looking for...", answer: "Someone who can laugh at themselves"),
                .init(question: "My love language is...", answer: "Acts of service and midnight snack runs")
            ],
            photos: [.init(systemName: "figure.stand"), .init(systemName: "music.note.list"), .init(systemName: "fork.knife")],
            interests: ["Vinyl", "Travel", "Cooking", "Yoga", "Jazz"],
            profession: "UX Designer",
            gender: "Woman",
            height: 168,
            isVerified: true,
            lookingFor: "Dating"
        ),
        UserProfile(
            name: "Lena",
            age: 24,
            bio: "Bookworm by day, rooftop bar hopper by night.",
            distance: 0.8,
            prompts: [
                .init(question: "A fact about me that surprises people...", answer: "I've read over 300 books and counting"),
                .init(question: "My ideal Sunday...", answer: "Farmers market → brunch → long walk → wine"),
                .init(question: "I'll know it's a match if...", answer: "You have strong opinions about movies")
            ],
            photos: [.init(systemName: "figure.stand"), .init(systemName: "books.vertical.fill"), .init(systemName: "wineglass.fill")],
            interests: ["Books", "Wine", "Hiking", "Art", "Film"],
            profession: "Editor",
            gender: "Woman",
            height: 163,
            isVerified: true,
            lookingFor: "Open to Anything"
        ),
        UserProfile(
            name: "Mia",
            age: 28,
            bio: "Half adventure, half overthinking.",
            distance: 5.1,
            prompts: [
                .init(question: "I get too excited about...", answer: "Airport energy at 5am"),
                .init(question: "My biggest green flag...", answer: "I always have snacks"),
                .init(question: "Change my mind that...", answer: "A good playlist fixes everything")
            ],
            photos: [.init(systemName: "figure.stand"), .init(systemName: "camera.fill"), .init(systemName: "figure.surfing")],
            interests: ["Surfing", "Photography", "Concerts", "Pottery", "Running"],
            profession: "Photographer",
            gender: "Woman",
            height: 170,
            isVerified: false,
            lookingFor: "Something Casual"
        ),
        UserProfile(
            name: "Sophie",
            age: 25,
            bio: "Professional overthinker with a soft spot for dogs.",
            distance: 3.4,
            prompts: [
                .init(question: "Two truths and a lie...", answer: "I've climbed Kilimanjaro, I hate ice cream, I can speak 3 languages"),
                .init(question: "My most irrational fear...", answer: "Elevators AND escalators, pick a side"),
                .init(question: "I guarantee we'll get along if...", answer: "You love dogs as much as I do")
            ],
            photos: [.init(systemName: "figure.stand"), .init(systemName: "pawprint.fill"), .init(systemName: "mountain.2.fill")],
            interests: ["Dogs", "Climbing", "Languages", "Baking", "Podcasts"],
            profession: "Product Manager",
            gender: "Woman",
            height: 165,
            isVerified: true,
            lookingFor: "Friendship"
        ),
        UserProfile(
            name: "Zoe",
            age: 27,
            bio: "Making art and bad puns since '97.",
            distance: 1.2,
            prompts: [
                .init(question: "My love language is...", answer: "Sending memes at 2am"),
                .init(question: "Weirdly, I'm good at...", answer: "Naming paint colors at Home Depot"),
                .init(question: "First round is on me if...", answer: "You can beat me at darts")
            ],
            photos: [.init(systemName: "figure.stand"), .init(systemName: "paintpalette.fill"), .init(systemName: "theatermasks.fill")],
            interests: ["Ceramics", "Stand-up", "Darts", "Thrifting", "Karaoke"],
            profession: "Illustrator",
            gender: "Woman",
            height: 160,
            isVerified: false,
            lookingFor: "Dating"
        )
    ]

    static let venues: [Venue] = [
        Venue(
            name: "Pulse Room",
            neighborhood: "SoMa",
            vibe: "High-energy dance floor",
            music: "House / EDM",
            symbolName: "waveform.path.ecg",
            gradientHex: ["7C3AED", "EC4899"]
        ),
        Venue(
            name: "Neon Garden",
            neighborhood: "Mission",
            vibe: "Loungey rooftop crowd",
            music: "Afrobeat / Pop",
            symbolName: "sparkles",
            gradientHex: ["2563EB", "06B6D4"]
        ),
        Venue(
            name: "Velvet Underground",
            neighborhood: "North Beach",
            vibe: "Intimate speakeasy",
            music: "Disco / Funk",
            symbolName: "music.note.house.fill",
            gradientHex: ["0F766E", "22C55E"]
        )
    ]

    static let initialVenueAssignments: [UUID: UUID] = {
        guard !venues.isEmpty else { return [:] }

        var assignments: [UUID: UUID] = [:]
        for (index, profile) in profiles.enumerated() {
            assignments[profile.id] = venues[index % venues.count].id
        }
        return assignments
    }()

    static let myProfile = UserProfile(
        name: "Alex",
        age: 27,
        bio: "Software engineer who secretly loves baking. My sourdough is a personality trait at this point.",
        distance: 0,
        prompts: [
            .init(question: "The key to my heart...", answer: "Bring coffee, stay for the conversation"),
            .init(question: "I'm looking for someone who...", answer: "Can match my energy on both lazy Sundays and spontaneous road trips"),
            .init(question: "Unusual skill I have...", answer: "I can name every country's capital. Party trick or red flag, you decide.")
        ],
        photos: [.init(systemName: "person.fill"), .init(systemName: "laptopcomputer"), .init(systemName: "birthday.cake")],
        interests: ["Baking", "Code", "Hiking", "Concerts", "Coffee"],
        profession: "Software Engineer",
        gender: "Man",
        height: 180,
        isVerified: true,
        lookingFor: "Dating",
        preferences: DatePreferences(
            ageMin: 22,
            ageMax: 32,
            genders: ["Women"],
            heightMin: 155,
            heightMax: 185,
            verifiedOnly: false
        )
    )

    static let matches: [Match] = [
        Match(
            profile: profiles[0],
            lastMessage: "That playlist you sent is perfect 🎵",
            lastMessageTime: Date().addingTimeInterval(-300),
            isNew: false,
            unreadCount: 2
        ),
        Match(
            profile: profiles[1],
            lastMessage: "It's a match!",
            lastMessageTime: Date().addingTimeInterval(-3600),
            isNew: true,
            unreadCount: 0
        ),
        Match(
            profile: profiles[3],
            lastMessage: "Okay but which truth was the lie??",
            lastMessageTime: Date().addingTimeInterval(-7200),
            isNew: false,
            unreadCount: 1
        )
    ]

    static func chatMessages(for matchId: UUID) -> [ChatMessage] {
        [
            ChatMessage(text: "Hey! Your playlist rec was spot on 🎶", isFromMe: false, timestamp: Date().addingTimeInterval(-3600)),
            ChatMessage(text: "Right?? Glad you liked it — what's your go-to genre?", isFromMe: true, timestamp: Date().addingTimeInterval(-3500)),
            ChatMessage(text: "Honestly it depends on my mood. Right now it's a lot of indie folk", isFromMe: false, timestamp: Date().addingTimeInterval(-3400)),
            ChatMessage(text: "That playlist you sent is perfect 🎵", isFromMe: false, timestamp: Date().addingTimeInterval(-300))
        ]
    }
}
