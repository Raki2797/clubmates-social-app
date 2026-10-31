import Foundation
import Testing
@testable import ClubMates

@Suite("Chat Local Store Tests", .serialized)
struct ChatLocalStoreTests {
    private let matchID = UUID(uuidString: "22c8c450-7555-4962-b661-40423d4c29df")!
    private let staleMatchID = UUID(uuidString: "f6c50f69-4264-4a7e-8cc2-4ee0d7990d3e")!
    private let venueID = UUID(uuidString: "abf264f1-6cea-4cb9-bdaf-a7b9522c9d2a")!
    private let userID = UUID(uuidString: "ceb38698-5a7e-47fc-9cf8-fcd1234c1c3c")!
    private let senderID = UUID(uuidString: "505f7fc3-2d06-4b96-aa90-6380f511ffde")!

    @Test("upsertMatches persists and orders matches by latest message time")
    func upsertMatchesPersistsAndOrdersMatches() async throws {
        let store = try makeStore()
        let older = makeMatch(
            id: staleMatchID,
            profile: makeProfile(id: UUID(), name: "Older"),
            lastMessage: "Earlier",
            lastMessageTime: date(seconds: 1_000)
        )
        let newer = makeMatch(
            id: matchID,
            profile: makeProfile(id: userID, name: "Dhanush"),
            lastMessage: "Latest",
            lastMessageTime: date(seconds: 2_000)
        )

        await store.upsertMatches([older, newer])
        let matches = await store.matches()

        #expect(matches.map(\.id) == [matchID, staleMatchID])
        #expect(matches.first?.profile.name == "Dhanush")
        #expect(matches.first?.lastMessage == "Latest")
        #expect(matches.first?.venueId == venueID)
    }

    @Test("replaceMatches removes stale matches and their messages")
    func replaceMatchesRemovesStaleMatchesAndMessages() async throws {
        let store = try makeStore()
        let kept = makeMatch(id: matchID, profile: makeProfile(id: userID, name: "Kept"))
        let stale = makeMatch(id: staleMatchID, profile: makeProfile(id: UUID(), name: "Stale"))
        let staleMessage = makeAPIMessage(id: UUID(), matchId: staleMatchID, body: "Remove me")

        await store.upsertMatches([kept, stale])
        await store.upsertMessage(staleMessage)
        await store.replaceMatches([kept])

        #expect(await store.matches().map(\.id) == [matchID])
        #expect(await store.messages(matchId: staleMatchID).isEmpty)
    }

    @Test("replaceMessages stores API messages in chronological order")
    func replaceMessagesStoresMessagesInChronologicalOrder() async throws {
        let store = try makeStore()
        let later = makeAPIMessage(
            id: UUID(),
            matchId: matchID,
            body: "Second",
            createdAt: date(seconds: 2_000)
        )
        let earlier = makeAPIMessage(
            id: UUID(),
            matchId: matchID,
            body: "First",
            createdAt: date(seconds: 1_000)
        )

        await store.replaceMessages([later, earlier], matchId: matchID)
        let messages = await store.messages(matchId: matchID)

        #expect(messages.map(\.text) == ["First", "Second"])
        #expect(messages.map(\.isFromMe) == [false, false])
    }

    @Test("latest cursors use cached match and message timestamps")
    func latestCursorsUseCachedTimestamps() async throws {
        let store = try makeStore()
        await store.upsertMatch(makeMatch(
            id: matchID,
            profile: makeProfile(id: userID, name: "Dhanush"),
            lastMessageTime: date(seconds: 2_000)
        ))
        await store.upsertMessage(makeAPIMessage(
            id: UUID(),
            matchId: matchID,
            body: "Cursor",
            createdAt: date(seconds: 3_000)
        ))

        #expect(await store.hasCachedMatches())
        #expect(await store.latestMatchCursor() == 2_000_000)
        #expect(await store.latestMessageCursor(matchId: matchID) == 3_000_000)
    }

    @Test("deleted API messages are removed from the local thread")
    func deletedAPIMessagesAreRemoved() async throws {
        let store = try makeStore()
        let messageID = UUID()
        await store.upsertMessage(makeAPIMessage(id: messageID, matchId: matchID, body: "Remove me"))

        await store.upsertMessage(makeAPIMessage(
            id: messageID,
            matchId: matchID,
            body: "Remove me",
            deletedAt: date(seconds: 2_000)
        ))

        #expect(await store.messages(matchId: matchID).isEmpty)
    }

    @Test("message retention keeps the latest 500 messages per thread")
    func messageRetentionKeepsLatest500Messages() async throws {
        let store = try makeStore()
        let messages = (0..<505).map { index in
            makeAPIMessage(
                id: UUID(),
                matchId: matchID,
                body: "Message \(index)",
                createdAt: date(seconds: TimeInterval(index))
            )
        }

        await store.replaceMessages(messages, matchId: matchID)
        let storedMessages = await store.messages(matchId: matchID)

        #expect(storedMessages.count == 500)
        #expect(storedMessages.first?.text == "Message 5")
        #expect(storedMessages.last?.text == "Message 504")
    }

    @Test("database version is tracked in UserDefaults")
    func databaseVersionIsTrackedInUserDefaults() async throws {
        UserDefaults.standard.removeObject(forKey: ChatLocalStore.databaseVersionKey)
        _ = try makeStore()

        #expect(UserDefaults.standard.integer(forKey: ChatLocalStore.databaseVersionKey) == ChatLocalStore.currentDatabaseVersion)
    }

    @Test("markRead clears unread count and isNew flag")
    func markReadClearsUnreadAndNewState() async throws {
        let store = try makeStore()
        let match = makeMatch(
            id: matchID,
            profile: makeProfile(id: userID, name: "Dhanush"),
            isNew: true,
            unreadCount: 3
        )

        await store.upsertMatch(match)
        await store.markRead(matchId: matchID)
        let updated = await store.matches().first

        #expect(updated?.unreadCount == 0)
        #expect(updated?.isNew == false)
    }

    @Test("deleteMatch removes match and messages")
    func deleteMatchRemovesMatchAndMessages() async throws {
        let store = try makeStore()
        await store.upsertMatch(makeMatch(id: matchID, profile: makeProfile(id: userID, name: "Dhanush")))
        await store.upsertMessage(makeAPIMessage(id: UUID(), matchId: matchID, body: "Gone"))

        await store.deleteMatch(matchId: matchID)

        #expect(await store.matches().isEmpty)
        #expect(await store.messages(matchId: matchID).isEmpty)
    }

    @Test("clearAll removes cached matches and messages")
    func clearAllRemovesCachedMatchesAndMessages() async throws {
        let store = try makeStore()
        await store.upsertMatch(makeMatch(id: matchID, profile: makeProfile(id: userID, name: "Dhanush")))
        await store.upsertMessage(makeAPIMessage(id: UUID(), matchId: matchID, body: "Clear me"))

        await store.clearAll()

        #expect(await store.matches().isEmpty)
        #expect(await store.messages(matchId: matchID).isEmpty)
    }

    @Test("observeMessages emits updates when messages change")
    func observeMessagesEmitsUpdatesWhenMessagesChange() async throws {
        let store = try makeStore()
        let stream = await store.observeMessages(matchId: matchID)
        var iterator = stream.makeAsyncIterator()

        let initial = await iterator.next()
        #expect(initial == [])

        await store.upsertMessage(makeAPIMessage(id: UUID(), matchId: matchID, body: "Hello"))

        let updated = await iterator.next()
        #expect(updated?.map(\.text) == ["Hello"])
    }
}

private extension ChatLocalStoreTests {
    func makeStore() throws -> ChatLocalStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClubMatesUnitTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return ChatLocalStore(path: directory.appendingPathComponent("clubmates.sqlite"))
    }

    func makeProfile(id: UUID, name: String) -> UserProfile {
        UserProfile(
            id: id,
            name: name,
            age: 24,
            bio: "Bio",
            distance: 1,
            prompts: [
                UserProfile.Prompt(question: "Go-to order?", answer: "Cold brew")
            ],
            photos: [ProfilePhoto(remoteURL: URL(string: "https://cdn.example.com/avatar.jpg")!)],
            interests: ["Music", "Travel"],
            profession: "Engineer",
            gender: "Male",
            height: 176,
            isVerified: true
        )
    }

    func makeMatch(
        id: UUID,
        profile: UserProfile,
        lastMessage: String = "It's a match!",
        lastMessageTime: Date = Date(timeIntervalSince1970: 1_000),
        isNew: Bool = false,
        unreadCount: Int = 0
    ) -> Match {
        Match(
            id: id,
            venueId: venueID,
            profile: profile,
            lastMessage: lastMessage,
            lastMessageTime: lastMessageTime,
            isNew: isNew,
            unreadCount: unreadCount
        )
    }

    func makeAPIMessage(
        id: UUID,
        matchId: UUID,
        body: String,
        isFromMe: Bool = false,
        isRead: Bool = false,
        createdAt: Date = Date(timeIntervalSince1970: 1_000),
        deletedAt: Date? = nil
    ) -> APIMessage {
        APIMessage(
            id: id,
            matchId: matchId,
            body: body,
            isFromMe: isFromMe,
            senderId: senderID,
            isRead: isRead,
            createdAt: createdAt,
            deletedAt: deletedAt
        )
    }

    func date(seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }
}
