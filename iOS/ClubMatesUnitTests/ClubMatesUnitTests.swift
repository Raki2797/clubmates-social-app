import Foundation
import CoreGraphics
import Testing
@testable import ClubMates

@Suite("Matches ViewModel Tests", .serialized)
struct ClubMatesUnitTests {
    private let me = UUID(uuidString: "505f7fc3-2d06-4b96-aa90-6380f511ffde")!
    private let other = UUID(uuidString: "ceb38698-5a7e-47fc-9cf8-fcd1234c1c3c")!
    private let matchID = UUID(uuidString: "22c8c450-7555-4962-b661-40423d4c29df")!
    private let venueID = UUID(uuidString: "abf264f1-6cea-4cb9-bdaf-a7b9522c9d2a")!

    @Test("Block removes match locally and hides user")
    @MainActor
    func blockRemovesMatchLocally() async throws {
        SafetyVisibilityStore.replace(with: [])
        defer { SafetyVisibilityStore.replace(with: []) }

        let profile = makeProfile(id: other, name: "Fuckboy")
        let match = Match(id: matchID, venueId: venueID, profile: profile, lastMessage: "Hi", isNew: false)
        let matchPath = "/matches/\(matchID.uuidString)"

        let api = try await makeAPIClient { method, path in
            switch (method, path) {
            case ("POST", "/blocks"):
                return .json(200, ["ok": true])
            case ("DELETE", matchPath):
                return .json(200, [:])
            case ("GET", "/matches"):
                return .json(200, ["matches": []])
            default:
                return .json(200, [:])
            }
        }

        let viewModel = MatchesViewModel(matches: [match], api: api)
        let ok = await viewModel.block(match)

        #expect(ok == true)
        #expect(viewModel.matches.isEmpty)
        #expect(SafetyVisibilityStore.isHidden(other))
    }

    @Test("Report spam removes match locally and hides user")
    @MainActor
    func reportSpamRemovesMatchLocally() async throws {
        SafetyVisibilityStore.replace(with: [])
        defer { SafetyVisibilityStore.replace(with: []) }

        let profile = makeProfile(id: other, name: "Spammer")
        let match = Match(id: matchID, venueId: venueID, profile: profile, lastMessage: "Buy this", isNew: false)
        let matchPath = "/matches/\(matchID.uuidString)"

        let api = try await makeAPIClient { method, path in
            switch (method, path) {
            case ("POST", "/reports"):
                return .json(200, ["ok": true])
            case ("DELETE", matchPath):
                return .json(200, [:])
            case ("GET", "/matches"):
                return .json(200, ["matches": []])
            default:
                return .json(200, [:])
            }
        }

        let viewModel = MatchesViewModel(matches: [match], api: api)
        let ok = await viewModel.reportSpam(match, reason: "Spam links")

        #expect(ok == true)
        #expect(viewModel.matches.isEmpty)
        #expect(SafetyVisibilityStore.isHidden(other))
    }

    @Test("refreshMatchesNow loads latest server matches")
    @MainActor
    func refreshMatchesLoadsServerState() async throws {
        let expectedName = "Dhanush"

        let api = try await makeAPIClient { method, path in
            switch (method, path) {
            case ("GET", "/matches"):
                return .json(
                    200,
                    [
                        "matches": [
                            [
                                "id": self.matchID.uuidString,
                                "venueId": self.venueID.uuidString,
                                "profile": [
                                    "id": self.other.uuidString,
                                    "name": expectedName,
                                    "age": 21,
                                    "bio": "Tester",
                                    "profession": "Chef",
                                    "gender": "Male",
                                    "height": 171,
                                    "interests": ["Travel"],
                                    "isVerified": false,
                                    "photoUrl": "https://cdn.example.com/photo.jpg"
                                ],
                                "lastMessage": "Hi",
                                "lastMessageAt": "2026-05-26T12:30:00.000Z",
                                "unreadCount": 1,
                                "isNew": false
                            ]
                        ]
                    ]
                )
            default:
                return .json(200, [:])
            }
        }

        let viewModel = MatchesViewModel(matches: [], api: api)
        await viewModel.refreshMatchesNow()

        #expect(viewModel.matches.count == 1)
        #expect(viewModel.matches.first?.profile.name == expectedName)
        #expect(viewModel.matches.first?.id == matchID)
    }

    @Test("Full match sync clears stale cached matches when server is empty")
    @MainActor
    func fullMatchSyncClearsStaleCachedMatchesWhenServerIsEmpty() async throws {
        let localStore = try makeChatStore()
        let staleMatch = Match(
            id: matchID,
            venueId: venueID,
            profile: makeProfile(id: other, name: "Stale"),
            lastMessage: "Old cache",
            isNew: false
        )
        await localStore.upsertMatch(staleMatch)

        let api = try await makeAPIClient { method, path in
            switch (method, path) {
            case ("GET", "/matches"):
                return .json(200, ["matches": []])
            case ("GET", "/swipes/incoming"):
                return .json(200, ["swipes": []])
            case ("GET", "/invites/incoming"):
                return .json(200, ["invites": []])
            default:
                return .json(200, [:])
            }
        }

        let viewModel = MatchesViewModel(matches: [], api: api, localStore: localStore)
        await viewModel.refreshMatchesNow()
        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(await localStore.matches().isEmpty)
        #expect(viewModel.matches.isEmpty)
    }

    @Test("Main tab badges split new matches from unread chats")
    func mainTabBadgeCountsUseDedicatedBuckets() {
        let matches = [
            Match(profile: makeProfile(id: UUID(), name: "New"), isNew: true, unreadCount: 0),
            Match(profile: makeProfile(id: UUID(), name: "Chat One"), isNew: false, unreadCount: 2),
            Match(profile: makeProfile(id: UUID(), name: "Chat Two"), isNew: false, unreadCount: 3),
            Match(profile: makeProfile(id: UUID(), name: "New With Chat"), isNew: true, unreadCount: 1)
        ]

        #expect(MainTabView.newMatchesCount(in: matches) == 2)
        #expect(MainTabView.unreadChatCount(in: matches) == 6)
    }

    @Test("Main tab keeps visited screens loaded")
    func mainTabRetainsVisitedScreens() {
        var loadedTabs: Set<MainTabView.Tab> = [.discover]

        loadedTabs = MainTabView.loadedTabs(afterSelecting: .profile, current: loadedTabs)
        #expect(loadedTabs == [.discover, .profile])

        loadedTabs = MainTabView.loadedTabs(afterSelecting: .matches, current: loadedTabs)
        #expect(loadedTabs == [.discover, .matches, .profile])

        loadedTabs = MainTabView.loadedTabs(afterSelecting: .profile, current: loadedTabs)
        #expect(loadedTabs == [.discover, .matches, .profile])
    }

    @Test("Main tab maps matches and chat tabs to one retained matches screen")
    func mainTabMapsMatchesModes() {
        #expect(MainTabView.matchesDisplayMode(for: .matches) == .matches)
        #expect(MainTabView.matchesDisplayMode(for: .chats) == .chats)
        #expect(MainTabView.matchesDisplayMode(for: .discover) == nil)
        #expect(MainTabView.matchesDisplayMode(for: .profile) == nil)
    }

    @Test("Matches view display modes use dedicated copy")
    func matchesViewDisplayModesUseDedicatedCopy() {
        #expect(MatchesView.DisplayMode.matches.screenTitle == "Matches")
        #expect(MatchesView.DisplayMode.matches.searchPlaceholder == "Search matches")
        #expect(MatchesView.DisplayMode.chats.screenTitle == "Chat")
        #expect(MatchesView.DisplayMode.chats.searchPlaceholder == "Search by name or message")
    }

    @Test("Matches tab keeps matches after conversation starts")
    func matchesTabKeepsConversationMatches() {
        let freshMatch = Match(
            profile: makeProfile(id: UUID(), name: "Fresh"),
            lastMessage: "It's a match!",
            isNew: true
        )
        let conversationMatch = Match(
            profile: makeProfile(id: UUID(), name: "Conversation"),
            lastMessage: "Hello",
            isNew: false
        )

        let visibleMatches = MatchesView.visibleMatches([freshMatch, conversationMatch])

        #expect(visibleMatches.map(\.id) == [freshMatch.id, conversationMatch.id])
    }

    @Test("Chat tab still shows conversation matches")
    func chatTabShowsConversationMatches() {
        let freshMatch = Match(
            profile: makeProfile(id: UUID(), name: "Fresh"),
            lastMessage: "It's a match!",
            isNew: true
        )
        let conversationMatch = Match(
            profile: makeProfile(id: UUID(), name: "Conversation"),
            lastMessage: "Hello",
            isNew: false
        )

        let conversationMatches = MatchesView.conversationMatches([freshMatch, conversationMatch])

        #expect(conversationMatches.map(\.id) == [conversationMatch.id])
    }

    @Test("Matches screen separates pending likes from real matches")
    func matchesScreenSeparatesPendingLikesFromRealMatches() {
        let pendingLike = Match(
            profile: makeProfile(id: UUID(), name: "Liked You"),
            lastMessage: "Liked you",
            isNew: true
        )
        let realMatch = Match(
            profile: makeProfile(id: UUID(), name: "Matched"),
            lastMessage: "It's a match!",
            isNew: true
        )
        let matches = [pendingLike, realMatch]
        let isPending: (Match) -> Bool = { $0.id == pendingLike.id }

        #expect(MatchesView.pendingLikeMatches(matches, isPending: isPending).map(\.id) == [pendingLike.id])
        #expect(MatchesView.realMatches(matches, isPending: isPending).map(\.id) == [realMatch.id])
        #expect(MatchesView.conversationMatches(matches, isPending: isPending).isEmpty)
    }

    @Test("Tapping a match opens the full profile instead of chat")
    @MainActor
    func tappingMatchOpensProfileInsteadOfChat() async throws {
        let profile = makeProfile(id: other, name: "Dhanush")
        let match = Match(id: matchID, venueId: venueID, profile: profile, lastMessage: "Hello", isNew: false)

        let api = try await makeAPIClient { method, path in
            switch (method, path) {
            case ("GET", "/matches"):
                return .json(200, ["matches": []])
            case ("GET", "/swipes/incoming"):
                return .json(200, ["swipes": []])
            default:
                return .json(200, [:])
            }
        }

        let viewModel = MatchesViewModel(matches: [match], api: api)
        viewModel.handleNewMatchTap(match)

        #expect(viewModel.selectedIncomingLikeProfile?.id == profile.id)
        #expect(viewModel.selectedIncomingLikeProfile?.name == "Dhanush")
        #expect(viewModel.selectedMatch == nil)
    }

    @Test("Profile sheet message action is only available for real matches")
    func profileSheetMessageActionUsesRealMatchesOnly() {
        let matchedProfile = makeProfile(id: other, name: "Dhanush")
        let pendingProfile = makeProfile(id: UUID(), name: "Pending")
        let realMatch = Match(id: matchID, profile: matchedProfile, isNew: true)
        let pendingCard = Match(profile: pendingProfile, lastMessage: "Liked you", isNew: true)

        let resolvedMatch = MatchesView.messageMatch(
            for: matchedProfile.id,
            in: [pendingCard, realMatch],
            isPending: { $0.id == pendingCard.id }
        )
        let pendingMatch = MatchesView.messageMatch(
            for: pendingProfile.id,
            in: [pendingCard, realMatch],
            isPending: { $0.id == pendingCard.id }
        )

        #expect(resolvedMatch?.id == realMatch.id)
        #expect(pendingMatch == nil)
    }

    @Test("Profile refresh uses freshness window")
    @MainActor
    func profileRefreshUsesFreshnessWindow() {
        let now = Date(timeIntervalSince1970: 1_800)
        let interval: TimeInterval = 120

        #expect(AppSessionStore.shouldRefreshProfile(
            force: false,
            isInFlight: false,
            lastRefreshAt: nil,
            now: now,
            interval: interval
        ) == true)
        #expect(AppSessionStore.shouldRefreshProfile(
            force: false,
            isInFlight: false,
            lastRefreshAt: now.addingTimeInterval(-30),
            now: now,
            interval: interval
        ) == false)
        #expect(AppSessionStore.shouldRefreshProfile(
            force: false,
            isInFlight: false,
            lastRefreshAt: now.addingTimeInterval(-130),
            now: now,
            interval: interval
        ) == true)
    }

    @Test("Profile refresh skips duplicate in-flight requests")
    @MainActor
    func profileRefreshSkipsInFlightRequests() {
        let now = Date(timeIntervalSince1970: 1_800)

        #expect(AppSessionStore.shouldRefreshProfile(
            force: false,
            isInFlight: true,
            lastRefreshAt: nil,
            now: now,
            interval: 120
        ) == false)
        #expect(AppSessionStore.shouldRefreshProfile(
            force: true,
            isInFlight: true,
            lastRefreshAt: now,
            now: now,
            interval: 120
        ) == false)
        #expect(AppSessionStore.shouldRefreshProfile(
            force: true,
            isInFlight: false,
            lastRefreshAt: now,
            now: now,
            interval: 120
        ) == true)
    }

    @Test("Profile saves quietly retry only transient failures once")
    @MainActor
    func profileSaveRetriesOnlyTransientFailuresOnce() {
        #expect(AppSessionStore.shouldAutomaticallyRetryProfileSave(
            APIError.networkOffline,
            retryAttempt: 0
        ) == true)
        #expect(AppSessionStore.shouldAutomaticallyRetryProfileSave(
            APIError.serverError(503, "Unavailable"),
            retryAttempt: 0
        ) == true)
        #expect(AppSessionStore.shouldAutomaticallyRetryProfileSave(
            APIError.networkOffline,
            retryAttempt: 1
        ) == false)
        #expect(AppSessionStore.shouldAutomaticallyRetryProfileSave(
            APIError.serverError(400, "Invalid profile"),
            retryAttempt: 0
        ) == false)
        #expect(AppSessionStore.shouldAutomaticallyRetryProfileSave(
            APIError.unauthorized,
            retryAttempt: 0
        ) == false)
    }

    @Test("Photo-only profile edits skip an empty metadata patch")
    func photoOnlyProfileEditSkipsEmptyMetadataPatch() {
        let original = makeProfile(id: other, name: "Photo Tester")
        var photoOnlyEdit = original
        photoOnlyEdit.photos.append(ProfilePhoto(imageData: Data([0x01, 0x02])))

        let photoOnlyPatch = APIProfilePatchRequest(profile: photoOnlyEdit, previous: original)
        #expect(photoOnlyPatch.hasChanges == false)

        var bioEdit = original
        bioEdit.bio = "Updated bio"
        let bioPatch = APIProfilePatchRequest(profile: bioEdit, previous: original)
        #expect(bioPatch.hasChanges == true)
    }

    @Test("Main photo cannot be dragged when it is the only photo")
    func singleMainPhotoCannotBeDraggedOrMoved() {
        let photo = ProfilePhoto(id: UUID(), remoteURL: URL(string: "https://cdn.example.com/main.jpg")!)
        var photos = [photo]

        #expect(EditProfileView.canDragPhoto(at: 0, photoCount: photos.count) == false)
        #expect(EditProfileView.canMovePhoto(from: 0, to: 0, photoCount: photos.count) == false)
        #expect(EditProfileView.movePhoto(in: &photos, draggedPhotoID: photo.id, destinationID: photo.id) == false)
        #expect(photos.map(\.id) == [photo.id])
    }

    @Test("Main photo can be swapped when another photo exists")
    func mainPhotoCanMoveWhenAnotherPhotoExists() {
        let main = ProfilePhoto(id: UUID(), remoteURL: URL(string: "https://cdn.example.com/main.jpg")!)
        let second = ProfilePhoto(id: UUID(), remoteURL: URL(string: "https://cdn.example.com/second.jpg")!)
        var photos = [main, second]

        #expect(EditProfileView.canDragPhoto(at: 0, photoCount: photos.count) == true)
        #expect(EditProfileView.canMovePhoto(from: 0, to: 1, photoCount: photos.count) == true)
        #expect(EditProfileView.movePhoto(in: &photos, draggedPhotoID: main.id, destinationID: second.id) == true)
        #expect(photos.map(\.id) == [second.id, main.id])
    }

    @Test("Photo reorder ignores invalid drag targets")
    func photoReorderIgnoresInvalidTargets() {
        let first = ProfilePhoto(id: UUID(), remoteURL: URL(string: "https://cdn.example.com/first.jpg")!)
        let second = ProfilePhoto(id: UUID(), remoteURL: URL(string: "https://cdn.example.com/second.jpg")!)
        var photos = [first, second]

        #expect(EditProfileView.canDragPhoto(at: 2, photoCount: photos.count) == false)
        #expect(EditProfileView.canMovePhoto(from: 0, to: 2, photoCount: photos.count) == false)
        #expect(EditProfileView.movePhoto(in: &photos, draggedPhotoID: UUID(), destinationID: second.id) == false)
        #expect(photos.map(\.id) == [first.id, second.id])
    }

    @Test("Venue refresh keeps current card stack when roster request fails")
    @MainActor
    func venueRefreshKeepsCardsWhenRosterFails() async throws {
        SafetyVisibilityStore.replace(with: [])
        defer { SafetyVisibilityStore.replace(with: []) }

        let venue = makeVenue(id: venueID)
        let visible = makeProfile(id: other, name: "Dhanush")
        let api = try await makeAPIClient { method, path in
            switch (method, path) {
            case ("GET", "/safety/hidden-users"):
                return .json(200, ["userIds": []])
            case ("GET", "/venues"):
                return .json(200, ["venues": []])
            case ("GET", "/venues/\(self.venueID.uuidString)/roster"):
                return .json(500, ["error": "temporary"])
            default:
                return .json(200, [:])
            }
        }

        let viewModel = DiscoverViewModel(api: api)
        viewModel.testSeedVenueState(activeVenue: venue, roster: [visible], profiles: [visible])

        await viewModel.testRefreshRoster(for: venue)

        #expect(viewModel.currentVenueRoster.map(\.id) == [visible.id])
        #expect(viewModel.profiles.map(\.id) == [visible.id])
        #expect(viewModel.currentProfile?.id == visible.id)
    }

    @Test("Venue refresh keeps current card stack when discover request fails")
    @MainActor
    func venueRefreshKeepsCardsWhenDiscoverFails() async throws {
        SafetyVisibilityStore.replace(with: [])
        defer { SafetyVisibilityStore.replace(with: []) }

        let venue = makeVenue(id: venueID)
        let visible = makeProfile(id: other, name: "Dhanush")
        let api = try await makeAPIClient { method, path in
            switch (method, path) {
            case ("GET", "/safety/hidden-users"):
                return .json(200, ["userIds": []])
            case ("GET", "/venues"):
                return .json(200, ["venues": []])
            case ("GET", "/venues/\(self.venueID.uuidString)/discover"):
                return .json(500, ["error": "temporary"])
            default:
                return .json(200, [:])
            }
        }

        let viewModel = DiscoverViewModel(api: api)
        viewModel.testSeedVenueState(activeVenue: venue, roster: [visible], profiles: [visible])
        viewModel.dragOffset = CGSize(width: 24, height: 8)

        await viewModel.testRefreshDiscoverQueue(for: venue)

        #expect(viewModel.profiles.map(\.id) == [visible.id])
        #expect(viewModel.currentProfile?.id == visible.id)
        #expect(viewModel.dragOffset == CGSize(width: 24, height: 8))
    }

    @Test("Venue hidden-user sync can filter without rebuilding active queue")
    @MainActor
    func venueHiddenSyncCanFilterWithoutRebuildingCards() async throws {
        SafetyVisibilityStore.replace(with: [])
        defer { SafetyVisibilityStore.replace(with: []) }

        let venue = makeVenue(id: venueID)
        let visible = makeProfile(id: other, name: "Dhanush")
        let waiting = makeProfile(id: UUID(), name: "SaiPavan")
        let api = try await makeAPIClient { method, path in
            switch (method, path) {
            case ("GET", "/safety/hidden-users"):
                return .json(200, ["userIds": [waiting.id.uuidString]])
            case ("GET", "/venues"):
                return .json(200, ["venues": []])
            default:
                return .json(200, [:])
            }
        }

        let viewModel = DiscoverViewModel(api: api)
        viewModel.testSeedVenueState(activeVenue: venue, roster: [visible, waiting], profiles: [visible, waiting])

        await viewModel.testApplyHiddenUsers(rebuildActiveQueue: false)

        #expect(viewModel.currentVenueRoster.map(\.id) == [visible.id])
        #expect(viewModel.profiles.map(\.id) == [visible.id])
        #expect(viewModel.currentProfile?.id == visible.id)
    }

    @Test("Venue hidden-user sync can preserve current card while rebuilding")
    @MainActor
    func venueHiddenSyncPreservesCurrentCardWhenRebuilding() async throws {
        SafetyVisibilityStore.replace(with: [])
        defer { SafetyVisibilityStore.replace(with: []) }

        let venue = makeVenue(id: venueID)
        let current = makeProfile(id: other, name: "Current")
        let next = makeProfile(id: UUID(), name: "Next")
        let api = try await makeAPIClient { method, path in
            switch (method, path) {
            case ("GET", "/safety/hidden-users"):
                return .json(200, ["userIds": []])
            case ("GET", "/venues"):
                return .json(200, ["venues": []])
            default:
                return .json(200, [:])
            }
        }

        let viewModel = DiscoverViewModel(api: api)
        viewModel.testSeedVenueState(activeVenue: venue, roster: [next, current], profiles: [current, next])

        await viewModel.testApplyHiddenUsers(rebuildActiveQueue: true)

        #expect(viewModel.profiles.map(\.id) == [current.id, next.id])
        #expect(viewModel.currentProfile?.id == current.id)
    }

    @Test("Confirmed matches are removed from venue roster and cards")
    @MainActor
    func venueExcludesConfirmedMatches() async throws {
        SafetyVisibilityStore.replace(with: [])
        defer { SafetyVisibilityStore.replace(with: []) }

        let venue = makeVenue(id: venueID)
        let matched = makeProfile(id: other, name: "SaiPavan")
        let available = makeProfile(id: UUID(), name: "Available")
        let api = try await makeAPIClient { method, path in
            switch (method, path) {
            case ("GET", "/safety/hidden-users"):
                return .json(200, ["userIds": []])
            case ("GET", "/venues"):
                return .json(200, ["venues": []])
            default:
                return .json(200, [:])
            }
        }

        let viewModel = DiscoverViewModel(api: api)
        viewModel.testSeedVenueState(
            activeVenue: venue,
            roster: [matched, available],
            profiles: [matched, available]
        )

        viewModel.excludeMatchedProfiles([matched.id])

        #expect(viewModel.currentVenueRoster.map(\.id) == [available.id])
        #expect(viewModel.profiles.map(\.id) == [available.id])
        #expect(viewModel.currentProfile?.id == available.id)
        #expect(viewModel.currentVenueOccupancy == 2)
    }

    @Test("Venue discover refresh preserves current profile order and stable photos")
    @MainActor
    func venueDiscoverRefreshPreservesCurrentProfileAndPhotos() async throws {
        SafetyVisibilityStore.replace(with: [])
        defer { SafetyVisibilityStore.replace(with: []) }

        let venue = makeVenue(id: venueID)
        let photo = ProfilePhoto(id: UUID(), remoteURL: URL(string: "https://cdn.example.com/stable.jpg")!)
        let current = UserProfile(
            id: other,
            name: "Current",
            age: 24,
            bio: "Bio",
            distance: 1,
            photos: [photo],
            interests: ["Music"]
        )
        let next = makeProfile(id: UUID(), name: "Next")
        let api = try await makeAPIClient { method, path in
            switch (method, path) {
            case ("GET", "/safety/hidden-users"):
                return .json(200, ["userIds": []])
            case ("GET", "/venues"):
                return .json(200, ["venues": []])
            case ("GET", "/venues/\(self.venueID.uuidString)/discover"):
                return .json(
                    200,
                    [
                        "profiles": [
                            self.apiProfileJSON(id: next.id, name: next.name, photoUrl: "https://cdn.example.com/next.jpg"),
                            self.apiProfileJSON(id: current.id, name: current.name, photoUrl: "https://cdn.example.com/rotated.jpg")
                        ]
                    ]
                )
            default:
                return .json(200, [:])
            }
        }

        let viewModel = DiscoverViewModel(api: api)
        viewModel.testSeedVenueState(activeVenue: venue, roster: [next, current], profiles: [current, next])

        await viewModel.testRefreshDiscoverQueue(for: venue)

        #expect(viewModel.profiles.map(\.id) == [current.id, next.id])
        #expect(viewModel.currentProfile?.photos == [photo])
    }

    @Test("Dating preferences summaries use friendly defaults")
    func datingPreferencesSummariesUseFriendlyDefaults() {
        #expect(PreferencesView.lookingForSummary("") == "Open")
        #expect(PreferencesView.lookingForSummary("Friendship") == "Friendship")
        #expect(PreferencesView.genderSummary([]) == "Everyone")
        #expect(PreferencesView.genderSummary(["Men", "Women"]) == "Men, Women")
    }

    @Test("Dating preferences gender chips toggle predictably")
    func datingPreferencesGenderToggleRules() {
        #expect(PreferencesView.toggledGenderSelection(current: [], label: "Men") == ["Men"])
        #expect(PreferencesView.toggledGenderSelection(current: ["Men"], label: "Women") == ["Men", "Women"])
        #expect(PreferencesView.toggledGenderSelection(current: ["Men", "Women"], label: "Men") == ["Women"])
        #expect(PreferencesView.toggledGenderSelection(current: ["Men", "Women"], label: "Everyone").isEmpty)
    }

    @Test("Dating preferences ranges stay inside bounds and do not cross")
    func datingPreferencesRangeClampingRules() {
        #expect(PreferencesView.clampedLowerRangeValue(17, upper: 30, bounds: 18...60) == 18)
        #expect(PreferencesView.clampedLowerRangeValue(35, upper: 35, bounds: 18...60) == 34)
        #expect(PreferencesView.clampedUpperRangeValue(61, lower: 30, bounds: 18...60) == 60)
        #expect(PreferencesView.clampedUpperRangeValue(25, lower: 25, bounds: 18...60) == 26)

        #expect(PreferencesView.clampedLowerRangeValue(130, upper: 180, bounds: 140...220) == 140)
        #expect(PreferencesView.clampedUpperRangeValue(230, lower: 180, bounds: 140...220) == 220)
    }

    @Test("Dating preferences cards use consistent horizontal padding")
    func datingPreferencesCardLayoutContract() {
        #expect(PreferencesView.preferenceCardHorizontalPadding == 20)
    }
}

private extension ClubMatesUnitTests {
    func makeProfile(id: UUID, name: String) -> UserProfile {
        UserProfile(
            id: id,
            name: name,
            age: 24,
            bio: "Bio",
            distance: 1.0,
            interests: ["Music"],
            profession: "Engineer",
            gender: "Male",
            height: 170,
            isVerified: false
        )
    }

    func makeVenue(id: UUID) -> Venue {
        Venue(
            id: id,
            name: "10 Downing Street",
            city: "Hyderabad",
            neighborhood: "Jubilee Hills",
            vibe: "Lounge",
            music: "House",
            symbolName: "building.2.fill",
            gradientHex: ["#111111", "#222222"],
            latitude: 17.4349,
            longitude: 78.3996,
            checkinRadiusMeters: 200
        )
    }

    func apiProfileJSON(id: UUID, name: String, photoUrl: String? = nil) -> [String: Any] {
        var json: [String: Any] = [
            "id": id.uuidString,
            "phone": NSNull(),
            "name": name,
            "age": 24,
            "bio": "Bio",
            "profession": "Engineer",
            "gender": "Male",
            "height": 170,
            "interests": ["Music"],
            "isVerified": false,
            "profileCompleted": true,
            "verificationSelfieUrl": NSNull(),
            "prompts": [],
            "photos": [],
            "distance": 1.0,
            "hasSuperLikedMe": false,
            "lookingFor": "",
            "preferences": [
                "ageMin": 18,
                "ageMax": 60,
                "genders": [],
                "heightMin": 140,
                "heightMax": 220,
                "verifiedOnly": false
            ]
        ]
        json["photoUrl"] = photoUrl ?? NSNull()
        return json
    }

    func makeAPIClient(
        handler: @escaping @Sendable (_ method: String, _ path: String) -> MockURLProtocol.Stub
    ) async throws -> NetworkClient {
        MockURLProtocol.handler = handler

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)

        let api = NetworkClient(baseURL: URL(string: "http://clubmates.test")!, session: session)
        await api.setTokens(accessToken: "test-access", refreshToken: "test-refresh")
        return api
    }

    func makeChatStore() throws -> ChatLocalStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClubMatesMatchesViewModelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return ChatLocalStore(path: directory.appendingPathComponent("clubmates.sqlite"))
    }
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    struct Stub: Sendable {
        let statusCode: Int
        let body: Data

        static func json(_ statusCode: Int, _ object: [String: Any]) -> Stub {
            let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
            return Stub(statusCode: statusCode, body: data)
        }
    }

    static var handler: (@Sendable (_ method: String, _ path: String) -> Stub)?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard
            let method = request.httpMethod,
            let url = request.url
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let stub = Self.handler?(method, url.path) ?? .json(404, ["error": "Not Found"])
        let response = HTTPURLResponse(
            url: url,
            statusCode: stub.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
