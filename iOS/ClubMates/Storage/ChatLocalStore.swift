import Foundation
import SQLite3

actor ChatLocalStore {
    static let shared = ChatLocalStore()
    static let databaseVersionKey = "clubmates.db.version"
    static let currentDatabaseVersion = 1

    private var db: OpaquePointer?
    private var matchContinuations: [UUID: AsyncStream<[Match]>.Continuation] = [:]
    private var messageContinuations: [UUID: [UUID: AsyncStream<[ChatMessage]>.Continuation]] = [:]

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    init(path: URL? = nil) {
        let databaseURL = path ?? Self.defaultDatabaseURL()
        try? FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if sqlite3_open(databaseURL.path, &db) == SQLITE_OK {
            Self.migrate(db)
            UserDefaults.standard.set(Self.currentDatabaseVersion, forKey: Self.databaseVersionKey)
        }
    }

    deinit {
        sqlite3_close(db)
    }

    func observeMatches() -> AsyncStream<[Match]> {
        AsyncStream { continuation in
            let id = UUID()
            matchContinuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeMatchContinuation(id) }
            }

            Task {
                continuation.yield(await self.matches())
            }
        }
    }

    func observeMessages(matchId: UUID) -> AsyncStream<[ChatMessage]> {
        AsyncStream { continuation in
            let id = UUID()
            var continuations = messageContinuations[matchId, default: [:]]
            continuations[id] = continuation
            messageContinuations[matchId] = continuations
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeMessageContinuation(id, matchId: matchId) }
            }

            Task {
                continuation.yield(await self.messages(matchId: matchId))
            }
        }
    }

    func matches() -> [Match] {
        guard let db else { return [] }

        let sql = """
        SELECT id, venue_id, venue_name, last_message, last_message_at, last_message_at_ms, unread_count, is_new, profile_json
        FROM matches
        ORDER BY last_message_at_ms DESC
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }

        var output: [Match] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard
                let id = uuid(statement, 0),
                let lastMessage = text(statement, 3),
                let lastMessageAt = text(statement, 4),
                let profileJSON = text(statement, 8),
                let profile = decodeProfile(profileJSON)
            else {
                continue
            }

            output.append(
                Match(
                    id: id,
                    venueId: uuid(statement, 1),
                    venueName: text(statement, 2),
                    profile: profile,
                    lastMessage: lastMessage,
                    lastMessageTime: date(from: lastMessageAt, fallbackMs: sqlite3_column_int64(statement, 5)),
                    isNew: sqlite3_column_int(statement, 7) == 1,
                    unreadCount: Int(sqlite3_column_int(statement, 6))
                )
            )
        }

        return output
    }

    func messages(matchId: UUID) -> [ChatMessage] {
        guard let db else { return [] }

        let sql = """
        SELECT id, body, is_from_me, created_at, created_at_ms
        FROM messages
        WHERE match_id = ?
        ORDER BY created_at_ms ASC
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }

        bind(statement, matchId.uuidString.lowercased(), 1)

        var output: [ChatMessage] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard
                let id = uuid(statement, 0),
                let body = text(statement, 1),
                let createdAt = text(statement, 3)
            else {
                continue
            }

            output.append(
                ChatMessage(
                    id: id,
                    text: body,
                    isFromMe: sqlite3_column_int(statement, 2) == 1,
                    timestamp: date(from: createdAt, fallbackMs: sqlite3_column_int64(statement, 4))
                )
            )
        }

        return output
    }

    func hasCachedMatches() -> Bool {
        (scalarInt("SELECT COUNT(*) FROM matches") ?? 0) > 0
    }

    func latestMatchCursor() -> Int64? {
        scalarInt("SELECT MAX(last_message_at_ms) FROM matches")
    }

    func latestMessageCursor(matchId: UUID) -> Int64? {
        scalarInt("SELECT MAX(created_at_ms) FROM messages WHERE match_id = ?", bind: { [self] statement in
            self.bind(statement, matchId.uuidString.lowercased(), 1)
        })
    }

    func replaceMatches(_ matches: [Match]) {
        upsertMatches(matches)
        deleteMatchesNotIn(Set(matches.map(\.id)))
        notifyMatches()
    }

    func upsertMatches(_ matches: [Match]) {
        matches.forEach(upsertMatchWithoutNotify)
        notifyMatches()
    }

    func upsertMatch(_ match: Match) {
        upsertMatchWithoutNotify(match)
        notifyMatches()
    }

    func replaceMessages(_ apiMessages: [APIMessage], matchId: UUID) {
        execute("DELETE FROM messages WHERE match_id = ?", bind: { [self] statement in
            self.bind(statement, matchId.uuidString.lowercased(), 1)
        })
        apiMessages.forEach { upsertMessageWithoutNotify($0) }
        pruneMessagesWithoutNotify(matchId: matchId)
        notifyMessages(matchId: matchId)
    }

    func upsertMessage(_ apiMessage: APIMessage) {
        upsertMessageWithoutNotify(apiMessage)
        pruneMessagesWithoutNotify(matchId: apiMessage.matchId)
        notifyMessages(matchId: apiMessage.matchId)
    }

    func upsertMessages(_ apiMessages: [APIMessage], matchId: UUID) {
        apiMessages.forEach { upsertMessageWithoutNotify($0) }
        pruneMessagesWithoutNotify(matchId: matchId)
        notifyMessages(matchId: matchId)
    }

    func persistConfirmedMessage(_ message: ChatMessage, matchId: UUID, senderId: UUID? = nil, isRead: Bool = false) {
        upsertMessageWithoutNotify(message, matchId: matchId, senderId: senderId, isRead: isRead)
        notifyMessages(matchId: matchId)
    }

    func markRead(matchId: UUID, upToMessageId: UUID? = nil) {
        markMessagesReadWithoutNotify(matchId: matchId, upToMessageId: upToMessageId)

        execute("UPDATE matches SET unread_count = 0, is_new = 0 WHERE id = ?", bind: { [self] statement in
            self.bind(statement, matchId.uuidString.lowercased(), 1)
        })
        notifyMatches()
        notifyMessages(matchId: matchId)
    }

    func markMessagesRead(matchId: UUID, upToMessageId: UUID? = nil) {
        markMessagesReadWithoutNotify(matchId: matchId, upToMessageId: upToMessageId)
        notifyMessages(matchId: matchId)
    }

    func deleteMessage(messageId: UUID, matchId: UUID? = nil) {
        let resolvedMatchId = matchId ?? messageMatchId(messageId: messageId)
        execute("DELETE FROM messages WHERE id = ?", bind: { [self] statement in
            self.bind(statement, messageId.uuidString.lowercased(), 1)
        })
        if let resolvedMatchId {
            notifyMessages(matchId: resolvedMatchId)
        }
    }

    private func markMessagesReadWithoutNotify(matchId: UUID, upToMessageId: UUID? = nil) {
        if let upToMessageId, let cutoff = messageTimestamp(messageId: upToMessageId) {
            execute("UPDATE messages SET is_read = 1 WHERE match_id = ? AND created_at_ms <= ?", bind: { [self] statement in
                self.bind(statement, matchId.uuidString.lowercased(), 1)
                sqlite3_bind_int64(statement, 2, cutoff)
            })
        } else {
            execute("UPDATE messages SET is_read = 1 WHERE match_id = ?", bind: { [self] statement in
                self.bind(statement, matchId.uuidString.lowercased(), 1)
            })
        }
    }

    func updateLastMessage(matchId: UUID, text: String, timestamp: Date = Date()) {
        execute(
            """
            UPDATE matches
            SET last_message = ?, last_message_at = ?, last_message_at_ms = ?
            WHERE id = ?
            """,
            bind: { [self] statement in
                self.bind(statement, text, 1)
                self.bind(statement, self.isoFormatter.string(from: timestamp), 2)
                sqlite3_bind_int64(statement, 3, self.millis(timestamp))
                self.bind(statement, matchId.uuidString.lowercased(), 4)
            }
        )
        notifyMatches()
    }

    func incrementUnread(matchId: UUID) {
        execute("UPDATE matches SET unread_count = unread_count + 1, is_new = 0 WHERE id = ?", bind: { [self] statement in
            self.bind(statement, matchId.uuidString.lowercased(), 1)
        })
        notifyMatches()
    }

    func deleteMatch(matchId: UUID) {
        execute("DELETE FROM messages WHERE match_id = ?", bind: { [self] statement in
            self.bind(statement, matchId.uuidString.lowercased(), 1)
        })
        execute("DELETE FROM matches WHERE id = ?", bind: { [self] statement in
            self.bind(statement, matchId.uuidString.lowercased(), 1)
        })
        notifyMessages(matchId: matchId)
        notifyMatches()
    }

    func clearAll() {
        execute("DELETE FROM messages")
        execute("DELETE FROM matches")
        messageContinuations.keys.forEach(notifyMessages)
        notifyMatches()
    }

    private static func migrate(_ db: OpaquePointer?) {
        execute(db, """
        CREATE TABLE IF NOT EXISTS messages (
            id TEXT PRIMARY KEY,
            match_id TEXT NOT NULL,
            body TEXT NOT NULL,
            is_from_me INTEGER NOT NULL,
            sender_id TEXT NOT NULL,
            is_read INTEGER NOT NULL,
            created_at TEXT NOT NULL,
            created_at_ms INTEGER NOT NULL
        )
        """)
        execute(db, "CREATE INDEX IF NOT EXISTS idx_messages_match_id ON messages(match_id)")
        execute(db, "CREATE INDEX IF NOT EXISTS idx_messages_match_time ON messages(match_id, created_at_ms)")

        execute(db, """
        CREATE TABLE IF NOT EXISTS matches (
            id TEXT PRIMARY KEY,
            venue_id TEXT,
            venue_name TEXT,
            last_message TEXT NOT NULL DEFAULT '',
            last_message_at TEXT NOT NULL DEFAULT '',
            last_message_at_ms INTEGER NOT NULL DEFAULT 0,
            unread_count INTEGER NOT NULL DEFAULT 0,
            is_new INTEGER NOT NULL DEFAULT 0,
            profile_json TEXT NOT NULL
        )
        """)
        addColumnIfMissing(db, table: "matches", column: "venue_name", definition: "venue_name TEXT")
        execute(db, "CREATE INDEX IF NOT EXISTS idx_matches_last_message ON matches(last_message_at_ms DESC)")
    }

    private func upsertMatchWithoutNotify(_ match: Match) {
        guard let profileJSON = encodeProfile(match.profile) else { return }

        execute(
            """
            INSERT OR REPLACE INTO matches (
                id, venue_id, venue_name, last_message, last_message_at, last_message_at_ms,
                unread_count, is_new, profile_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            bind: { [self] statement in
                self.bind(statement, match.id.uuidString.lowercased(), 1)
                self.bind(statement, match.venueId?.uuidString.lowercased(), 2)
                self.bind(statement, match.venueName, 3)
                self.bind(statement, match.lastMessage, 4)
                self.bind(statement, self.isoFormatter.string(from: match.lastMessageTime), 5)
                sqlite3_bind_int64(statement, 6, self.millis(match.lastMessageTime))
                sqlite3_bind_int(statement, 7, Int32(match.unreadCount))
                sqlite3_bind_int(statement, 8, match.isNew ? 1 : 0)
                self.bind(statement, profileJSON, 9)
            }
        )
    }

    private func upsertMessageWithoutNotify(_ apiMessage: APIMessage) {
        if apiMessage.deletedAt != nil {
            deleteMessageWithoutNotify(messageId: apiMessage.id)
            return
        }

        upsertMessageWithoutNotify(
            apiMessage.chatMessage,
            matchId: apiMessage.matchId,
            senderId: apiMessage.senderId,
            isRead: apiMessage.isRead
        )
    }

    private func upsertMessageWithoutNotify(
        _ message: ChatMessage,
        matchId: UUID,
        senderId: UUID?,
        isRead: Bool
    ) {
        execute(
            """
            INSERT OR REPLACE INTO messages (
                id, match_id, body, is_from_me, sender_id, is_read, created_at, created_at_ms
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            bind: { [self] statement in
                self.bind(statement, message.id.uuidString.lowercased(), 1)
                self.bind(statement, matchId.uuidString.lowercased(), 2)
                self.bind(statement, message.text, 3)
                sqlite3_bind_int(statement, 4, message.isFromMe ? 1 : 0)
                self.bind(statement, senderId?.uuidString.lowercased() ?? "", 5)
                sqlite3_bind_int(statement, 6, isRead ? 1 : 0)
                self.bind(statement, self.isoFormatter.string(from: message.timestamp), 7)
                sqlite3_bind_int64(statement, 8, self.millis(message.timestamp))
            }
        )
    }

    private func deleteMatchesNotIn(_ ids: Set<UUID>) {
        let storedIds = Set(matches().map(\.id))
        let staleIds = storedIds.subtracting(ids)
        staleIds.forEach(deleteMatch)
    }

    private func deleteMessageWithoutNotify(messageId: UUID) {
        execute("DELETE FROM messages WHERE id = ?", bind: { [self] statement in
            self.bind(statement, messageId.uuidString.lowercased(), 1)
        })
    }

    private func pruneMessagesWithoutNotify(matchId: UUID, keep count: Int = 500) {
        execute(
            """
            DELETE FROM messages
            WHERE match_id = ?
              AND id NOT IN (
                  SELECT id FROM messages
                  WHERE match_id = ?
                  ORDER BY created_at_ms DESC
                  LIMIT ?
              )
            """,
            bind: { [self] statement in
                self.bind(statement, matchId.uuidString.lowercased(), 1)
                self.bind(statement, matchId.uuidString.lowercased(), 2)
                sqlite3_bind_int(statement, 3, Int32(count))
            }
        )
    }

    private func messageTimestamp(messageId: UUID) -> Int64? {
        guard let db else { return nil }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT created_at_ms FROM messages WHERE id = ?", -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        bind(statement, messageId.uuidString.lowercased(), 1)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return sqlite3_column_int64(statement, 0)
    }

    private func messageMatchId(messageId: UUID) -> UUID? {
        guard let db else { return nil }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT match_id FROM messages WHERE id = ?", -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        bind(statement, messageId.uuidString.lowercased(), 1)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return uuid(statement, 0)
    }

    private func scalarInt(_ sql: String, bind: ((OpaquePointer?) -> Void)? = nil) -> Int64? {
        guard let db else { return nil }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        bind?(statement)
        guard sqlite3_step(statement) == SQLITE_ROW, sqlite3_column_type(statement, 0) != SQLITE_NULL else {
            return nil
        }
        return sqlite3_column_int64(statement, 0)
    }

    private func execute(_ sql: String, bind: ((OpaquePointer?) -> Void)? = nil) {
        guard let db else { return }
        Self.execute(db, sql, bind: bind)
    }

    private static func execute(_ db: OpaquePointer?, _ sql: String, bind: ((OpaquePointer?) -> Void)? = nil) {
        guard let db else { return }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }

        bind?(statement)
        sqlite3_step(statement)
    }

    private func notifyMatches() {
        let snapshot = matches()
        matchContinuations.values.forEach { $0.yield(snapshot) }
    }

    private func notifyMessages(matchId: UUID) {
        let snapshot = messages(matchId: matchId)
        messageContinuations[matchId]?.values.forEach { $0.yield(snapshot) }
    }

    private func removeMatchContinuation(_ id: UUID) {
        matchContinuations[id] = nil
    }

    private func removeMessageContinuation(_ id: UUID, matchId: UUID) {
        messageContinuations[matchId]?[id] = nil
        if messageContinuations[matchId]?.isEmpty == true {
            messageContinuations[matchId] = nil
        }
    }

    private func encodeProfile(_ profile: UserProfile) -> String? {
        guard let data = try? encoder.encode(profile) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func decodeProfile(_ rawValue: String) -> UserProfile? {
        guard let data = rawValue.data(using: .utf8) else { return nil }
        return try? decoder.decode(UserProfile.self, from: data)
    }

    private func date(from rawValue: String, fallbackMs: Int64) -> Date {
        isoFormatter.date(from: rawValue) ?? Date(timeIntervalSince1970: TimeInterval(fallbackMs) / 1_000)
    }

    private func millis(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000).rounded())
    }

    private func text(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard let cString = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: cString)
    }

    private func uuid(_ statement: OpaquePointer?, _ index: Int32) -> UUID? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL, let value = text(statement, index) else {
            return nil
        }
        return UUID(uuidString: value)
    }

    private func bind(_ statement: OpaquePointer?, _ value: String?, _ index: Int32) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
    }

    private static func addColumnIfMissing(
        _ db: OpaquePointer?,
        table: String,
        column: String,
        definition: String
    ) {
        guard !columnExists(db, table: table, column: column) else { return }
        execute(db, "ALTER TABLE \(table) ADD COLUMN \(definition)")
    }

    private static func columnExists(_ db: OpaquePointer?, table: String, column: String) -> Bool {
        guard let db else { return false }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(\(table))", -1, &statement, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(statement) }

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let name = sqlite3_column_text(statement, 1) else { continue }
            if String(cString: name) == column {
                return true
            }
        }
        return false
    }

    private static func defaultDatabaseURL() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return baseURL.appendingPathComponent("ClubMates/clubmates.sqlite")
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
