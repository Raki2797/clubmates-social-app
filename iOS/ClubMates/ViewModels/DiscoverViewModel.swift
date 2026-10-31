import CoreLocation
import SwiftUI

@MainActor
class DiscoverViewModel: ObservableObject {
    struct VenueOption: Identifiable {
        let venue: Venue
        let occupancy: Int

        var id: UUID { venue.id }
    }

    @Published private(set) var venues: [Venue] = []
    @Published private(set) var activeVenue: Venue?
    @Published private(set) var venueRosters: [UUID: [UserProfile]] = [:]
    @Published private(set) var venueOccupancy: [UUID: Int] = [:]
    @Published private(set) var latestVenueEvent: String = ""
    @Published private(set) var canUndo: Bool = false
    @Published private(set) var isCheckingIn: Bool = false
    @Published private(set) var checkInError: String?
    @Published private(set) var selectedCity: String = "Hyderabad"
    @Published private(set) var isSendingSOS: Bool = false
    @Published var sosError: String?

    @Published var profiles: [UserProfile] = []
    @Published var dragOffset: CGSize = .zero
    @Published var showMatchAlert: Bool = false
    @Published var lastMatchedProfile: UserProfile?
    @Published var lastMatchedMatchID: UUID?
    @Published var selectedRosterProfile: UserProfile?
    @Published var isLoadingRosterProfile: Bool = false
    @Published var inviteError: String?
    @Published var isTransitioning: Bool = false
    var onInsufficientCoins: (() -> Void)?

    private var swipedProfileIDsByVenue: [UUID: Set<UUID>] = [:]
    private var swipeHistoryByVenue: [UUID: [UserProfile]] = [:]
    private var clearEventTask: DispatchWorkItem?
    private var hiddenUsersObserver: NSObjectProtocol?
    private var signOutObserver: NSObjectProtocol?
    private var venuePresenceObserver: NSObjectProtocol?
    private var autoCheckoutTask: Task<Void, Never>?
    private var isAutoCheckoutCheckInFlight = false
    private var isVenueRefreshInFlight = false
    private var hasPendingVenueRefresh = false
    private var pendingVenueRefreshNeedsHiddenUsersSync = false
    private let api: NetworkClient
    private let locationProvider = VenueLocationProvider()
    private let autoCheckoutIntervalNanoseconds: UInt64 = 30_000_000_000
    private let autoCheckoutBufferMeters: Double = 35

    init(api: NetworkClient = .shared) {
        self.api = api
        hiddenUsersObserver = NotificationCenter.default.addObserver(
            forName: SafetyVisibilityStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.filterHiddenUsersFromCurrentState()
            }
        }
        venuePresenceObserver = NotificationCenter.default.addObserver(
            forName: .venuePresenceDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                await self?.handleVenuePresenceChanged(notification)
            }
        }

        signOutObserver = NotificationCenter.default.addObserver(
            forName: .appSessionDidSignOut,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.resetOnSignOut()
            }
        }

        Task {
            await syncHiddenUsers()
            await loadVenues()
        }
    }

    deinit {
        autoCheckoutTask?.cancel()
        if let hiddenUsersObserver {
            NotificationCenter.default.removeObserver(hiddenUsersObserver)
        }
        if let signOutObserver {
            NotificationCenter.default.removeObserver(signOutObserver)
        }
        if let venuePresenceObserver {
            NotificationCenter.default.removeObserver(venuePresenceObserver)
        }
    }

    private func resetOnSignOut() {
        autoCheckoutTask?.cancel()
        autoCheckoutTask = nil
        clearEventTask?.cancel()
        clearEventTask = nil
        isAutoCheckoutCheckInFlight = false
        isVenueRefreshInFlight = false
        hasPendingVenueRefresh = false
        pendingVenueRefreshNeedsHiddenUsersSync = false

        venues = []
        activeVenue = nil
        venueRosters = [:]
        venueOccupancy = [:]
        profiles = []
        swipedProfileIDsByVenue = [:]
        swipeHistoryByVenue = [:]
        dragOffset = .zero
        canUndo = false
        isCheckingIn = false
        checkInError = nil
        isSendingSOS = false
        sosError = nil
        inviteError = nil
        showMatchAlert = false
        lastMatchedProfile = nil
        lastMatchedMatchID = nil
        selectedRosterProfile = nil
        isLoadingRosterProfile = false
        latestVenueEvent = ""
    }

    var currentProfile: UserProfile? {
        SafetyVisibilityStore.visibleProfiles(profiles).first
    }

    var nextProfile: UserProfile? {
        let visibleProfiles = SafetyVisibilityStore.visibleProfiles(profiles)
        guard visibleProfiles.count > 1 else { return nil }
        return visibleProfiles[1]
    }

    var isCheckedIn: Bool {
        activeVenue != nil
    }

    var currentVenueRoster: [UserProfile] {
        guard let venueID = activeVenue?.id else { return [] }
        return SafetyVisibilityStore.visibleProfiles(venueRosters[venueID] ?? [])
    }

    var currentVenueOccupancy: Int {
        guard activeVenue != nil else { return 0 }
        return currentVenueRoster.count + 1
    }

    var venueOptions: [VenueOption] {
        venues.map { venue in
            VenueOption(
                venue: venue,
                occupancy: venueOccupancy[venue.id] ?? venueRosters[venue.id]?.count ?? 0
            )
        }
    }

    var availableCities: [String] {
        Array(Set(venues.map(\.city))).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    var selectedCityVenueOptions: [VenueOption] {
        venueOptions.filter { $0.venue.city == selectedCity }
    }

    var likeOpacity: Double {
        min(1, max(0, dragOffset.width / 70))
    }

    var nopeOpacity: Double {
        min(1, max(0, -dragOffset.width / 70))
    }

    var superLikeOpacity: Double {
        0
    }

    var backCardScale: CGFloat {
        let drag = min(abs(dragOffset.width), 120)
        return 0.94 + (drag / 120) * 0.06
    }

    var backCardOffset: CGSize {
        CGSize(width: -dragOffset.width * 0.05, height: -abs(dragOffset.width) * 0.02)
    }

    func onDragChanged(_ value: DragGesture.Value) {
        dragOffset = value.translation
    }

    func onDragEnded(_ value: DragGesture.Value) {
        let hThreshold: CGFloat = 110
        let vThreshold: CGFloat = -130

        if value.translation.width > hThreshold {
            commitSwipe(direction: CGSize(width: 700, height: -80), isLike: true)
        } else if value.translation.width < -hThreshold {
            commitSwipe(direction: CGSize(width: -700, height: 80), isLike: false)
        } else if value.translation.height < vThreshold && abs(value.translation.width) < 60 {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                dragOffset = .zero
            }
        } else {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                dragOffset = .zero
            }
        }
    }

    func checkIn(to venue: Venue) {
        guard !isCheckingIn else { return }

        Task {
            isCheckingIn = true
            checkInError = nil

            do {
                let coordinate = try await locationProvider.currentCoordinate()
                try await api.checkIn(
                    venueId: venue.id,
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude
                )

                activeVenue = venue
                startAutoCheckoutMonitoring()
                dragOffset = .zero
                rebuildQueue()
                updateUndoAvailability()
                publishVenueEvent("Checked in at \(venue.name)")
                isCheckingIn = false
                await syncHiddenUsers()
                await requestActiveVenueRefresh(refreshHiddenUsers: false)
            } catch {
                let message = error.localizedDescription
                checkInError = message
                publishVenueEvent(message)
                isCheckingIn = false
            }
        }
    }

    func selectCity(_ city: String) {
        guard selectedCity != city else { return }
        selectedCity = city
        checkInError = nil
    }

    func refreshVenuesForPicker() {
        Task {
            await loadVenues()
        }
    }

    func refreshSafetyFilters() {
        Task {
            await syncHiddenUsers()

            if activeVenue != nil {
                await requestActiveVenueRefresh(refreshHiddenUsers: false)
            }
        }
    }

    func excludeMatchedProfiles(_ profileIDs: Set<UUID>) {
        guard !profileIDs.isEmpty else { return }

        for venueID in Array(venueRosters.keys) {
            venueRosters[venueID]?.removeAll { profileIDs.contains($0.id) }
        }
        profiles.removeAll { profileIDs.contains($0.id) }

        if let activeVenue {
            venueOccupancy[activeVenue.id] = currentVenueRoster.count + 1
        }
    }

    func openRosterProfile(_ profile: UserProfile) {
        guard !isLoadingRosterProfile else { return }

        Task {
            isLoadingRosterProfile = true
            defer { isLoadingRosterProfile = false }

            // Ensure repeat taps on the same user can reopen the sheet.
            selectedRosterProfile = nil

            do {
                let response = try await api.userProfile(userId: profile.id)
                selectedRosterProfile = response.user.userProfile
            } catch {
                // Graceful fallback: show compact roster data when full profile fetch fails.
                selectedRosterProfile = profile
            }
        }
    }

    func checkOut() {
        performCheckOut(event: "You checked out")
    }

    func triggerSOS() async {
        guard !isSendingSOS else { return }

        isSendingSOS = true
        defer { isSendingSOS = false }

        let coordinate = try? await locationProvider.currentCoordinate()

        do {
            _ = try await api.triggerSOS(
                source: activeVenue == nil ? "app" : "venue",
                venueId: activeVenue?.id,
                latitude: coordinate?.latitude,
                longitude: coordinate?.longitude,
                message: "Emergency SOS triggered from venue screen."
            )
            sosError = nil
            publishVenueEvent("SOS recorded. Call 112 if you are in immediate danger.")
        } catch {
            sosError = error.localizedDescription
            publishVenueEvent("Could not record SOS. Call 112 now if you are in danger.")
        }
    }

    func swipe(_ action: SwipeDirection) {
        guard isCheckedIn else { return }

        switch action {
        case .like:
            commitSwipe(direction: CGSize(width: 700, height: -80), isLike: true)
        case .nope:
            commitSwipe(direction: CGSize(width: -700, height: 80), isLike: false)
        case .superLike:
            break
        }
    }

    func sendInvite(to profile: UserProfile, treat: TreatInvite, walletVM: WalletViewModel?) {
        guard let venue = activeVenue else { return }

        swipedProfileIDsByVenue[venue.id, default: []].insert(profile.id)
        advance(swipedProfile: profile)

        // Optimistic balance deduction
        if let cost = walletVM?.costFor(treat) {
            walletVM?.balance -= cost
        }

        Task {
            do {
                let response = try await api.sendTreatInvite(
                    targetUserId: profile.id,
                    venueId: venue.id,
                    treat: treat
                )
                inviteError = nil
                if response.isMatch {
                    lastMatchedProfile = profile
                    lastMatchedMatchID = response.matchId
                    showMatchAlert = true
                } else {
                    publishVenueEvent("Invite sent to \(profile.name)")
                }
            } catch let APIError.serverError(code, _) where code == 402 {
                // Reverse optimistic deduction and restore profile
                await walletVM?.loadWallet()
                swipedProfileIDsByVenue[venue.id, default: []].remove(profile.id)
                if !profiles.contains(where: { $0.id == profile.id }) {
                    profiles.insert(profile, at: 0)
                }
                onInsufficientCoins?()
            } catch {
                // Reverse optimistic deduction
                if let cost = walletVM?.costFor(treat) {
                    walletVM?.balance += cost
                }
                inviteError = error.localizedDescription
                swipedProfileIDsByVenue[venue.id, default: []].remove(profile.id)
                if !profiles.contains(where: { $0.id == profile.id }) {
                    profiles.insert(profile, at: 0)
                }
            }
        }
    }

    func undo() {
        guard
            let venueID = activeVenue?.id,
            var history = swipeHistoryByVenue[venueID],
            let restored = history.popLast()
        else {
            return
        }

        swipeHistoryByVenue[venueID] = history
        swipedProfileIDsByVenue[venueID, default: []].remove(restored.id)
        Task {
            try? await api.undoSwipe(targetUserId: restored.id, venueId: venueID)
        }

        if currentVenueRoster.contains(where: { $0.id == restored.id }) && !profiles.contains(where: { $0.id == restored.id }) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                profiles.insert(restored, at: 0)
                dragOffset = .zero
            }
        } else {
            rebuildQueue()
        }

        updateUndoAvailability()
    }

    private func commitSwipe(direction: CGSize, isLike: Bool) {
        guard let profile = currentProfile, let venue = activeVenue else { return }

        withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
            dragOffset = direction
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
            self.recordSwipe(for: profile)
            self.advance(swipedProfile: profile)
            self.updateUndoAvailability()

            Task {
                let direction = isLike ? "like" : "nope"
                do {
                    #if DEBUG
                    print(
                        "[SwipeTrace-iOS] sending actor swipe target=\(profile.id) "
                            + "venue=\(venue.id) direction=\(direction)"
                    )
                    #endif
                    let response = try await self.api.swipe(
                        targetUserId: profile.id,
                        venueId: venue.id,
                        direction: direction
                    )
                    #if DEBUG
                    print(
                        "[SwipeTrace-iOS] swipe response target=\(profile.id) "
                            + "isMatch=\(response.isMatch) matchId=\(response.matchId?.uuidString ?? "nil")"
                    )
                    #endif
                    if response.isMatch {
                        self.lastMatchedProfile = profile
                        self.lastMatchedMatchID = response.matchId
                        self.showMatchAlert = true
                    }
                } catch {
                    #if DEBUG
                    print(
                        "[SwipeTrace-iOS] swipe failed target=\(profile.id) "
                            + "error=\(error.localizedDescription)"
                    )
                    #endif
                    self.rebuildQueue()
                }
            }
        }
    }

    private func advance(swipedProfile: UserProfile) {
        isTransitioning = true
        profiles.removeAll { $0.id == swipedProfile.id }
        dragOffset = .zero
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.88)) {
                self.isTransitioning = false
            }
        }
    }

    private func recordSwipe(for profile: UserProfile) {
        guard let venueID = activeVenue?.id else { return }
        swipedProfileIDsByVenue[venueID, default: []].insert(profile.id)
        swipeHistoryByVenue[venueID, default: []].append(profile)
    }

    private func updateUndoAvailability() {
        guard let venueID = activeVenue?.id else {
            canUndo = false
            return
        }

        canUndo = !(swipeHistoryByVenue[venueID]?.isEmpty ?? true)
    }

    private func rebuildQueue(preserveCurrentProfileID: UUID? = nil) {
        guard let venueID = activeVenue?.id else {
            profiles = []
            return
        }

        let swipedIDs = swipedProfileIDsByVenue[venueID] ?? []
        var queue = currentVenueRoster.filter {
            !swipedIDs.contains($0.id) && !SafetyVisibilityStore.isHidden($0.id)
        }

        if
            let preserveCurrentProfileID,
            let preservedIndex = queue.firstIndex(where: { $0.id == preserveCurrentProfileID })
        {
            let preserved = queue.remove(at: preservedIndex)
            queue.insert(preserved, at: 0)
        }

        profiles = queue
    }

    private func syncHiddenUsers(rebuildActiveQueue: Bool = true) async {
        do {
            let response = try await api.hiddenUserIds()
            SafetyVisibilityStore.replace(with: response.userIds)
            filterHiddenUsersFromCurrentState(rebuildActiveQueue: rebuildActiveQueue)
        } catch {
            filterHiddenUsersFromCurrentState(rebuildActiveQueue: rebuildActiveQueue)
        }
    }

    private func filterHiddenUsersFromCurrentState(rebuildActiveQueue: Bool = true) {
        for venueID in Array(venueRosters.keys) {
            venueRosters[venueID] = SafetyVisibilityStore.visibleProfiles(venueRosters[venueID] ?? [])
        }

        profiles = SafetyVisibilityStore.visibleProfiles(profiles)

        if let activeVenue {
            venueOccupancy[activeVenue.id] = currentVenueRoster.count + 1
        }

        if rebuildActiveQueue, activeVenue != nil {
            rebuildQueue(preserveCurrentProfileID: currentProfile?.id)
        }
    }

    private func refreshVenueRosters() {
        var rosters: [UUID: [UserProfile]] = [:]

        for venue in venues {
            rosters[venue.id] = []
        }

        venueRosters = rosters

        if activeVenue != nil {
            rebuildQueue(preserveCurrentProfileID: currentProfile?.id)
        }
    }

    private func loadVenues() async {
        do {
            await syncHiddenUsers()
            let response = try await api.venues()
            venues = response.venues.map(\.venue)
            venueOccupancy = Dictionary(uniqueKeysWithValues: response.venues.map { ($0.id, $0.occupancy) })
            if !availableCities.contains(selectedCity), let firstCity = availableCities.first {
                selectedCity = firstCity
            }
            refreshVenueRosters()
        } catch {
            venues = []
            venueRosters = [:]
            venueOccupancy = [:]
        }
    }

    private func loadRoster(for venue: Venue, refreshHiddenUsers: Bool = true) async {
        do {
            if refreshHiddenUsers {
                await syncHiddenUsers(rebuildActiveQueue: false)
            }
            let response = try await api.roster(venueId: venue.id)
            let roster = SafetyVisibilityStore.visibleProfiles(response.roster.map(\.userProfile))
            venueRosters[venue.id] = roster
            venueOccupancy[venue.id] = roster.count + (activeVenue?.id == venue.id ? 1 : 0)
        } catch {
            // Keep the previous roster visible through transient refresh failures.
        }
    }

    private func loadDiscoverQueue(for venue: Venue, refreshHiddenUsers: Bool = true) async {
        do {
            if refreshHiddenUsers {
                await syncHiddenUsers(rebuildActiveQueue: false)
            }
            let response = try await api.discover(venueId: venue.id)
            let swipedIDs = swipedProfileIDsByVenue[venue.id] ?? []
            let incoming = SafetyVisibilityStore
                .visibleProfiles(response.profiles.map(\.userProfile))
                .filter { !swipedIDs.contains($0.id) }
            let preservedIncoming = preserveCurrentProfileOrder(incoming)
            let stabilized = stabilizeDiscoverProfiles(preservedIncoming)

            if stabilized != profiles {
                profiles = stabilized
                if currentProfile == nil {
                    dragOffset = .zero
                }
            }
        } catch {
            // Keep the current stack steady if a periodic refresh temporarily fails.
        }
    }

    private func preserveCurrentProfileOrder(_ queue: [UserProfile]) -> [UserProfile] {
        guard let currentID = currentProfile?.id else { return queue }
        guard let index = queue.firstIndex(where: { $0.id == currentID }) else { return queue }

        var reordered = queue
        let current = reordered.remove(at: index)
        reordered.insert(current, at: 0)
        return reordered
    }

    private func stabilizeDiscoverProfiles(_ incoming: [UserProfile]) -> [UserProfile] {
        guard !profiles.isEmpty else { return incoming }

        let existingById = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
        return incoming.map { next in
            guard let existing = existingById[next.id] else { return next }

            // Preserve equivalent rendered media, but accept a richer full-profile response.
            let stablePhotos = next.photos.count > existing.photos.count
                ? next.photos
                : (existing.photos.isEmpty ? next.photos : existing.photos)
            return UserProfile(
                id: next.id,
                name: next.name,
                age: next.age,
                bio: next.bio,
                distance: next.distance,
                prompts: next.prompts,
                photos: stablePhotos,
                interests: next.interests,
                profession: next.profession,
                gender: next.gender,
                height: next.height,
                isVerified: next.isVerified,
                lookingFor: next.lookingFor,
                preferences: next.preferences
            )
        }
    }

    private func publishVenueEvent(_ event: String) {
        latestVenueEvent = event

        clearEventTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            self?.latestVenueEvent = ""
        }
        clearEventTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: task)
    }

    private func performCheckOut(event: String) {
        let checkedOutVenue = activeVenue
        activeVenue = nil
        stopAutoCheckoutMonitoring()
        profiles = []
        dragOffset = .zero
        updateUndoAvailability()
        publishVenueEvent(event)

        if let checkedOutVenue {
            Task {
                try? await api.checkOut(venueId: checkedOutVenue.id)
                await loadVenues()
            }
        }
    }

    private func startAutoCheckoutMonitoring() {
        stopAutoCheckoutMonitoring()
        guard activeVenue != nil else { return }

        let interval = autoCheckoutIntervalNanoseconds
        autoCheckoutTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: interval)
                guard !Task.isCancelled else { break }
                await self?.evaluateAutoCheckoutIfNeeded()
            }
        }
    }

    private func stopAutoCheckoutMonitoring() {
        autoCheckoutTask?.cancel()
        autoCheckoutTask = nil
        isAutoCheckoutCheckInFlight = false
    }

    private func handleVenuePresenceChanged(_ notification: Notification) async {
        guard let changedVenueId = notification.object as? UUID else { return }
        guard activeVenue?.id == changedVenueId else { return }
        await requestActiveVenueRefresh(refreshHiddenUsers: true)
    }

    private func requestActiveVenueRefresh(refreshHiddenUsers: Bool) async {
        guard activeVenue != nil else { return }

        if isCheckingIn || isVenueRefreshInFlight {
            hasPendingVenueRefresh = true
            pendingVenueRefreshNeedsHiddenUsersSync = pendingVenueRefreshNeedsHiddenUsersSync || refreshHiddenUsers
            return
        }
        await refreshActiveVenueContent(refreshHiddenUsers: refreshHiddenUsers)
    }

    private func refreshActiveVenueContent(refreshHiddenUsers: Bool) async {
        guard let venue = activeVenue, !isCheckingIn, !isVenueRefreshInFlight else { return }

        isVenueRefreshInFlight = true

        if refreshHiddenUsers {
            await syncHiddenUsers(rebuildActiveQueue: false)
        }

        await loadRoster(for: venue, refreshHiddenUsers: false)
        await loadDiscoverQueue(for: venue, refreshHiddenUsers: false)

        isVenueRefreshInFlight = false

        guard hasPendingVenueRefresh, activeVenue != nil else { return }
        let needsHiddenUsersSync = pendingVenueRefreshNeedsHiddenUsersSync
        hasPendingVenueRefresh = false
        pendingVenueRefreshNeedsHiddenUsersSync = false
        await requestActiveVenueRefresh(refreshHiddenUsers: needsHiddenUsersSync)
    }

    private func evaluateAutoCheckoutIfNeeded() async {
        guard let venue = activeVenue else {
            stopAutoCheckoutMonitoring()
            return
        }

        guard venue.latitude != nil, venue.longitude != nil else {
            return
        }

        guard !isAutoCheckoutCheckInFlight, !isCheckingIn else {
            return
        }

        isAutoCheckoutCheckInFlight = true
        defer { isAutoCheckoutCheckInFlight = false }

        do {
            let currentCoordinate = try await locationProvider.currentCoordinate()
            guard let distanceMeters = distanceFromVenue(venue, userCoordinate: currentCoordinate) else {
                return
            }

            let allowedRadius = max(25, Double(venue.checkinRadiusMeters))
            if distanceMeters > allowedRadius + autoCheckoutBufferMeters {
                performCheckOut(event: "Auto checked out - you moved away from \(venue.name)")
            }
        } catch {
            // Ignore transient location failures. We'll retry on next interval.
        }
    }

    private func distanceFromVenue(_ venue: Venue, userCoordinate: CLLocationCoordinate2D) -> CLLocationDistance? {
        guard let venueLatitude = venue.latitude, let venueLongitude = venue.longitude else {
            return nil
        }

        let venueLocation = CLLocation(latitude: venueLatitude, longitude: venueLongitude)
        let userLocation = CLLocation(latitude: userCoordinate.latitude, longitude: userCoordinate.longitude)
        return userLocation.distance(from: venueLocation)
    }

    enum SwipeDirection { case like, nope, superLike }
}

#if DEBUG
extension DiscoverViewModel {
    func testSeedVenueState(
        activeVenue venue: Venue,
        roster: [UserProfile],
        profiles seededProfiles: [UserProfile],
        swipedProfileIDs: Set<UUID> = []
    ) {
        activeVenue = venue
        venueRosters[venue.id] = roster
        venueOccupancy[venue.id] = roster.count + 1
        profiles = seededProfiles
        swipedProfileIDsByVenue[venue.id] = swipedProfileIDs
        dragOffset = .zero
        updateUndoAvailability()
    }

    func testApplyHiddenUsers(rebuildActiveQueue: Bool) async {
        await syncHiddenUsers(rebuildActiveQueue: rebuildActiveQueue)
    }

    func testRefreshRoster(for venue: Venue) async {
        await loadRoster(for: venue)
    }

    func testRefreshDiscoverQueue(for venue: Venue) async {
        await loadDiscoverQueue(for: venue)
    }
}
#endif

private final class VenueLocationProvider: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    enum LocationError: LocalizedError {
        case permissionDenied
        case requestInProgress
        case unavailable

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Location permission is needed to verify venue check-in."
            case .requestInProgress:
                return "Already checking your location."
            case .unavailable:
                return "Could not read your current location."
            }
        }
    }

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocationCoordinate2D, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    func currentCoordinate() async throws -> CLLocationCoordinate2D {
        if continuation != nil {
            throw LocationError.requestInProgress
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            DispatchQueue.main.async {
                self.startLocationRequest()
            }
        }
    }

    private func startLocationRequest() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            finish(.failure(LocationError.permissionDenied))
        @unknown default:
            finish(.failure(LocationError.unavailable))
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            finish(.failure(LocationError.permissionDenied))
        case .notDetermined:
            break
        @unknown default:
            finish(.failure(LocationError.unavailable))
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, location.horizontalAccuracy >= 0 else {
            finish(.failure(LocationError.unavailable))
            return
        }

        finish(.success(location.coordinate))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(.failure(error))
    }

    private func finish(_ result: Result<CLLocationCoordinate2D, Error>) {
        guard let continuation else { return }
        self.continuation = nil

        switch result {
        case let .success(coordinate):
            continuation.resume(returning: coordinate)
        case let .failure(error):
            continuation.resume(throwing: error)
        }
    }
}
