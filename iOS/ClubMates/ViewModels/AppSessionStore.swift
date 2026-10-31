import Foundation
import UIKit

enum OnboardingStep: Int, Codable {
    case basics = 1
    case vibe = 2
    case preferences = 3
}

extension Notification.Name {
    static let appSessionDidSignOut = Notification.Name("AppSessionDidSignOut")
    static let venuePresenceDidChange = Notification.Name("VenuePresenceDidChange")
    static let profileVerificationDidUpdate = Notification.Name("ProfileVerificationDidUpdate")
}

enum ProfileSyncStatus: Equatable {
    case synced(Date?)    // last successful sync time (nil = never synced this session)
    case syncing          // network call in progress
    case failed(String)   // error message, retry available
}

struct ProfileSaveIssue: Identifiable, Equatable {
    let id = UUID()
    let message: String
}

private struct PendingProfileSave {
    let profile: UserProfile
    let previousProfile: UserProfile?
}

@MainActor
final class AppSessionStore: ObservableObject {
    @Published private(set) var phoneNumber: String?
    @Published private(set) var currentProfile: UserProfile?
    @Published private(set) var hasCompletedProfile = false
    @Published private(set) var authErrorMessage: String?
    @Published private(set) var isNetworkBusy = false
    @Published private(set) var lastAuthWasNewUser = false
    @Published private(set) var needsVideoVerification = false
    @Published private(set) var onboardingStep: OnboardingStep = .basics
    @Published private(set) var isProfileLoading = false
    @Published private(set) var syncStatus: ProfileSyncStatus = .synced(nil)
    @Published private(set) var profileSaveIssue: ProfileSaveIssue?
    @Published private(set) var uploadingProfilePhotoIDs: Set<UUID> = []
    @Published private(set) var failedProfilePhotoIDs: Set<UUID> = []
    @Published private(set) var isProfileVerificationPending = false

    // Phone number stored during OTP verification for new users who haven't
    // finished onboarding yet. Kept separate so isAuthenticated stays false
    // until the full profile is saved.
    private var pendingPhone: String?

    private let storageKey = "clubmates.app_session"
    private let selfieStorageKey = "clubmates.verification_selfie"
    private let profileRefreshInterval: TimeInterval = 120
    private let defaults: UserDefaults
    private let api: NetworkClient
    private let profileStore: ProfileLocalStore
    private let chatStore: ChatLocalStore
    private var profileSyncTask: Task<Void, Never>?
    private var pendingProfileSave: PendingProfileSave?
    private var profileSyncGeneration = 0
    private var lastProfileRefreshAt: Date?
    private var isProfileRefreshInFlight = false
    private var currentPhotoUploadFailureID: UUID?
    private var profileVerificationObserver: NSObjectProtocol?

    /// JPEG data of the verification selfie, stored locally for face comparison.
    private(set) var verificationSelfieData: Data? {
        get { defaults.data(forKey: selfieStorageKey) }
        set {
            if let data = newValue {
                defaults.set(data, forKey: selfieStorageKey)
            } else {
                defaults.removeObject(forKey: selfieStorageKey)
            }
        }
    }

    init(
        defaults: UserDefaults = .standard,
        api: NetworkClient = .shared,
        profileStore: ProfileLocalStore = .shared,
        chatStore: ChatLocalStore = .shared
    ) {
        self.defaults = defaults
        self.api = api
        self.profileStore = profileStore
        self.chatStore = chatStore
        profileVerificationObserver = NotificationCenter.default.addObserver(
            forName: .profileVerificationDidUpdate,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshProfile(force: true)
                self?.isProfileVerificationPending = false
            }
        }
        Task { await loadSession() }
    }

    deinit {
        if let profileVerificationObserver {
            NotificationCenter.default.removeObserver(profileVerificationObserver)
        }
    }

    var isAuthenticated: Bool {
        phoneNumber != nil
    }

    // True while the user has verified OTP but hasn't finished onboarding yet.
    var isOnboarding: Bool {
        pendingPhone != nil
    }

    var needsProfileCreation: Bool {
        (isAuthenticated || isOnboarding) && !hasCompletedProfile
    }

    /// Returns `(success, userExists)`. `userExists` is `nil` when the call failed.
    func accountStatus(phoneNumber: String) async -> AccountStatusResponse? {
        let phone = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        isNetworkBusy = true
        authErrorMessage = nil
        defer { isNetworkBusy = false }

        do {
            return try await api.accountStatus(phone: phone)
        } catch {
            authErrorMessage = error.localizedDescription
            return nil
        }
    }

    /// Returns `(success, userExists)`. `userExists` is `nil` when the call failed.
    func sendOTP(phoneNumber: String, restore: Bool = false) async -> (success: Bool, userExists: Bool?) {
        let phone = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        isNetworkBusy = true
        authErrorMessage = nil
        defer { isNetworkBusy = false }

        do {
            let response = try await api.sendOTP(phone: phone, restore: restore)
            return (true, response.userExists)
        } catch {
            authErrorMessage = error.localizedDescription
            return (false, nil)
        }
    }

    func uploadVerificationSelfie(_ selfieData: Data) async throws {
        verificationSelfieData = selfieData
        needsVideoVerification = false
        persistSession()

        print("[Verification] POST /users/me/verification-selfie — sending \(selfieData.count) bytes")
        do {
            let response = try await api.uploadVerificationSelfie(selfieData)
            print("[Verification] POST /users/me/verification-selfie — success ok=\(response.ok) selfieUrl=\(response.selfieUrl ?? "nil")")
            isProfileVerificationPending = true
        } catch {
            print("[Verification] POST /users/me/verification-selfie — failed: \(error.localizedDescription)")
            throw error
        }
    }

    func uploadAndVerification(selfieData: Data) async {
        do {
            try await uploadVerificationSelfie(selfieData)
        } catch {
            return
        }
        // Eager refresh so the profile badge updates even if the WebSocket
        // was disconnected when the background worker finished.
        await refreshProfile(force: true)
    }

    func advanceOnboardingStep() {
        switch onboardingStep {
        case .basics: onboardingStep = .vibe
        case .vibe:   onboardingStep = .preferences
        case .preferences: break
        }
    }

    func rewindOnboardingStep() {
        switch onboardingStep {
        case .basics: break
        case .vibe:        onboardingStep = .basics
        case .preferences: onboardingStep = .vibe
        }
    }

    /// Downloads and caches the verification selfie from the server URL.
    func fetchAndCacheVerificationSelfie(from urlString: String) async {
        guard verificationSelfieData == nil,
              let url = URL(string: urlString)
        else { return }
        if let data = try? await api.downloadData(from: url), !data.isEmpty {
            verificationSelfieData = data
        }
    }

    func verifyOTP(phoneNumber: String, code: String, restore: Bool = false) async -> Bool {
        let phone = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        isNetworkBusy = true
        authErrorMessage = nil
        defer { isNetworkBusy = false }

        do {
            let response = try await api.verifyOTP(phone: phone, code: code, restore: restore)
            lastAuthWasNewUser = response.isNewUser == true

            if response.user.profileCompleted {
                // Returning user with a complete profile — fetch, save to SQLite, then authenticate
                self.phoneNumber = phone
                needsVideoVerification = false
                isProfileLoading = true
                if let user = try? await api.currentUser().user {
                    let now = Date()
                    setProfile(user, syncedAt: now)
                    lastProfileRefreshAt = now
                    syncStatus = .synced(now)
                    if let selfieUrl = user.verificationSelfieUrl {
                        await fetchAndCacheVerificationSelfie(from: selfieUrl)
                    }
                }
                isProfileLoading = false
                persistSession(clean: true)
            } else if response.isNewUser == true {
                // Brand new user — tokens are stored but we don't authenticate yet.
                // They must complete selfie + profile first.
                pendingPhone = phone
                needsVideoVerification = true
                currentProfile = nil
                hasCompletedProfile = false
                onboardingStep = .basics
            } else {
                // Existing user with incomplete profile — same holding pattern.
                pendingPhone = phone
                needsVideoVerification = false
                currentProfile = nil
                hasCompletedProfile = false
                onboardingStep = .basics
            }
            return true
        } catch {
            authErrorMessage = error.localizedDescription
            return false
        }
    }

    func completeProfile(_ profile: UserProfile) {
        // Promote pending phone to authenticated phone — this is the moment the
        // user is considered fully created from the app's perspective.
        if let pending = pendingPhone {
            phoneNumber = pending
            pendingPhone = nil
        }
        currentProfile = normalized(profile)
        hasCompletedProfile = true
        persistSession()

        enqueueProfileSave(profile, replacing: nil)
    }

    func updateProfile(_ profile: UserProfile) {
        let updatedProfile = normalized(profile)
        guard currentProfile != updatedProfile else {
            print("[Profile] updateProfile: no changes detected, skipping")
            return
        }

        print("[Profile] updateProfile: changes detected, saving locally and syncing to backend")
        let previousProfile = currentProfile
        currentProfile = updatedProfile
        persistSession()

        enqueueProfileSave(updatedProfile, replacing: previousProfile)
    }

    func updateGhostMode(_ isEnabled: Bool) {
        guard var profile = currentProfile else { return }
        guard profile.isGhostMode != isEnabled else { return }

        let previousProfile = profile
        profile.isGhostMode = isEnabled
        currentProfile = normalized(profile)
        persistSession()

        enqueueProfileSave(profile, replacing: previousProfile)
    }

    func signOut() {
        Task {
            await api.logout()
        }
        clearLocalSession()
    }

    func deleteAccount() async -> Bool {
        isNetworkBusy = true
        authErrorMessage = nil
        defer { isNetworkBusy = false }

        do {
            _ = try await api.deleteAccount()
            clearLocalSession()
            return true
        } catch {
            authErrorMessage = error.localizedDescription
            return false
        }
    }

    private func clearLocalSession() {
        profileSyncGeneration += 1
        profileSyncTask?.cancel()
        profileSyncTask = nil
        pendingProfileSave = nil
        phoneNumber = nil
        pendingPhone = nil
        currentProfile = nil
        hasCompletedProfile = false
        lastAuthWasNewUser = false
        needsVideoVerification = false
        onboardingStep = .basics
        uploadingProfilePhotoIDs.removeAll()
        failedProfilePhotoIDs.removeAll()
        isProfileVerificationPending = false
        defaults.removeObject(forKey: storageKey)
        defaults.removeObject(forKey: selfieStorageKey)
        SafetyVisibilityStore.clear()
        Task {
            await profileStore.clear()
            await chatStore.clearAll()
        }
        ProfileImageCache.shared.clearDisk()
        NotificationCenter.default.post(name: .appSessionDidSignOut, object: nil)
    }

    func refreshProfile(force: Bool = false) async {
        guard let sessionPhone = phoneNumber else { return }
        guard shouldRefreshProfile(force: force) else { return }

        isProfileRefreshInFlight = true
        // Only show loading shimmer when there is no cached profile yet
        let showLoading = currentProfile == nil
        if showLoading { isProfileLoading = true }
        defer {
            isProfileRefreshInFlight = false
            if showLoading { isProfileLoading = false }
        }

        do {
            let user = try await api.currentUser().user
            guard phoneNumber == sessionPhone else { return }
            let now = Date()
            setProfile(user, syncedAt: now)
            lastProfileRefreshAt = now
            persistSession(clean: true)
            if let selfieUrl = user.verificationSelfieUrl {
                await fetchAndCacheVerificationSelfie(from: selfieUrl)
            }
        } catch {
            guard phoneNumber == sessionPhone else { return }
            authErrorMessage = error.localizedDescription
        }
    }

    func retrySync() {
        guard let profile = currentProfile else { return }
        profileSaveIssue = nil
        failedProfilePhotoIDs.removeAll()
        // Always use PUT on retry to push all fields regardless of diff.
        enqueueProfileSave(profile, replacing: nil)
    }

    func dismissProfileSaveIssue() {
        profileSaveIssue = nil
    }

    private func enqueueProfileSave(_ profile: UserProfile, replacing previousProfile: UserProfile?) {
        let baseline: UserProfile?
        if let pendingProfileSave {
            baseline = pendingProfileSave.previousProfile
        } else {
            baseline = previousProfile
        }
        pendingProfileSave = PendingProfileSave(
            profile: profile,
            previousProfile: baseline
        )

        guard profileSyncTask == nil else { return }
        let generation = profileSyncGeneration
        profileSyncTask = Task {
            await processPendingProfileSaves(generation: generation)
        }
    }

    private func processPendingProfileSaves(generation: Int) async {
        var forceFullSave = false

        while
            !Task.isCancelled,
            generation == profileSyncGeneration,
            let pendingSave = pendingProfileSave
        {
            pendingProfileSave = nil
            let succeeded = await saveProfileToBackend(
                pendingSave.profile,
                replacing: forceFullSave ? nil : pendingSave.previousProfile
            )
            forceFullSave = !succeeded
        }

        guard generation == profileSyncGeneration else { return }
        profileSyncTask = nil
    }

    @discardableResult
    private func saveProfileToBackend(
        _ profile: UserProfile,
        replacing previousProfile: UserProfile?
    ) async -> Bool {
        guard let sessionPhone = phoneNumber else { return false }
        syncStatus = .syncing
        profileSaveIssue = nil
        failedProfilePhotoIDs.removeAll()

        let normalizedProfile = normalized(profile)
        var retryAttempt = 0

        while true {
            currentPhotoUploadFailureID = nil

            do {
                var wroteToBackend = false
                if let previous = previousProfile {
                    let patch = APIProfilePatchRequest(profile: normalizedProfile, previous: previous)
                    if patch.hasChanges {
                        print("[Profile] PATCH /users/me — notifPrefs: \(normalizedProfile.notificationPreferences), prefs: \(normalizedProfile.preferences)")
                        _ = try await api.patchProfile(normalizedProfile, previous: previous)
                        print("[Profile] PATCH succeeded")
                        wroteToBackend = true
                    } else {
                        print("[Profile] No profile field changes; continuing with photo sync")
                    }
                } else {
                    print("[Profile] PUT /users/me (full save)")
                    _ = try await api.updateProfile(normalizedProfile)
                    print("[Profile] PUT succeeded")
                    wroteToBackend = true
                }

                if shouldSyncProfilePhotos(normalizedProfile.photos, replacing: previousProfile) {
                    let shouldShowVerificationPending = shouldMarkVerificationPending(
                        for: normalizedProfile.photos,
                        replacing: previousProfile
                    )
                    if shouldShowVerificationPending {
                        isProfileVerificationPending = true
                    }
                    let uploadedPhotos = try await syncProfilePhotos(normalizedProfile.photos, replacing: previousProfile)

                    // Optimistically patch currentProfile with the server-confirmed photos so the
                    // subsequent GET /users/me can't overwrite them with a stale photoUrl fallback
                    // (which happens when the server returns photos:[] right after an upload).
                    if !uploadedPhotos.isEmpty, var patched = currentProfile {
                        patched.photos = normalizedProfile.photos.map { photo in
                            uploadedPhotos[photo.id] ?? photo
                        }
                        currentProfile = patched
                    }

                    wroteToBackend = true
                } else {
                    print("[Profile] No photo changes; skipping photo sync")
                }

                if !wroteToBackend {
                    let now = Date()
                    syncStatus = .synced(now)
                    return true
                }

                // Guard before writing results back — prevents a cancelled task (e.g. after
                // sign-out) from overwriting the newly signed-in user's profile data.
                guard !Task.isCancelled else { return false }
                let response = try await api.currentUser()
                guard !Task.isCancelled, phoneNumber == sessionPhone else { return false }
                print("[Profile] GET /users/me — notifPrefs: \(response.user.notificationPreferences), lookingFor: \(response.user.lookingFor ?? "")")
                let now = Date()
                uploadingProfilePhotoIDs.removeAll()
                failedProfilePhotoIDs.removeAll()
                profileSaveIssue = nil
                syncStatus = .synced(now)
                setProfile(response.user, syncedAt: now)
                lastProfileRefreshAt = now
                persistSession(clean: true)
                return true
            } catch {
                guard !Task.isCancelled, phoneNumber == sessionPhone else {
                    uploadingProfilePhotoIDs.removeAll()
                    return false
                }

                if Self.shouldAutomaticallyRetryProfileSave(error, retryAttempt: retryAttempt) {
                    retryAttempt += 1
                    print("[Profile] save failed; retrying automatically: \(error.localizedDescription)")
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    guard !Task.isCancelled else {
                        uploadingProfilePhotoIDs.removeAll()
                        return false
                    }
                    continue
                }

                uploadingProfilePhotoIDs.removeAll()
                isProfileVerificationPending = false
                if let failedPhotoID = currentPhotoUploadFailureID {
                    failedProfilePhotoIDs.insert(failedPhotoID)
                } else {
                    profileSaveIssue = ProfileSaveIssue(
                        message: Self.userFacingProfileSaveMessage(for: error)
                    )
                }
                print("[Profile] saveProfileToBackend FAILED: \(error.localizedDescription)")
                syncStatus = .failed(error.localizedDescription)
                return false
            }
        }
    }

    private func shouldSyncProfilePhotos(_ desiredPhotos: [ProfilePhoto], replacing previousProfile: UserProfile?) -> Bool {
        guard let previousProfile else { return true }
        if desiredPhotos.contains(where: { $0.imageData != nil }) {
            return true
        }

        let previousRemoteIds = previousProfile.photos.compactMap { photo -> UUID? in
            photo.remoteURL == nil ? nil : photo.id
        }
        let desiredRemoteIds = desiredPhotos.compactMap { photo -> UUID? in
            photo.remoteURL == nil ? nil : photo.id
        }
        return previousRemoteIds != desiredRemoteIds
    }

    private func shouldMarkVerificationPending(
        for desiredPhotos: [ProfilePhoto],
        replacing previousProfile: UserProfile?
    ) -> Bool {
        guard let previousProfile else { return false }
        let hasVerificationState = previousProfile.isVerified || previousProfile.verificationFailureReason != nil
        return hasVerificationState && desiredPhotos.contains(where: { $0.imageData != nil })
    }


    // Returns a mapping from client photo UUID → confirmed server ProfilePhoto (with remoteURL),
    // for every photo that was uploaded this sync. Used to patch currentProfile before GET /users/me
    // so a stale server response can't overwrite the just-uploaded photos.
    @discardableResult
    private func syncProfilePhotos(_ desiredPhotos: [ProfilePhoto], replacing previousProfile: UserProfile?) async throws -> [UUID: ProfilePhoto] {
        let existingRemotePhotoIds = Set(previousProfile?.photos.compactMap { photo -> UUID? in
            photo.remoteURL == nil ? nil : photo.id
        } ?? [])

        var desiredRemotePhotoIds: [UUID] = []
        var uploadedPhotosByClientID: [UUID: ProfilePhoto] = [:]

        for (index, photo) in desiredPhotos.enumerated() {
            if let imageData = photo.imageData {
                uploadingProfilePhotoIDs.insert(photo.id)
                failedProfilePhotoIDs.remove(photo.id)
                do {
                    let response = try await api.uploadProfilePhoto(
                        imageData,
                        position: index,
                        clientPhotoId: photo.id
                    )
                    uploadingProfilePhotoIDs.remove(photo.id)
                    desiredRemotePhotoIds.append(response.photo.id)

                    // Seed the uploaded bytes into the image cache under the server CDN URL so
                    // CachedRemoteImage renders instantly when the profile switches from .imageData
                    // to .remoteURL — prevents the placeholder flash.
                    if let cdnURL = URL(string: response.photo.cdnUrl),
                       let uploadedImage = UIImage(data: imageData) {
                        ProfileImageCache.shared.insertMemory(uploadedImage, for: cdnURL)
                    }

                    if let cdnURL = URL(string: response.photo.cdnUrl) {
                        uploadedPhotosByClientID[photo.id] = ProfilePhoto(id: response.photo.id, remoteURL: cdnURL)
                    }
                } catch {
                    uploadingProfilePhotoIDs.remove(photo.id)
                    currentPhotoUploadFailureID = photo.id
                    throw error
                }
            } else if photo.remoteURL != nil {
                desiredRemotePhotoIds.append(photo.id)
            }
        }

        let desiredRemotePhotoIdSet = Set(desiredRemotePhotoIds)
        for removedPhotoId in existingRemotePhotoIds.subtracting(desiredRemotePhotoIdSet) {
            try await api.deleteProfilePhoto(photoId: removedPhotoId)
        }

        if !desiredRemotePhotoIds.isEmpty {
            try await api.reorderProfilePhotos(photoIds: desiredRemotePhotoIds)
        }

        return uploadedPhotosByClientID
    }

    static func shouldAutomaticallyRetryProfileSave(_ error: Error, retryAttempt: Int) -> Bool {
        guard retryAttempt < 1 else { return false }

        switch error {
        case APIError.networkOffline, APIError.decodingFailed:
            return true
        case let APIError.serverError(statusCode, _):
            return statusCode == 408 || statusCode == 429 || statusCode >= 500
        default:
            return false
        }
    }

    private static func userFacingProfileSaveMessage(for error: Error) -> String {
        if case APIError.networkOffline = error {
            return "Check your internet connection and try again. Your changes are still saved on this device."
        }

        if case APIError.unauthorized = error {
            return "Your session has expired. Sign in again, then retry your changes."
        }

        return "Your changes are still saved on this device. Please try again in a moment."
    }

    private func loadSession() async {
        guard NetworkClient.hasStoredTokens(defaults: defaults) else {
            defaults.removeObject(forKey: storageKey)
            return
        }

        guard
            let data = defaults.data(forKey: storageKey),
            let snapshot = try? JSONDecoder().decode(SessionSnapshot.self, from: data)
        else {
            return
        }

        phoneNumber = snapshot.phoneNumber

        let storedProfile = await profileStore.loadProfile()
        hasCompletedProfile = snapshot.profileCompleted ?? storedProfile.map(isLocallyComplete) ?? false
        currentProfile = hasCompletedProfile ? storedProfile : nil

        // Restore sync status from SQLite
        let isDirty = await profileStore.isDirty()
        let lastSynced = await profileStore.lastSyncedAt()
        if isDirty {
            syncStatus = .failed("Changes not synced yet")
            // Retry automatically on relaunch so local wins before refresh overwrites
            if let profile = currentProfile {
                enqueueProfileSave(profile, replacing: nil)
            }
        } else {
            syncStatus = .synced(lastSynced)
        }
    }

    private func persistSession(clean: Bool = false) {
        guard let phoneNumber else {
            defaults.removeObject(forKey: storageKey)
            Task { await profileStore.clear() }
            return
        }

        // Persist lightweight metadata to UserDefaults (phone + completion flag)
        let snapshot = SessionSnapshot(phoneNumber: phoneNumber, profileCompleted: hasCompletedProfile)
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: storageKey)
        }

        // When data came directly from the server it's already clean — don't mark dirty.
        if !clean, let profile = currentProfile {
            Task { await profileStore.save(profile, dirty: true) }
        }
    }

    private func setProfile(_ user: APIUserProfile, syncedAt: Date? = nil) {
        hasCompletedProfile = user.profileCompleted == true
        let profile = hasCompletedProfile ? normalized(user.userProfile) : nil
        currentProfile = profile
        if let profile {
            let ts = syncedAt ?? Date()
            Task { await profileStore.save(profile, dirty: false, syncedAt: ts) }
            // Pre-warm disk cache for own profile photos
            let remoteURLs = profile.photos.compactMap(\.remoteURL)
            if !remoteURLs.isEmpty {
                ProfileImageCache.shared.prefetch(urls: remoteURLs)
            }
        }
    }

    private func shouldRefreshProfile(force: Bool) -> Bool {
        Self.shouldRefreshProfile(
            force: force,
            isInFlight: isProfileRefreshInFlight,
            lastRefreshAt: lastProfileRefreshAt,
            now: Date(),
            interval: profileRefreshInterval
        )
    }

    static func shouldRefreshProfile(
        force: Bool,
        isInFlight: Bool,
        lastRefreshAt: Date?,
        now: Date,
        interval: TimeInterval
    ) -> Bool {
        if force { return !isInFlight }
        guard !isInFlight else { return false }
        guard let lastRefreshAt else { return true }
        return now.timeIntervalSince(lastRefreshAt) >= interval
    }

    private func normalized(_ profile: UserProfile) -> UserProfile {
        var profile = profile
        var seenInterests = Set<String>()
        profile.name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.bio = String(profile.bio.trimmingCharacters(in: .whitespacesAndNewlines).prefix(150))
        profile.profession = profile.profession.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.interests = profile.interests.filter { seenInterests.insert($0).inserted }
        return profile
    }

    private func isLocallyComplete(_ profile: UserProfile) -> Bool {
        let profile = normalized(profile)
        return !profile.name.isEmpty
            && profile.name != "New ClubMate"
            && !profile.bio.isEmpty
            && (18...99).contains(profile.age)
    }
}

private struct SessionSnapshot: Codable {
    var phoneNumber: String
    var profileCompleted: Bool?
}
