import Foundation
import SQLite3

actor ProfileLocalStore {
    static let shared = ProfileLocalStore()

    private var db: OpaquePointer?

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init(path: URL? = nil) {
        let url = path ?? Self.defaultDatabaseURL()
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if sqlite3_open(url.path, &db) == SQLITE_OK {
            Self.migrate(db)
        }
    }

    deinit { sqlite3_close(db) }

    // MARK: - Read

    func loadProfile() -> UserProfile? {
        guard let db else { return nil }
        let sql = """
        SELECT id, name, age, bio, distance, profession, gender, height,
               is_verified, looking_for, interests_json, prompts_json, photos_json,
               preferences_json, notif_prefs_json, is_ghost_mode
        FROM user_profile
        LIMIT 1
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }

        guard
            let idStr = text(stmt, 0), let id = UUID(uuidString: idStr),
            let name = text(stmt, 1)
        else { return nil }

        let age = Int(sqlite3_column_int(stmt, 2))
        let bio = text(stmt, 3) ?? ""
        let distance = sqlite3_column_double(stmt, 4)
        let profession = text(stmt, 5) ?? ""
        let gender = text(stmt, 6) ?? ""
        let height = Int(sqlite3_column_int(stmt, 7))
        let isVerified = sqlite3_column_int(stmt, 8) == 1
        let lookingFor = text(stmt, 9) ?? ""
        let interests: [String] = decode(text(stmt, 10)) ?? []
        let prompts: [UserProfile.Prompt] = decode(text(stmt, 11)) ?? []
        let photos: [ProfilePhoto] = decode(text(stmt, 12)) ?? []
        let preferences: DatePreferences = decode(text(stmt, 13)) ?? .default
        let notifPrefs: NotificationPreferences = decode(text(stmt, 14)) ?? .default
        let isGhostMode = sqlite3_column_int(stmt, 15) == 1

        return UserProfile(
            id: id, name: name, age: age, bio: bio, distance: distance,
            prompts: prompts, photos: photos, interests: interests,
            profession: profession, gender: gender, height: height,
            isVerified: isVerified, isGhostMode: isGhostMode, lookingFor: lookingFor,
            preferences: preferences, notificationPreferences: notifPrefs
        )
    }

    // MARK: - Write

    func save(_ profile: UserProfile, dirty: Bool = true, syncedAt: Date? = nil) {
        guard let db else { return }
        let sql = """
        INSERT OR REPLACE INTO user_profile (
            id, name, age, bio, distance, profession, gender, height,
            is_verified, looking_for, interests_json, prompts_json, photos_json,
            preferences_json, notif_prefs_json, is_ghost_mode, is_dirty, last_synced_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        bind(stmt, profile.id.uuidString.lowercased(), 1)
        bind(stmt, profile.name, 2)
        sqlite3_bind_int(stmt, 3, Int32(profile.age))
        bind(stmt, profile.bio, 4)
        sqlite3_bind_double(stmt, 5, profile.distance)
        bind(stmt, profile.profession, 6)
        bind(stmt, profile.gender, 7)
        sqlite3_bind_int(stmt, 8, Int32(profile.height))
        sqlite3_bind_int(stmt, 9, profile.isVerified ? 1 : 0)
        bind(stmt, profile.lookingFor, 10)
        bind(stmt, encode(profile.interests), 11)
        bind(stmt, encode(profile.prompts), 12)
        bind(stmt, encode(profile.photos), 13)
        bind(stmt, encode(profile.preferences), 14)
        bind(stmt, encode(profile.notificationPreferences), 15)
        sqlite3_bind_int(stmt, 16, profile.isGhostMode ? 1 : 0)
        sqlite3_bind_int(stmt, 17, dirty ? 1 : 0)
        if let syncedAt {
            sqlite3_bind_int64(stmt, 18, Int64(syncedAt.timeIntervalSince1970 * 1000))
        } else {
            sqlite3_bind_null(stmt, 18)
        }

        sqlite3_step(stmt)
    }

    func markClean(syncedAt: Date) {
        guard let db else { return }
        let ms = Int64(syncedAt.timeIntervalSince1970 * 1000)
        Self.execute(db, "UPDATE user_profile SET is_dirty = 0, last_synced_at = \(ms)")
    }

    func isDirty() -> Bool {
        guard let db else { return false }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT is_dirty FROM user_profile LIMIT 1", -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return false }
        return sqlite3_column_int(stmt, 0) == 1
    }

    func lastSyncedAt() -> Date? {
        guard let db else { return nil }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT last_synced_at FROM user_profile LIMIT 1", -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW,
              sqlite3_column_type(stmt, 0) != SQLITE_NULL else { return nil }
        let ms = sqlite3_column_int64(stmt, 0)
        return ms > 0 ? Date(timeIntervalSince1970: TimeInterval(ms) / 1000) : nil
    }

    func clear() {
        guard let db else { return }
        Self.execute(db, "DELETE FROM user_profile")
    }

    // MARK: - Migration

    private static func migrate(_ db: OpaquePointer?) {
        execute(db, """
        CREATE TABLE IF NOT EXISTS user_profile (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL DEFAULT '',
            age INTEGER NOT NULL DEFAULT 18,
            bio TEXT NOT NULL DEFAULT '',
            distance REAL NOT NULL DEFAULT 0,
            profession TEXT NOT NULL DEFAULT '',
            gender TEXT NOT NULL DEFAULT '',
            height INTEGER NOT NULL DEFAULT 170,
            is_verified INTEGER NOT NULL DEFAULT 0,
            looking_for TEXT NOT NULL DEFAULT '',
            interests_json TEXT NOT NULL DEFAULT '[]',
            prompts_json TEXT NOT NULL DEFAULT '[]',
            photos_json TEXT NOT NULL DEFAULT '[]',
            preferences_json TEXT NOT NULL DEFAULT '{}',
            notif_prefs_json TEXT NOT NULL DEFAULT '{}',
            is_ghost_mode INTEGER NOT NULL DEFAULT 0,
            is_dirty INTEGER NOT NULL DEFAULT 0,
            last_synced_at INTEGER
        )
        """)
        // Add columns if upgrading from older schema
        addColumnIfMissing(db, table: "user_profile", column: "is_dirty", definition: "is_dirty INTEGER NOT NULL DEFAULT 0")
        addColumnIfMissing(db, table: "user_profile", column: "last_synced_at", definition: "last_synced_at INTEGER")
        addColumnIfMissing(db, table: "user_profile", column: "is_ghost_mode", definition: "is_ghost_mode INTEGER NOT NULL DEFAULT 0")
    }

    // MARK: - Helpers

    private func encode<T: Encodable>(_ value: T) -> String? {
        guard let data = try? encoder.encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func decode<T: Decodable>(_ raw: String?) -> T? {
        guard let raw, let data = raw.data(using: .utf8) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    private func text(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let c = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: c)
    }

    private func bind(_ stmt: OpaquePointer?, _ value: String?, _ index: Int32) {
        guard let value else { sqlite3_bind_null(stmt, index); return }
        sqlite3_bind_text(stmt, index, value, -1, SQLITE_TRANSIENT)
    }

    private static func execute(_ db: OpaquePointer?, _ sql: String) {
        guard let db else { return }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_step(stmt)
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
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(\(table))", -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }

        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let name = sqlite3_column_text(stmt, 1) else { continue }
            if String(cString: name) == column {
                return true
            }
        }
        return false
    }

    private static func defaultDatabaseURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("ClubMates/clubmates.sqlite")
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
