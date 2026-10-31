import Foundation

enum APIDateDecoding {
    private static let iso8601WithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static let strategy: JSONDecoder.DateDecodingStrategy = .custom { decoder in
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        if
            let date = iso8601WithFractionalSeconds.date(from: rawValue)
                ?? iso8601.date(from: rawValue)
        {
            return date
        }

        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Invalid ISO8601 date: \(rawValue)"
        )
    }
}

enum APIError: LocalizedError {
    case badURL
    case unauthorized
    case serverError(Int, String)
    case decodingFailed
    case networkOffline

    var errorDescription: String? {
        switch self {
        case .badURL:
            return "The API URL is invalid."
        case .unauthorized:
            return "Your session expired. Please sign in again."
        case let .serverError(_, message):
            return message
        case .decodingFailed:
            return "The server response could not be read."
        case .networkOffline:
            return "Could not reach the ClubMates API."
        }
    }
}

actor NetworkClient {
    static let shared = NetworkClient()
    private static let tokenStorageKey = "clubmates.api_tokens"

    private struct TokenSnapshot: Codable {
        var accessToken: String
        var refreshToken: String
    }

    private struct CheckInRequest: Encodable {
        let latitude: Double
        let longitude: Double
    }

    private struct GhostModeRequest: Encodable {
        let isGhostMode: Bool
    }

    private struct PhoneRequest: Encodable {
        let phone: String
    }

    private struct OTPRequest: Encodable {
        let phone: String
        let restore: Bool
    }

    private struct OTPVerifyRequest: Encodable {
        let phone: String
        let code: String
        let restore: Bool
    }

    private let baseURL: URL
    private let session: URLSession
    private var accessToken: String?
    private var refreshToken: String?

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = APIDateDecoding.strategy
        return decoder
    }()

    init(
        baseURL: URL = APIConfiguration.baseURL,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
        if let snapshot = Self.loadTokenSnapshot(storageKey: Self.tokenStorageKey) {
            accessToken = snapshot.accessToken
            refreshToken = snapshot.refreshToken
        }
    }

    static func hasStoredTokens(defaults: UserDefaults = .standard) -> Bool {
        defaults.data(forKey: tokenStorageKey) != nil
    }

    func setTokens(accessToken: String, refreshToken: String) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        persistTokens()
    }

    func clearTokens() {
        accessToken = nil
        refreshToken = nil
        UserDefaults.standard.removeObject(forKey: Self.tokenStorageKey)
    }

    func accountStatus(phone: String) async throws -> AccountStatusResponse {
        try await request(
            path: "/auth/account-status",
            method: "POST",
            body: PhoneRequest(phone: phone),
            requiresAuth: false
        )
    }

    func sendOTP(phone: String, restore: Bool = false) async throws -> OTPResponse {
        try await request(
            path: "/auth/otp/send",
            method: "POST",
            body: OTPRequest(phone: phone, restore: restore),
            requiresAuth: false
        )
    }

    func verifyOTP(phone: String, code: String, restore: Bool = false) async throws -> APIAuthResponse {
        let response: APIAuthResponse = try await request(
            path: "/auth/otp/verify",
            method: "POST",
            body: OTPVerifyRequest(phone: phone, code: code, restore: restore),
            requiresAuth: false
        )
        setTokens(accessToken: response.accessToken, refreshToken: response.refreshToken)
        return response
    }

    func currentUser() async throws -> UserResponse {
        try await request(path: "/users/me")
    }

    func userProfile(userId: UUID) async throws -> UserResponse {
        try await request(path: "/users/\(userId.uuidString)/profile")
    }

    func updateProfile(_ profile: UserProfile) async throws -> UserResponse {
        try await request(
            path: "/users/me",
            method: "PUT",
            body: APIProfileUpdateRequest(profile: profile)
        )
    }

    func patchProfile(_ profile: UserProfile, previous: UserProfile) async throws -> UserResponse {
        try await request(
            path: "/users/me",
            method: "PATCH",
            body: APIProfilePatchRequest(profile: profile, previous: previous)
        )
    }

    func updateGhostMode(_ isGhostMode: Bool) async throws -> UserResponse {
        let response: UserResponse = try await request(
            path: "/users/me",
            method: "PATCH",
            body: GhostModeRequest(isGhostMode: isGhostMode)
        )
        return response
    }

    func uploadVerificationSelfie(_ imageData: Data) async throws -> VerificationSelfieResponse {
        try await multipartUpload(
            path: "/users/me/verification-selfie",
            imageData: imageData,
            fieldName: "selfie",
            filename: "selfie.jpg"
        )
    }

    func downloadData(from url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.networkOffline
        }
        return data
    }

    func uploadProfilePhoto(
        _ imageData: Data,
        position: Int,
        clientPhotoId: UUID
    ) async throws -> ProfilePhotoResponse {
        try await uploadProfilePhoto(
            imageData,
            position: position,
            clientPhotoId: clientPhotoId,
            hasRetried: false
        )
    }

    func extractEmbedding(_ imageData: Data) async throws -> EmbeddingResponse {
        try await multipartUpload(
            path: "/photos/extract-embedding",
            imageData: imageData,
            fieldName: "photo",
            filename: "photo.jpg"
        )
    }

    func deleteProfilePhoto(photoId: UUID) async throws {
        let _: EmptyResponse = try await request(path: "/users/me/photos/\(photoId.uuidString)", method: "DELETE")
    }

    func reorderProfilePhotos(photoIds: [UUID]) async throws {
        let body = ["order": photoIds.map(\.uuidString)]
        let _: EmptyResponse = try await request(path: "/users/me/photos/order", method: "PUT", body: body)
    }

    func logout() async {
        guard let refreshToken else {
            clearTokens()
            return
        }

        do {
            let _: EmptyResponse = try await request(
                path: "/auth/session",
                method: "DELETE",
                body: ["refreshToken": refreshToken],
                requiresAuth: false
            )
        } catch {
            // Local sign-out should still complete even if the server is unreachable.
        }
        clearTokens()
    }

    func deleteAccount() async throws -> AccountDeletionResponse {
        let response: AccountDeletionResponse = try await request(path: "/users/me", method: "DELETE")
        clearTokens()
        return response
    }

    func venues() async throws -> VenuesResponse {
        try await request(path: "/venues")
    }

    func roster(venueId: UUID) async throws -> RosterResponse {
        try await request(path: "/venues/\(venueId.uuidString)/roster")
    }

    func checkIn(venueId: UUID, latitude: Double, longitude: Double) async throws {
        let _: EmptyResponse = try await request(
            path: "/venues/\(venueId.uuidString)/checkin",
            method: "POST",
            body: CheckInRequest(latitude: latitude, longitude: longitude)
        )
    }

    func checkOut(venueId: UUID) async throws {
        let _: EmptyResponse = try await request(path: "/venues/\(venueId.uuidString)/checkin", method: "DELETE")
    }

    func discover(venueId: UUID) async throws -> DiscoverResponse {
        try await request(path: "/venues/\(venueId.uuidString)/discover")
    }

    func venueVoting(venueId: UUID) async throws -> VenueVotingResponse {
        try await request(path: "/venues/\(venueId.uuidString)/voting")
    }

    func joinVenueVoting(venueId: UUID, category: VenueVotingCategory) async throws -> VenueVotingCompetitionResponse {
        try await request(
            path: "/venues/\(venueId.uuidString)/voting/\(category.rawValue)/join",
            method: "POST"
        )
    }

    func restartVenueVotingDemo(venueId: UUID) async throws -> VenueVotingRestartResponse {
        try await request(
            path: "/venues/\(venueId.uuidString)/voting/demo/restart",
            method: "POST"
        )
    }

    func voteInVenueCompetition(competitionId: UUID, entryId: UUID) async throws -> VenueVotingCompetitionResponse {
        try await request(
            path: "/venue-voting/\(competitionId.uuidString)/entries/\(entryId.uuidString)/vote",
            method: "POST"
        )
    }

    func venueVotingHistory() async throws -> VenueVotingHistoryResponse {
        try await request(path: "/venue-voting/history")
    }

    func swipe(targetUserId: UUID, venueId: UUID, direction: String) async throws -> SwipeResponse {
        try await request(
            path: "/swipes",
            method: "POST",
            body: [
                "targetUserId": targetUserId.uuidString,
                "venueId": venueId.uuidString,
                "direction": direction
            ]
        )
    }

    func incomingSwipes() async throws -> IncomingSwipesResponse {
        try await request(path: "/swipes/incoming")
    }

    func sendTreatInvite(targetUserId: UUID, venueId: UUID, treat: TreatInvite) async throws -> TreatInviteResponse {
        try await request(
            path: "/invites",
            method: "POST",
            body: [
                "targetUserId": targetUserId.uuidString,
                "venueId": venueId.uuidString,
                "treatType": treat.rawValue
            ]
        )
    }

    func incomingTreatInvites() async throws -> IncomingTreatInvitesResponse {
        try await request(path: "/invites/incoming")
    }

    func acceptTreatInvite(inviteId: UUID) async throws -> AcceptTreatInviteResponse {
        try await request(path: "/invites/\(inviteId.uuidString)/accept", method: "POST")
    }

    func declineTreatInvite(inviteId: UUID) async throws {
        let _: EmptyResponse = try await request(path: "/invites/\(inviteId.uuidString)/decline", method: "POST")
    }

    func undoSwipe(targetUserId: UUID, venueId: UUID) async throws {
        let _: EmptyResponse = try await request(path: "/swipes/\(targetUserId.uuidString)/\(venueId.uuidString)", method: "DELETE")
    }

    func matches(updatedSince: Int64? = nil, limit: Int? = nil, page: Int? = nil) async throws -> MatchesResponse {
        try await request(path: pathWithQuery(
            "/matches",
            queryItems: [
                updatedSince.map { URLQueryItem(name: "updatedSince", value: String($0)) },
                limit.map { URLQueryItem(name: "limit", value: String($0)) },
                page.map { URLQueryItem(name: "page", value: String($0)) }
            ].compactMap { $0 }
        ))
    }

    func messages(matchId: UUID, since: Int64? = nil, before: Int64? = nil, limit: Int? = nil, page: Int? = nil) async throws -> MessagesResponse {
        try await request(path: pathWithQuery(
            "/matches/\(matchId.uuidString)/messages",
            queryItems: [
                since.map { URLQueryItem(name: "since", value: String($0)) },
                before.map { URLQueryItem(name: "before", value: String($0)) },
                limit.map { URLQueryItem(name: "limit", value: String($0)) },
                page.map { URLQueryItem(name: "page", value: String($0)) }
            ].compactMap { $0 }
        ))
    }

    func sendMessage(matchId: UUID, body: String) async throws -> MessageResponse {
        try await request(
            path: "/matches/\(matchId.uuidString)/messages",
            method: "POST",
            body: ["body": body]
        )
    }

    func markRead(matchId: UUID, upToMessageId: UUID? = nil) async throws {
        let body = upToMessageId.map { ["upToMessageId": $0.uuidString] } ?? [:]
        let _: EmptyResponse = try await request(path: "/matches/\(matchId.uuidString)/messages/read", method: "PUT", body: body)
    }

    func unmatch(matchId: UUID) async throws {
        let _: EmptyResponse = try await request(path: "/matches/\(matchId.uuidString)", method: "DELETE")
    }

    func triggerSOS(
        source: String,
        venueId: UUID? = nil,
        matchId: UUID? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        accuracyMeters: Double? = nil,
        message: String? = nil
    ) async throws -> SOSResponse {
        try await request(
            path: "/safety/sos",
            method: "POST",
            body: APISOSRequest(
                venueId: venueId,
                matchId: matchId,
                latitude: latitude,
                longitude: longitude,
                accuracyMeters: accuracyMeters,
                source: source,
                message: message
            )
        )
    }

    func hiddenUserIds() async throws -> HiddenUsersResponse {
        try await request(path: "/safety/hidden-users")
    }

    func blockUser(userId: UUID) async throws {
        let _: EmptyResponse = try await request(
            path: "/blocks",
            method: "POST",
            body: APIBlockRequest(blockedUserId: userId)
        )
    }

    func reportUser(
        userId: UUID,
        matchId: UUID?,
        category: String,
        reason: String,
        details: String? = nil
    ) async throws {
        let _: EmptyResponse = try await request(
            path: "/reports",
            method: "POST",
            body: APIReportRequest(
                reportedUserId: userId,
                matchId: matchId,
                category: category,
                reason: reason,
                details: details
            )
        )
    }

    func wallet() async throws -> WalletResponse {
        try await request(path: "/v1/wallet")
    }

    func coinPackages() async throws -> CoinPackagesResponse {
        try await request(path: "/v1/wallet/packages")
    }

    func purchaseCoins(packageSlug: String) async throws -> PurchaseResponse {
        try await request(path: "/v1/wallet/purchase", method: "POST", body: ["slug": packageSlug])
    }

    func coinTransactions(limit: Int = 20, before: String? = nil) async throws -> TransactionsResponse {
        try await request(path: pathWithQuery(
            "/v1/wallet/transactions",
            queryItems: [
                URLQueryItem(name: "limit", value: String(limit)),
                before.map { URLQueryItem(name: "before", value: $0) }
            ].compactMap { $0 }
        ))
    }

    func treatPricing() async throws -> TreatPricingResponse {
        try await request(path: "/v1/wallet/treat-pricing")
    }

    func webSocketURL() async throws -> URL {
        if accessToken == nil {
            try await refreshSession()
        }

        guard let accessToken else { throw APIError.unauthorized }
        guard
            let url = URL(string: "/v1/ws", relativeTo: baseURL)?.absoluteURL,
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            throw APIError.badURL
        }

        components.scheme = components.scheme == "https" ? "wss" : "ws"
        components.queryItems = [URLQueryItem(name: "token", value: accessToken)]

        guard let webSocketURL = components.url else { throw APIError.badURL }
        return webSocketURL
    }

    private func request<Response: Decodable, Body: Encodable>(
        path: String,
        method: String = "GET",
        body: Body? = Optional<Data>.none,
        requiresAuth: Bool = true,
        hasRetried: Bool = false
    ) async throws -> Response {
        guard let url = URL(string: path, relativeTo: baseURL) else { throw APIError.badURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body {
            let encodedBody = try encoder.encode(body)
            request.httpBody = encodedBody
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        if requiresAuth, let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { throw APIError.networkOffline }

            if httpResponse.statusCode == 401, requiresAuth, !hasRetried {
                try await refreshSession()
                return try await self.request(
                    path: path,
                    method: method,
                    body: body,
                    requiresAuth: requiresAuth,
                    hasRetried: true
                )
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                let message = (try? decoder.decode(APIErrorResponse.self, from: data).error) ?? "Server error"
                throw httpResponse.statusCode == 401
                    ? APIError.unauthorized
                    : APIError.serverError(httpResponse.statusCode, message)
            }

            if Response.self == EmptyResponse.self {
                return EmptyResponse() as! Response
            }

            do {
                return try decoder.decode(Response.self, from: data)
            } catch {
                throw APIError.decodingFailed
            }
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.networkOffline
        }
    }

    private func multipartUpload<Response: Decodable>(
        path: String,
        imageData: Data,
        fieldName: String,
        filename: String,
        hasRetried: Bool = false
    ) async throws -> Response {
        guard let url = URL(string: path, relativeTo: baseURL) else { throw APIError.badURL }

        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(filename)\"\r\n")
        body.append("Content-Type: image/jpeg\r\n\r\n")
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accessToken { request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        request.httpBody = body

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { throw APIError.networkOffline }

            if httpResponse.statusCode == 401, !hasRetried {
                try await refreshSession()
                return try await multipartUpload(path: path, imageData: imageData, fieldName: fieldName, filename: filename, hasRetried: true)
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                let message = (try? decoder.decode(APIErrorResponse.self, from: data).error) ?? "Server error"
                throw httpResponse.statusCode == 401 ? APIError.unauthorized : APIError.serverError(httpResponse.statusCode, message)
            }

            do { return try decoder.decode(Response.self, from: data) } catch { throw APIError.decodingFailed }
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.networkOffline
        }
    }

    private func uploadProfilePhoto(
        _ imageData: Data,
        position: Int,
        clientPhotoId: UUID,
        hasRetried: Bool
    ) async throws -> ProfilePhotoResponse {
        guard
            let base = URL(string: "/users/me/photos", relativeTo: baseURL),
            var components = URLComponents(url: base, resolvingAgainstBaseURL: true)
        else {
            throw APIError.badURL
        }

        components.queryItems = [
            URLQueryItem(name: "position", value: String(position)),
            URLQueryItem(name: "clientPhotoId", value: clientPhotoId.uuidString.lowercased())
        ]
        guard let url = components.url else { throw APIError.badURL }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        let body = multipartPhotoBody(
            imageData: imageData,
            boundary: boundary,
            filename: "profile-photo-\(position).jpg"
        )

        do {
            let (data, response) = try await session.upload(for: request, from: body)
            guard let httpResponse = response as? HTTPURLResponse else { throw APIError.networkOffline }

            if httpResponse.statusCode == 401, !hasRetried {
                try await refreshSession()
                return try await uploadProfilePhoto(
                    imageData,
                    position: position,
                    clientPhotoId: clientPhotoId,
                    hasRetried: true
                )
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                let message = (try? decoder.decode(APIErrorResponse.self, from: data).error) ?? "Server error"
                throw httpResponse.statusCode == 401
                    ? APIError.unauthorized
                    : APIError.serverError(httpResponse.statusCode, message)
            }

            return try decoder.decode(ProfilePhotoResponse.self, from: data)
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.networkOffline
        }
    }

    private func multipartPhotoBody(imageData: Data, boundary: String, filename: String) -> Data {
        var data = Data()
        data.append("--\(boundary)\r\n")
        data.append("Content-Disposition: form-data; name=\"photo\"; filename=\"\(filename)\"\r\n")
        data.append("Content-Type: image/jpeg\r\n\r\n")
        data.append(imageData)
        data.append("\r\n--\(boundary)--\r\n")
        return data
    }




    private func refreshSession() async throws {
        guard let refreshToken else { throw APIError.unauthorized }

        let response: APIAuthResponse = try await request(
            path: "/auth/refresh",
            method: "POST",
            body: ["refreshToken": refreshToken],
            requiresAuth: false
        )
        setTokens(accessToken: response.accessToken, refreshToken: response.refreshToken)
    }

    private static func loadTokenSnapshot(storageKey: String) -> TokenSnapshot? {
        guard
            let data = UserDefaults.standard.data(forKey: storageKey),
            let snapshot = try? JSONDecoder().decode(TokenSnapshot.self, from: data)
        else {
            return nil
        }

        return snapshot
    }

    private func persistTokens() {
        guard let accessToken, let refreshToken else { return }
        let snapshot = TokenSnapshot(accessToken: accessToken, refreshToken: refreshToken)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: Self.tokenStorageKey)
    }

    private func pathWithQuery(_ path: String, queryItems: [URLQueryItem]) -> String {
        guard !queryItems.isEmpty else { return path }
        var components = URLComponents()
        components.path = path
        components.queryItems = queryItems
        return components.string ?? path
    }
}

enum APIConfiguration {
    static var baseURL: URL {
        if
            let rawValue = ProcessInfo.processInfo.environment["CLUBMATES_API_BASE_URL"],
            let url = URL(string: rawValue)
        {
            return url
        }

        if
            let rawValue = Bundle.main.object(forInfoDictionaryKey: "CLUBMATES_API_BASE_URL") as? String,
            let url = URL(string: rawValue)
        {
            return url
        }

        #if DEBUG
        return URL(string: "https://139.59.25.255")!
        #else
        return URL(string: "https://139.59.25.255")!
        #endif
    }
}

struct EmptyResponse: Decodable {}

private struct APIErrorResponse: Decodable {
    let error: String
}

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
