import Foundation
import Network
import OSLog
import SwiftUI

private final class SingleResumeContinuation<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Never>?

    init(_ continuation: CheckedContinuation<Value, Never>) {
        self.continuation = continuation
    }

    func resume(returning value: Value) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()

        continuation?.resume(returning: value)
    }
}

@MainActor
class MatchesViewModel: ObservableObject {
    private struct RealtimeEventEnvelope: Decodable {
        let type: String?
    }

    struct IncomingLikeBanner: Identifiable, Equatable {
        let id = UUID()
        let profileId: UUID
        let name: String
        let isSuperLike: Bool
        let isMatch: Bool
        let matchId: UUID?
        let profile: UserProfile?
        let treat: TreatInvite?
    }

    @Published var matches: [Match]
    @Published var selectedMatch: Match?
    @Published var messages: [ChatMessage]
    @Published var newMessageText: String
    @Published var isTyping: Bool = false
    @Published var messageError: String?
    @Published var sosError: String?
    @Published var safetyError: String?
    @Published var incomingLikeBanner: IncomingLikeBanner?
    @Published var selectedIncomingLikeProfile: UserProfile?
    @Published private(set) var isSendingSOS = false
    @Published private(set) var isSubmittingSafetyAction = false
    @Published private(set) var onlineUserIDs: Set<UUID> = []

    enum IncomingLikeDecision {
        case like
        case nope

        var apiDirection: String {
            switch self {
            case .like:
                return "like"
            case .nope:
                return "nope"
            }
        }
    }

    private var threads: [UUID: [ChatMessage]]
    private let api: NetworkClient
    private var realtimeTask: URLSessionWebSocketTask?
    private var realtimeListenTask: Task<Void, Never>?
    private var realtimeHeartbeatTask: Task<Void, Never>?
    private var realtimeHandshakeTask: Task<Void, Never>?
    private var realtimeReconnectTask: Task<Void, Never>?
    private var isRealtimeConnecting = false
    private var isRealtimeReady = false
    private var matchObservationTask: Task<Void, Never>?
    private var messageObservationTask: Task<Void, Never>?
    private let pathMonitor = NWPathMonitor()
    private let pathMonitorQueue = DispatchQueue(label: "ClubMates.MatchesViewModel.PathMonitor")
    private var signOutObserver: NSObjectProtocol?
    private var pendingSwipeCardsByUserId: [UUID: Match] = [:]
    private var pendingTreatInvitesByUserId: [UUID: APITreatInvite] = [:]
    private var optimisticMessagesByMatchId: [UUID: [ChatMessage]] = [:]
    private var bannerDismissTask: Task<Void, Never>?
    private var interactionSyncTask: Task<Void, Never>?
    private var interactionSyncNeedsMatchReload = false
    private var announcedIncomingLikeUserIDs: Set<UUID> = []
    private var announcedMatchUserIDs: Set<UUID> = []
    private var knownServerMatchProfileIDs: Set<UUID> = []
    private var hasLoadedInitialServerMatches = false
    private let localStore: ChatLocalStore
    private static let realtimeLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "ClubMates",
        category: "Realtime"
    )

    private static func trace(_ message: String) {
        realtimeLogger.notice("\(message, privacy: .public)")
        #if DEBUG
        print("[RealtimeTrace] \(message)")
        #endif
    }

    private let realtimeDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = APIDateDecoding.strategy
        return decoder
    }()

    init(matches: [Match] = [], api: NetworkClient = .shared, localStore: ChatLocalStore = .shared) {
        self.matches = matches
        self.messages = []
        self.newMessageText = ""
        self.api = api
        self.localStore = localStore
        self.threads = Dictionary(uniqueKeysWithValues: matches.map { match in
            (match.id, matches.isEmpty ? [] : SampleData.chatMessages(for: match.id))
        })
        observeLocalMatches()
        Task {
            if !matches.isEmpty {
                await localStore.upsertMatches(matches)
            }
            await connectRealtime()
            await loadMatches()
            await loadIncomingSwipes()
            await loadIncomingTreatInvites()
        }
        startConnectivityMonitoring()

        signOutObserver = NotificationCenter.default.addObserver(
            forName: .appSessionDidSignOut,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleSessionSignOut()
        }
    }

    deinit {
        if let signOutObserver {
            NotificationCenter.default.removeObserver(signOutObserver)
        }
        matchObservationTask?.cancel()
        messageObservationTask?.cancel()
        bannerDismissTask?.cancel()
        interactionSyncTask?.cancel()
        interactionSyncNeedsMatchReload = false
        realtimeHandshakeTask?.cancel()
        realtimeReconnectTask?.cancel()
        realtimeHeartbeatTask?.cancel()
        realtimeListenTask?.cancel()
        realtimeTask?.cancel(with: .goingAway, reason: nil)
        pathMonitor.cancel()
    }

    private func observeLocalMatches() {
        matchObservationTask?.cancel()
        matchObservationTask = Task { [weak self] in
            guard let self else { return }
            for await cachedMatches in await localStore.observeMatches() {
                guard !Task.isCancelled else { return }
                let mergedMatches = await MainActor.run {
                    self.mergeWithPendingSwipeCards(cachedMatches)
                }
                await MainActor.run {
                    self.matches = mergedMatches
                    let matchIds = Set(mergedMatches.map(\.id))
                    self.threads = self.threads.filter { matchIds.contains($0.key) }
                    if let selectedMatch = self.selectedMatch, !matchIds.contains(selectedMatch.id) {
                        self.closeChat()
                    }
                    self.reconcileNotificationAnnouncements()
                }
            }
        }
    }

    private func observeLocalMessages(matchId: UUID) {
        messageObservationTask?.cancel()
        messageObservationTask = Task { [weak self] in
            guard let self else { return }
            for await cachedMessages in await localStore.observeMessages(matchId: matchId) {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard self.selectedMatch?.id == matchId else { return }
                    self.messages = self.mergeWithOptimisticMessages(cachedMessages, matchId: matchId)
                    self.threads[matchId] = self.messages
                }
            }
        }
    }

    @discardableResult
    func addMatch(
        for profile: UserProfile,
        matchId: UUID? = nil,
        venueId: UUID? = nil,
        venueName: String? = nil,
        shouldOpenChat: Bool = false
    ) -> Match {
        let match: Match

        if let existingMatch = matches.first(where: { $0.profile.id == profile.id }) {
            let resolvedProfile = richestProfile(profile, fallback: existingMatch.profile)
            if let matchId, existingMatch.id != matchId {
                let correctedMatch = Match(
                    id: matchId,
                    venueId: venueId ?? existingMatch.venueId,
                    venueName: venueName ?? existingMatch.venueName,
                    profile: resolvedProfile,
                    lastMessage: existingMatch.lastMessage,
                    lastMessageTime: existingMatch.lastMessageTime,
                    isNew: existingMatch.isNew,
                    unreadCount: existingMatch.unreadCount
                )
                matches.removeAll { $0.id == existingMatch.id }
                matches.insert(correctedMatch, at: 0)
                threads[matchId] = threads.removeValue(forKey: existingMatch.id) ?? []
                match = correctedMatch
            } else {
                if resolvedProfile != existingMatch.profile {
                    let updatedMatch = Match(
                        id: existingMatch.id,
                        venueId: existingMatch.venueId,
                        venueName: existingMatch.venueName,
                        profile: resolvedProfile,
                        lastMessage: existingMatch.lastMessage,
                        lastMessageTime: existingMatch.lastMessageTime,
                        isNew: existingMatch.isNew,
                        unreadCount: existingMatch.unreadCount
                    )
                    if let index = matches.firstIndex(where: { $0.id == existingMatch.id }) {
                        matches[index] = updatedMatch
                    }
                    match = updatedMatch
                } else {
                    match = existingMatch
                }
            }
        } else {
            match = Match(
                id: matchId ?? UUID(),
                venueId: venueId,
                venueName: venueName,
                profile: profile,
                lastMessage: "It's a match!",
                lastMessageTime: Date(),
                isNew: true,
                unreadCount: 0
            )
            matches.insert(match, at: 0)
            threads[match.id] = []
        }

        if shouldOpenChat {
            openChat(for: match)
        }

        Task {
            await localStore.upsertMatch(match)
        }

        return match
    }

    func openChat(for match: Match) {
        guard containsMatch(match.id) else { return }

        selectedMatch = match
        messages = []
        newMessageText = ""
        isTyping = false
        markRead(match: match)
        observeLocalMessages(matchId: match.id)

        Task {
            await loadMessages(for: match)
        }
    }

    func isPendingIncomingLike(_ match: Match) -> Bool {
        pendingSwipeCardsByUserId[match.profile.id] != nil
            || pendingTreatInvitesByUserId[match.profile.id] != nil
    }

    func pendingTreatInvite(for match: Match) -> APITreatInvite? {
        pendingTreatInvitesByUserId[match.profile.id]
    }

    var confirmedMatchProfileIDs: Set<UUID> {
        Set(matches.compactMap { match in
            isPendingIncomingLike(match) ? nil : match.profile.id
        })
    }

    func reviewIncomingLike(_ match: Match, decision: IncomingLikeDecision) {
        guard isPendingIncomingLike(match) else { return }
        guard let venueId = match.venueId else {
            safetyError = "This like is missing venue details. Pull to refresh and try again."
            return
        }

        pendingSwipeCardsByUserId[match.profile.id] = nil
        matches.removeAll { $0.id == match.id }
        selectedIncomingLikeProfile = nil
        reconcileNotificationAnnouncements()

        Task {
            do {
                let response = try await api.swipe(
                    targetUserId: match.profile.id,
                    venueId: venueId,
                    direction: decision.apiDirection
                )

                if decision == .like, response.isMatch {
                    let venueName = await resolveVenueName(venueId)
                    let promotedMatch = Match(
                        id: response.matchId ?? match.id,
                        venueId: venueId,
                        venueName: venueName,
                        profile: match.profile,
                        lastMessage: "It's a match!",
                        lastMessageTime: Date(),
                        isNew: true,
                        unreadCount: 0
                    )
                    matches.insert(promotedMatch, at: 0)
                    threads[promotedMatch.id] = threads[promotedMatch.id, default: []]
                    await localStore.upsertMatch(promotedMatch)
                    showMatchBannerIfNeeded(profile: match.profile, matchId: promotedMatch.id)
                }

                safetyError = nil
            } catch {
                safetyError = error.localizedDescription
                await loadIncomingSwipes()
                await loadIncomingTreatInvites()
            }
        }
    }

    func reviewTreatInvite(_ match: Match, accept: Bool) {
        guard let invite = pendingTreatInvitesByUserId[match.profile.id] else { return }

        pendingTreatInvitesByUserId[match.profile.id] = nil
        matches.removeAll { $0.id == match.id }
        selectedIncomingLikeProfile = nil
        reconcileNotificationAnnouncements()

        Task {
            do {
                if accept {
                    let response = try await api.acceptTreatInvite(inviteId: invite.id)
                    let venueName = await resolveVenueName(invite.venueId)
                    let promotedMatch = Match(
                        id: response.matchId,
                        venueId: invite.venueId,
                        venueName: venueName,
                        profile: match.profile,
                        lastMessage: "It's a match!",
                        lastMessageTime: Date(),
                        isNew: true,
                        unreadCount: 0
                    )
                    matches.insert(promotedMatch, at: 0)
                    threads[promotedMatch.id] = []
                    await localStore.upsertMatch(promotedMatch)
                    await loadMatches()
                    showMatchBannerIfNeeded(profile: match.profile, matchId: promotedMatch.id)
                } else {
                    try await api.declineTreatInvite(inviteId: invite.id)
                }
                safetyError = nil
            } catch {
                safetyError = error.localizedDescription
                await loadIncomingTreatInvites()
            }
        }
    }

    func handleNewMatchTap(_ match: Match) {
        guard containsMatch(match.id) else { return }
        selectedIncomingLikeProfile = match.profile
    }

    func presentProfileSheet(for profile: UserProfile) {
        selectedIncomingLikeProfile = profile
    }

    func closeChat() {
        selectedMatch = nil
        messages = []
        newMessageText = ""
        isTyping = false
        messageObservationTask?.cancel()
        messageObservationTask = nil
    }

    func sendMessage() {
        guard let selectedMatch, containsMatch(selectedMatch.id) else { return }

        let text = newMessageText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }

        let matchId = selectedMatch.id
        let message = ChatMessage(text: text, isFromMe: true)

        optimisticMessagesByMatchId[matchId, default: []].append(message)
        messages = mergeWithOptimisticMessages(messages.filter { !optimisticMessagesByMatchId[matchId, default: []].map(\.id).contains($0.id) }, matchId: matchId)
        newMessageText = ""
        updateLastMessage(for: matchId, text: text)

        Task {
            do {
                let response = try await api.sendMessage(matchId: matchId, body: text)
                removeOptimisticMessage(id: message.id, from: matchId)
                await localStore.upsertMessage(response.message)
                await localStore.updateLastMessage(matchId: matchId, text: response.message.body, timestamp: response.message.createdAt)
                messageError = nil
            } catch {
                if await reconcileSentMessage(message, text: text, in: matchId, after: error) {
                    messageError = nil
                    return
                }

                removeOptimisticMessage(id: message.id, from: matchId)
                if self.selectedMatch?.id == matchId && newMessageText.isEmpty {
                    newMessageText = text
                }
                messageError = error.localizedDescription
            }
        }
    }

    func unmatch(_ match: Match) {
        unmatch(matchID: match.id)
    }

    func unmatch(matchID: UUID) {
        guard containsMatch(matchID) else { return }
        removeMatchLocally(matchID: matchID)

        Task {
            do {
                try await api.unmatch(matchId: matchID)
                await loadMatches()
            } catch {
                safetyError = error.localizedDescription
                await loadMatches()
            }
        }
    }

    func triggerSOS(for match: Match) async {
        guard !isSendingSOS else { return }

        isSendingSOS = true
        defer { isSendingSOS = false }

        do {
            _ = try await api.triggerSOS(
                source: "chat",
                venueId: match.venueId,
                matchId: match.id,
                message: "Emergency SOS triggered from chat."
            )
            sosError = nil
        } catch {
            sosError = error.localizedDescription
        }
    }

    func block(_ match: Match) async -> Bool {
        guard !isSubmittingSafetyAction else { return false }

        isSubmittingSafetyAction = true
        defer { isSubmittingSafetyAction = false }

        do {
            try await api.blockUser(userId: match.profile.id)
            SafetyVisibilityStore.hide(match.profile.id)
            safetyError = nil
            unmatch(matchID: match.id)
            return true
        } catch {
            safetyError = error.localizedDescription
            return false
        }
    }

    func reportSpam(_ match: Match, reason: String) async -> Bool {
        guard !isSubmittingSafetyAction else { return false }

        isSubmittingSafetyAction = true
        defer { isSubmittingSafetyAction = false }

        do {
            try await api.reportUser(
                userId: match.profile.id,
                matchId: match.id,
                category: "spam",
                reason: reason,
                details: "Reported from chat."
            )
            SafetyVisibilityStore.hide(match.profile.id)
            safetyError = nil
            unmatch(matchID: match.id)
            return true
        } catch {
            safetyError = error.localizedDescription
            return false
        }
    }

    func refreshMatchesNow() async {
        await loadMatches()
        await loadIncomingSwipes()
        await loadIncomingTreatInvites()
    }

    func resumeRealtimeAndSync() async {
        if let realtimeTask {
            let isAlive = await Self.sendPing(on: realtimeTask)
            if !isAlive {
                handleRealtimeDisconnect(task: realtimeTask, reason: "Foreground health check failed")
            }
        }
        await connectRealtime()
        await refreshMatchesNow()
    }

    private func loadMatches() async {
        do {
            let hadCachedMatches = await localStore.hasCachedMatches()
            let response = try await api.matches()
            let activeMatches = response.matches.filter { $0.deletedAt == nil }.map(\.match)
            announceNewServerMatchesIfNeeded(activeMatches)

            await localStore.replaceMatches(activeMatches)

            let mergedMatches = mergeWithPendingSwipeCards(activeMatches)
            matches = mergedMatches
            let matchIds = Set(mergedMatches.map(\.id))
            threads = threads.filter { matchIds.contains($0.key) }
            if let selectedMatch, !matchIds.contains(selectedMatch.id) {
                closeChat()
            }
            reconcileNotificationAnnouncements()

            if !hadCachedMatches {
                for match in activeMatches {
                    await loadMessages(for: match, forceFullSync: true)
                }
            }
        } catch {
            // Keep cached DB state visible when the network is temporarily unavailable.
        }
    }

    private func announceNewServerMatchesIfNeeded(_ loadedMatches: [Match]) {
        let loadedProfileIDs = Set(loadedMatches.map { $0.profile.id })
        defer {
            knownServerMatchProfileIDs = loadedProfileIDs
            hasLoadedInitialServerMatches = true
        }

        guard hasLoadedInitialServerMatches else { return }

        for match in loadedMatches where !knownServerMatchProfileIDs.contains(match.profile.id) {
            showMatchBannerIfNeeded(profile: match.profile, matchId: match.id)
        }
    }

    private func loadIncomingSwipes() async {
        do {
            let response = try await api.incomingSwipes()
            var latestByUserId: [UUID: IncomingSwipe] = [:]
            for swipe in response.swipes {
                latestByUserId[swipe.profile.id] = swipe
            }

            // Drop cards no longer present in server incoming list.
            pendingSwipeCardsByUserId = pendingSwipeCardsByUserId.filter { userId, _ in
                latestByUserId[userId] != nil
            }

            for swipe in latestByUserId.values {
                let shouldAnnounce = pendingSwipeCardsByUserId[swipe.profile.id] == nil
                let event = ChatRealtimeEvent(
                    type: "swipe.received",
                    message: nil,
                    matchId: nil,
                    tempId: nil,
                    serverId: nil,
                    readerId: nil,
                    upToMessageId: nil,
                    userId: nil,
                    online: nil,
                    userIds: nil,
                    profile: swipe.profile,
                    direction: swipe.direction,
                    isMatch: false,
                    venueId: swipe.venueId,
                    inviteId: nil,
                    treatType: nil,
                    intent: nil,
                    createdAt: nil,
                    status: nil
                )
                upsertSwipeNotification(
                    profile: swipe.profile,
                    event: event,
                    shouldAnnounce: shouldAnnounce
                )
            }
            reconcileNotificationAnnouncements()
        } catch {
            // Keep websocket-driven state when polling temporarily fails.
        }
    }

    private func loadIncomingTreatInvites() async {
        do {
            let response = try await api.incomingTreatInvites()
            let latestByUserId = Dictionary(
                response.invites.compactMap { invite in
                    invite.profile.map { ($0.id, invite) }
                },
                uniquingKeysWith: { first, _ in first }
            )
            pendingTreatInvitesByUserId = pendingTreatInvitesByUserId.filter {
                latestByUserId[$0.key] != nil
            }

            for (userId, invite) in latestByUserId {
                guard let apiProfile = invite.profile else { continue }
                pendingTreatInvitesByUserId[userId] = invite
                upsertTreatInvite(invite, profile: apiProfile)
            }
            reconcileNotificationAnnouncements()
        } catch {
            // Keep websocket-driven invite cards when polling temporarily fails.
        }
    }

    private func mergeWithPendingSwipeCards(_ serverMatches: [Match]) -> [Match] {
        let serverProfileIDs = Set(serverMatches.map { $0.profile.id })
        pendingSwipeCardsByUserId = pendingSwipeCardsByUserId.filter { userId, _ in
            !SafetyVisibilityStore.isHidden(userId) && !serverProfileIDs.contains(userId)
        }
        pendingTreatInvitesByUserId = pendingTreatInvitesByUserId.filter { userId, _ in
            !SafetyVisibilityStore.isHidden(userId) && !serverProfileIDs.contains(userId)
        }

        let inviteCards = pendingTreatInvitesByUserId.values.compactMap { invite -> Match? in
            guard let profile = invite.profile?.userProfile else { return nil }
            return Match(
                id: invite.id,
                venueId: invite.venueId,
                venueName: nil,
                profile: profile,
                lastMessage: "\(invite.treatType.emoji) \(profile.name) wants to \(invite.treatType.notificationNoun)",
                lastMessageTime: invite.createdAt,
                isNew: true,
                unreadCount: 0
            )
        }
        let pendingCards = (Array(pendingSwipeCardsByUserId.values) + inviteCards)
            .filter { !serverProfileIDs.contains($0.profile.id) }

        return (serverMatches + pendingCards).sorted { $0.lastMessageTime > $1.lastMessageTime }
    }

    private func fullestKnownProfile(for profileID: UUID, fallback: UserProfile) -> UserProfile {
        let candidates = matches.map(\.profile)
            + pendingSwipeCardsByUserId.values.map(\.profile)
            + [fallback]

        return candidates
            .filter { $0.id == profileID }
            .max { lhs, rhs in
                profileRichnessScore(lhs) < profileRichnessScore(rhs)
            } ?? fallback
    }

    private func richestProfile(_ profile: UserProfile, fallback: UserProfile) -> UserProfile {
        guard profile.id == fallback.id else { return profile }
        return profileRichnessScore(profile) >= profileRichnessScore(fallback) ? profile : fallback
    }

    private func profileRichnessScore(_ profile: UserProfile) -> Int {
        profile.photos.count * 100
            + profile.prompts.count * 10
            + profile.interests.count
            + (profile.bio.isEmpty ? 0 : 5)
    }

    private func loadMessages(for match: Match, forceFullSync: Bool = false) async {
        do {
            let cursor = forceFullSync ? nil : await localStore.latestMessageCursor(matchId: match.id)
            let response = try await api.messages(matchId: match.id, since: cursor, limit: cursor == nil ? 50 : 100, page: 1)
            if cursor == nil {
                await localStore.replaceMessages(response.messages, matchId: match.id)
            } else {
                await localStore.upsertMessages(response.messages, matchId: match.id)
            }
        } catch {
            // Cached messages remain available offline.
        }
    }

    private func connectRealtime() async {
        guard realtimeTask == nil, !isRealtimeConnecting else { return }
        isRealtimeConnecting = true
        defer { isRealtimeConnecting = false }

        do {
            let url = try await api.webSocketURL()
            guard realtimeTask == nil else { return }

            let task = URLSession.shared.webSocketTask(with: url)
            realtimeTask = task
            isRealtimeReady = false
            task.resume()
            startRealtimeHandshakeWatchdog(for: task)
            startRealtimeHeartbeat(for: task)
            realtimeListenTask = Task { [weak self] in
                await self?.listenForRealtimeMessages(task: task)
            }
        } catch {
            Self.realtimeLogger.error("Connection setup failed: \(error.localizedDescription, privacy: .public)")
            scheduleRealtimeReconnect()
        }
    }

    private func startConnectivityMonitoring() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor [weak self] in
                await self?.connectRealtime()
                await self?.refreshMatchesNow()
            }
        }
        pathMonitor.start(queue: pathMonitorQueue)
    }

    private func handleSessionSignOut() {
        realtimeHeartbeatTask?.cancel()
        realtimeHeartbeatTask = nil
        realtimeHandshakeTask?.cancel()
        realtimeHandshakeTask = nil
        realtimeReconnectTask?.cancel()
        realtimeReconnectTask = nil
        realtimeListenTask?.cancel()
        realtimeListenTask = nil
        realtimeTask?.cancel(with: .goingAway, reason: nil)
        realtimeTask = nil
        isRealtimeConnecting = false
        isRealtimeReady = false
        onlineUserIDs.removeAll()
        pendingSwipeCardsByUserId.removeAll()
        pendingTreatInvitesByUserId.removeAll()
        optimisticMessagesByMatchId.removeAll()
        announcedIncomingLikeUserIDs.removeAll()
        announcedMatchUserIDs.removeAll()
        knownServerMatchProfileIDs.removeAll()
        hasLoadedInitialServerMatches = false
        incomingLikeBanner = nil
        bannerDismissTask?.cancel()
        bannerDismissTask = nil
        interactionSyncTask?.cancel()
        interactionSyncTask = nil
        interactionSyncNeedsMatchReload = false
        Task {
            await localStore.clearAll()
        }
    }

    private func listenForRealtimeMessages(task: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                handleRealtimeMessage(message)
            } catch {
                if !Task.isCancelled {
                    handleRealtimeDisconnect(task: task, error: error)
                }
                return
            }
        }
    }

    private func startRealtimeHandshakeWatchdog(for task: URLSessionWebSocketTask) {
        realtimeHandshakeTask?.cancel()
        realtimeHandshakeTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 10_000_000_000)
            } catch {
                return
            }

            guard let self, self.realtimeTask === task, !self.isRealtimeReady else { return }
            self.handleRealtimeDisconnect(task: task, reason: "Handshake timed out")
        }
    }

    private func startRealtimeHeartbeat(for task: URLSessionWebSocketTask) {
        realtimeHeartbeatTask?.cancel()
        realtimeHeartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 20_000_000_000)
                } catch {
                    return
                }

                guard !Task.isCancelled else { return }
                let isAlive = await Self.sendPing(on: task)
                if !isAlive {
                    self?.handleRealtimeDisconnect(task: task, reason: "Heartbeat failed")
                    return
                }
            }
        }
    }

    private func handleRealtimeDisconnect(
        task: URLSessionWebSocketTask,
        error: Error? = nil,
        reason: String? = nil
    ) {
        guard realtimeTask === task else { return }

        if let error {
            Self.realtimeLogger.error("Connection lost: \(error.localizedDescription, privacy: .public)")
        } else if let reason {
            Self.realtimeLogger.error("Connection lost: \(reason, privacy: .public)")
        }

        realtimeHandshakeTask?.cancel()
        realtimeHandshakeTask = nil
        realtimeHeartbeatTask?.cancel()
        realtimeHeartbeatTask = nil
        realtimeListenTask = nil
        realtimeTask = nil
        isRealtimeReady = false
        task.cancel(with: .goingAway, reason: nil)
        scheduleRealtimeReconnect()
    }

    private func scheduleRealtimeReconnect() {
        guard realtimeReconnectTask == nil else { return }

        realtimeReconnectTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 2_000_000_000)
            } catch {
                return
            }

            guard let self else { return }
            self.realtimeReconnectTask = nil
            await self.connectRealtime()
        }
    }

    nonisolated private static func sendPing(on task: URLSessionWebSocketTask) async -> Bool {
        await withCheckedContinuation { continuation in
            let continuation = SingleResumeContinuation(continuation)
            task.sendPing { error in
                continuation.resume(returning: error == nil)
            }
        }
    }

    private func handleRealtimeMessage(_ message: URLSessionWebSocketTask.Message) {
        let data: Data?
        switch message {
        case .string(let text):
            data = text.data(using: .utf8)
        case .data(let messageData):
            data = messageData
        @unknown default:
            data = nil
        }

        guard let data else {
            return
        }

        do {
            let event = try realtimeDecoder.decode(ChatRealtimeEvent.self, from: data)
            Self.realtimeLogger.debug("Received event: \(event.type, privacy: .public)")
            handleRealtimeEvent(event)
        } catch {
            let eventType = (try? realtimeDecoder.decode(RealtimeEventEnvelope.self, from: data).type)
                ?? "unknown"
            Self.realtimeLogger.error(
                "Could not decode \(eventType, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func handleRealtimeEvent(_ event: ChatRealtimeEvent) {
        switch event.type {
        case "connection.ready":
            isRealtimeReady = true
            realtimeHandshakeTask?.cancel()
            realtimeHandshakeTask = nil
            Self.trace("connection.ready")
            // Realtime events are ephemeral. Recover interactions that may have
            // happened while this client was launching or reconnecting.
            scheduleInteractionSync(includeMatches: true)
        case "message.created", "message.new":
            guard let apiMessage = event.message else { return }
            receiveRealtimeMessage(apiMessage)
        case "message.ack":
            guard let apiMessage = event.message else { return }
            Task { await localStore.upsertMessage(apiMessage) }
            removeOptimisticMessage(id: event.tempId ?? apiMessage.id, from: apiMessage.matchId)
        case "message.read", "messages.read":
            guard let matchId = event.matchId else { return }
            Task { await localStore.markMessagesRead(matchId: matchId, upToMessageId: event.upToMessageId) }
        case "match.unmatched":
            guard let matchId = event.matchId else { return }
            removeMatchLocally(matchID: matchId)
        case "safety.hidden_users_updated":
            Task { [weak self] in
                await self?.syncHiddenUsersAndRefreshMatches()
            }
        case "profile.verification.updated":
            NotificationCenter.default.post(name: .profileVerificationDidUpdate, object: nil)
        case "presence.snapshot":
            onlineUserIDs = Set(event.userIds ?? [])
        case "presence.update":
            guard let userId = event.userId, let online = event.online else { return }
            if online {
                onlineUserIDs.insert(userId)
            } else {
                onlineUserIDs.remove(userId)
            }
        case "venue.presence_changed":
            guard let venueId = event.venueId else { return }
            NotificationCenter.default.post(
                name: .venuePresenceDidChange,
                object: venueId,
                userInfo: [
                    "userId": event.userId as Any,
                    "status": event.status as Any
                ]
            )
        case "swipe.received":
            guard let profile = event.profile else {
                Self.trace("swipe.received missing profile")
                return
            }
            Self.trace(
                "swipe.received sender=\(profile.id) direction=\(event.direction ?? "nil") "
                    + "isMatch=\(event.isMatch == true) currentBanner=\(incomingLikeBanner?.profileId.uuidString ?? "nil")"
            )
            upsertSwipeNotification(profile: profile, event: event, shouldAnnounce: true)
            scheduleInteractionSync(includeMatches: event.isMatch == true)
        case "swipe.withdrawn":
            guard let userId = event.userId else {
                Self.trace("swipe.withdrawn missing userId")
                return
            }
            Self.trace("swipe.withdrawn sender=\(userId)")
            clearPendingSwipe(from: userId)
        case "invite.received":
            guard
                let profile = event.profile,
                let inviteId = event.inviteId,
                let treat = event.treatType,
                let createdAt = event.createdAt
            else { return }
            let invite = APITreatInvite(
                id: inviteId,
                venueId: event.venueId,
                treatType: treat,
                intent: event.intent ?? "If we both meet and vibe, I’m open to this treat.",
                createdAt: createdAt,
                profile: profile
            )
            pendingTreatInvitesByUserId[profile.id] = invite
            upsertTreatInvite(invite, profile: profile)
            scheduleInteractionSync()
        case "invite.accepted":
            if !upsertAcceptedInviteMatch(from: event) {
                clearPendingInviteState(inviteId: event.inviteId, matchId: event.matchId)
                Task { [weak self] in
                    await self?.loadMatches()
                }
            }
            scheduleInteractionSync(includeMatches: true)
        default:
            break
        }
    }

    @discardableResult
    private func upsertAcceptedInviteMatch(from event: ChatRealtimeEvent) -> Bool {
        guard
            let matchId = event.matchId,
            let apiProfile = event.profile
        else {
            return false
        }

        let incomingProfile = richestProfile(
            apiProfile.userProfile,
            fallback: fullestKnownProfile(for: apiProfile.id, fallback: apiProfile.userProfile)
        )
        let acceptedMatch = Match(
            id: matchId,
            venueId: event.venueId,
            venueName: nil,
            profile: incomingProfile,
            lastMessage: "It's a match!",
            lastMessageTime: event.createdAt ?? Date(),
            isNew: true,
            unreadCount: 0
        )

        clearPendingInviteState(inviteId: event.inviteId, matchId: matchId)
        pendingTreatInvitesByUserId[incomingProfile.id] = nil
        pendingSwipeCardsByUserId[incomingProfile.id] = nil
        matches.removeAll { $0.profile.id == incomingProfile.id && $0.id != matchId }

        if let existingIndex = matches.firstIndex(where: { $0.id == matchId }) {
            matches[existingIndex] = acceptedMatch
            let bumped = matches.remove(at: existingIndex)
            matches.insert(bumped, at: 0)
        } else {
            matches.insert(acceptedMatch, at: 0)
        }
        threads[matchId] = threads[matchId, default: []]
        knownServerMatchProfileIDs.insert(incomingProfile.id)

        Task {
            await localStore.upsertMatch(acceptedMatch)
        }
        reconcileNotificationAnnouncements()
        showMatchBannerIfNeeded(profile: incomingProfile, matchId: matchId)
        return true
    }

    private func clearPendingInviteState(inviteId: UUID?, matchId: UUID?) {
        let profileID = pendingTreatInvitesByUserId.first { _, invite in
            invite.id == inviteId
        }?.key

        if let profileID {
            pendingTreatInvitesByUserId[profileID] = nil
            pendingSwipeCardsByUserId[profileID] = nil
            matches.removeAll { match in
                match.profile.id == profileID && match.id != matchId
            }
            if selectedIncomingLikeProfile?.id == profileID {
                selectedIncomingLikeProfile = nil
            }
        }
        reconcileNotificationAnnouncements()
    }

    private func upsertTreatInvite(_ invite: APITreatInvite, profile: APIUserProfile) {
        let incomingProfile = profile.userProfile
        let card = Match(
            id: invite.id,
            venueId: invite.venueId,
            venueName: nil,
            profile: incomingProfile,
            lastMessage: "\(invite.treatType.emoji) \(incomingProfile.name) wants to \(invite.treatType.notificationNoun)",
            lastMessageTime: invite.createdAt,
            isNew: true,
            unreadCount: 0
        )
        pendingSwipeCardsByUserId[incomingProfile.id] = nil
        matches.removeAll { $0.profile.id == incomingProfile.id }
        matches.insert(card, at: 0)
        reconcileNotificationAnnouncements()

        if !announcedIncomingLikeUserIDs.contains(incomingProfile.id) {
            showIncomingLikeBanner(
                profileId: incomingProfile.id,
                name: incomingProfile.name,
                isSuperLike: false,
                profile: incomingProfile,
                treat: invite.treatType
            )
            announcedIncomingLikeUserIDs.insert(incomingProfile.id)
        }
    }

    private func upsertSwipeNotification(
        profile: APIUserProfile,
        event: ChatRealtimeEvent,
        shouldAnnounce: Bool
    ) {
        let compactProfile = profile.userProfile
        let incomingProfile = richestProfile(
            compactProfile,
            fallback: fullestKnownProfile(for: compactProfile.id, fallback: compactProfile)
        )
        Self.trace(
            "upsert swipe sender=\(incomingProfile.id) shouldAnnounce=\(shouldAnnounce) "
                + "alreadyAnnounced=\(announcedIncomingLikeUserIDs.contains(incomingProfile.id)) "
                + "pendingBefore=\(pendingSwipeCardsByUserId[incomingProfile.id] != nil)"
        )
        let existingMatchId = matches.first(where: { $0.profile.id == incomingProfile.id })?.id
        let resolvedMatchId = event.matchId ?? existingMatchId ?? UUID()

        let previewText: String
        if event.isMatch == true {
            previewText = "It's a match!"
        } else if event.direction == "superlike" {
            previewText = "Super liked you"
        } else {
            previewText = "Liked you"
        }

        if event.isMatch == true {
            pendingSwipeCardsByUserId[incomingProfile.id] = nil
            announcedIncomingLikeUserIDs.remove(incomingProfile.id)
            knownServerMatchProfileIDs.insert(incomingProfile.id)
            showMatchBannerIfNeeded(profile: incomingProfile, matchId: resolvedMatchId)
        } else if shouldAnnounce {
            Self.trace("showing one-way like banner sender=\(incomingProfile.id)")
            showIncomingLikeBanner(
                profileId: incomingProfile.id,
                name: incomingProfile.name,
                isSuperLike: event.direction == "superlike",
                profile: incomingProfile
            )
            announcedIncomingLikeUserIDs.insert(incomingProfile.id)
        }

        if let idx = matches.firstIndex(where: { $0.id == resolvedMatchId }) {
            let updatedMatch = Match(
                id: matches[idx].id,
                venueId: event.venueId ?? matches[idx].venueId,
                venueName: matches[idx].venueName,
                profile: incomingProfile,
                lastMessage: previewText,
                lastMessageTime: Date(),
                isNew: matches[idx].isNew,
                unreadCount: matches[idx].unreadCount
            )
            matches[idx] = updatedMatch
            let bumped = matches.remove(at: idx)
            matches.insert(bumped, at: 0)
            if event.isMatch == true {
                Task { await localStore.upsertMatch(updatedMatch) }
            }
            return
        }

        if let idx = matches.firstIndex(where: { $0.profile.id == incomingProfile.id }) {
            let updatedMatch = Match(
                id: event.matchId ?? matches[idx].id,
                venueId: event.venueId ?? matches[idx].venueId,
                venueName: matches[idx].venueName,
                profile: incomingProfile,
                lastMessage: previewText,
                lastMessageTime: Date(),
                isNew: matches[idx].isNew,
                unreadCount: matches[idx].unreadCount
            )
            matches[idx] = updatedMatch
            let bumped = matches.remove(at: idx)
            matches.insert(bumped, at: 0)
            if event.isMatch == true {
                Task { await localStore.upsertMatch(updatedMatch) }
            }
            return
        }

        let seededMatch = Match(
            id: resolvedMatchId,
            venueId: event.venueId,
            venueName: nil,
            profile: incomingProfile,
            lastMessage: previewText,
            lastMessageTime: Date(),
            isNew: true,
            unreadCount: 0
        )
        if event.isMatch == true {
            matches.insert(seededMatch, at: 0)
            Task {
                await localStore.upsertMatch(seededMatch)
            }
        } else {
            pendingSwipeCardsByUserId[incomingProfile.id] = seededMatch
            matches = mergeWithPendingSwipeCards(matches.filter { $0.profile.id != incomingProfile.id })
        }
        threads[resolvedMatchId] = threads[resolvedMatchId, default: []]
        reconcileNotificationAnnouncements()
    }

    private func clearPendingSwipe(from userId: UUID) {
        Self.trace(
            "clearing pending swipe sender=\(userId) "
                + "pendingBefore=\(pendingSwipeCardsByUserId[userId] != nil)"
        )
        pendingSwipeCardsByUserId[userId] = nil
        announcedIncomingLikeUserIDs.remove(userId)
        matches.removeAll { match in
            match.profile.id == userId && pendingTreatInvitesByUserId[userId] == nil
        }
        if incomingLikeBanner?.profileId == userId && incomingLikeBanner?.isMatch == false {
            incomingLikeBanner = nil
        }
        if selectedIncomingLikeProfile?.id == userId {
            selectedIncomingLikeProfile = nil
        }
        reconcileNotificationAnnouncements()
    }

    private func showMatchBannerIfNeeded(profile: UserProfile, matchId: UUID? = nil) {
        guard !announcedMatchUserIDs.contains(profile.id) else { return }
        showIncomingLikeBanner(
            profileId: profile.id,
            name: profile.name,
            isSuperLike: false,
            isMatch: true,
            matchId: matchId,
            profile: profile
        )
        announcedMatchUserIDs.insert(profile.id)
    }

    private func showIncomingLikeBanner(
        profileId: UUID,
        name: String,
        isSuperLike: Bool,
        isMatch: Bool = false,
        matchId: UUID? = nil,
        profile: UserProfile? = nil,
        treat: TreatInvite? = nil
    ) {
        bannerDismissTask?.cancel()
        incomingLikeBanner = IncomingLikeBanner(
            profileId: profileId,
            name: name,
            isSuperLike: isSuperLike,
            isMatch: isMatch,
            matchId: matchId,
            profile: profile,
            treat: treat
        )
        Self.trace(
            "banner assigned sender=\(profileId) bannerId=\(incomingLikeBanner?.id.uuidString ?? "nil") "
                + "isMatch=\(isMatch)"
        )
        bannerDismissTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 3_000_000_000)
            } catch {
                return
            }
            await MainActor.run {
                Self.trace("banner auto-dismiss sender=\(profileId)")
                self?.incomingLikeBanner = nil
            }
        }
    }

    private func scheduleInteractionSync(includeMatches: Bool = false) {
        interactionSyncNeedsMatchReload = interactionSyncNeedsMatchReload || includeMatches
        guard interactionSyncTask == nil else { return }

        interactionSyncTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 250_000_000)
            } catch {
                return
            }

            guard let self else { return }
            let shouldLoadMatches = self.interactionSyncNeedsMatchReload
            self.interactionSyncNeedsMatchReload = false

            if shouldLoadMatches {
                await self.loadMatches()
            }
            await self.loadIncomingSwipes()
            await self.loadIncomingTreatInvites()
            self.interactionSyncTask = nil
        }
    }

    func isUserOnline(_ userId: UUID) -> Bool {
        onlineUserIDs.contains(userId)
    }

    private func removeMatchLocally(matchID: UUID) {
        matches.removeAll { $0.id == matchID }
        threads[matchID] = nil
        optimisticMessagesByMatchId[matchID] = nil
        reconcileNotificationAnnouncements()

        Task {
            await localStore.deleteMatch(matchId: matchID)
        }

        if selectedMatch?.id == matchID {
            closeChat()
        }
    }

    private func reconcileNotificationAnnouncements() {
        let pendingProfileIDs = Set(pendingSwipeCardsByUserId.keys).union(pendingTreatInvitesByUserId.keys)
        announcedIncomingLikeUserIDs = announcedIncomingLikeUserIDs.intersection(pendingProfileIDs)

        let activeMatchProfileIDs = Set(
            matches
                .filter { !isPendingIncomingLike($0) }
                .map(\.profile.id)
        )
        announcedMatchUserIDs = announcedMatchUserIDs.intersection(activeMatchProfileIDs)
    }

    private func receiveRealtimeMessage(_ apiMessage: APIMessage) {
        let matchId = apiMessage.matchId
        let message = apiMessage.chatMessage

        if !containsMatch(matchId) {
            Task { await loadMatches() }
            return
        }

        Task {
            await localStore.upsertMessage(apiMessage)
        }
        updateLastMessage(for: matchId, text: message.text, timestamp: message.timestamp)

        guard let idx = matches.firstIndex(where: { $0.id == matchId }) else { return }
        if selectedMatch?.id == matchId {
            matches[idx].unreadCount = 0
            matches[idx].isNew = false
            if !message.isFromMe {
                markRead(match: matches[idx])
            }
        } else if !message.isFromMe {
            matches[idx].unreadCount += 1
            matches[idx].isNew = false
            Task {
                await localStore.incrementUnread(matchId: matchId)
            }
        }
    }

    private func markRead(match: Match) {
        if let idx = matches.firstIndex(where: { $0.id == match.id }) {
            matches[idx].unreadCount = 0
            matches[idx].isNew = false
        }

        Task {
            await localStore.markRead(matchId: match.id)
            try? await api.markRead(matchId: match.id)
        }
    }

    var totalUnread: Int {
        matches.reduce(0) { $0 + $1.unreadCount }
    }

    private func reconcileSentMessage(
        _ optimisticMessage: ChatMessage,
        text: String,
        in matchId: UUID,
        after error: Error
    ) async -> Bool {
        guard shouldReconcileSendFailure(error) else { return false }

        do {
            let response = try await api.messages(matchId: matchId)

            if let savedMessage = response.messages.reversed().first(where: { apiMessage in
                apiMessage.isFromMe
                    && apiMessage.body == text
                    && apiMessage.createdAt >= optimisticMessage.timestamp.addingTimeInterval(-10)
            }) {
                await localStore.replaceMessages(response.messages, matchId: matchId)
                removeOptimisticMessage(id: optimisticMessage.id, from: matchId)
                updateLastMessage(for: matchId, text: savedMessage.body, timestamp: savedMessage.createdAt)
                return true
            }

            if response.messages.contains(where: { $0.id == optimisticMessage.id }) {
                await localStore.replaceMessages(response.messages, matchId: matchId)
                removeOptimisticMessage(id: optimisticMessage.id, from: matchId)
                return true
            }
        } catch {
            if isNetworkAmbiguous(error) {
                return true
            }
        }

        return false
    }

    private func mergeWithOptimisticMessages(_ cachedMessages: [ChatMessage], matchId: UUID) -> [ChatMessage] {
        let cachedIDs = Set(cachedMessages.map(\.id))
        let optimistic = optimisticMessagesByMatchId[matchId, default: []]
            .filter { !cachedIDs.contains($0.id) }
        return (cachedMessages + optimistic).sorted { $0.timestamp < $1.timestamp }
    }

    private func removeOptimisticMessage(id: UUID, from matchId: UUID) {
        optimisticMessagesByMatchId[matchId]?.removeAll { $0.id == id }
        if optimisticMessagesByMatchId[matchId]?.isEmpty == true {
            optimisticMessagesByMatchId[matchId] = nil
        }

        if selectedMatch?.id == matchId {
            messages.removeAll { $0.id == id }
        }
    }

    private func shouldReconcileSendFailure(_ error: Error) -> Bool {
        guard let apiError = error as? APIError else { return true }

        switch apiError {
        case .networkOffline, .decodingFailed:
            return true
        case .badURL, .unauthorized, .serverError(_, _):
            return false
        }
    }

    private func isNetworkAmbiguous(_ error: Error) -> Bool {
        guard let apiError = error as? APIError else { return true }

        switch apiError {
        case .networkOffline:
            return true
        case .badURL, .unauthorized, .serverError(_, _), .decodingFailed:
            return false
        }
    }

    private func updateLastMessage(for matchId: UUID, text: String, timestamp: Date = Date()) {
        if let idx = matches.firstIndex(where: { $0.id == matchId }) {
            matches[idx].lastMessage = text
            matches[idx].lastMessageTime = timestamp
            matches.sort { $0.lastMessageTime > $1.lastMessageTime }
        }
        Task {
            await localStore.updateLastMessage(matchId: matchId, text: text, timestamp: timestamp)
        }
    }

    private func containsMatch(_ matchId: UUID) -> Bool {
        matches.contains { $0.id == matchId }
    }

    private func resolveVenueName(_ venueId: UUID?) async -> String? {
        guard let venueId else { return nil }
        return try? await api.venues().venues.first(where: { $0.id == venueId })?.name
    }

    private func syncHiddenUsersAndRefreshMatches() async {
        do {
            let response = try await api.hiddenUserIds()
            SafetyVisibilityStore.replace(with: response.userIds)
        } catch {
            // Ignore hidden-user sync failures; match reload still keeps UI consistent.
        }

        await loadMatches()
    }
}
