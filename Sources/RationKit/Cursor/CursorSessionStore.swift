import Foundation
import SQLite3

/// The Cursor login already on disk: the access token the app uses, and the
/// plan name it cached beside it.
///
/// Ration reads those two fields and nothing else. In particular it never
/// reads a refresh secret — Cursor rotates that itself.
public struct CursorSession: Sendable {
    public let accessToken: String
    public let planName: String?

    public init(accessToken: String, planName: String?) {
        self.accessToken = accessToken
        self.planName = planName
    }
}

extension CursorSession: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        let plan = planName ?? "unknown plan"
        return "CursorSession(token: <redacted>, plan: \(plan))"
    }

    public var debugDescription: String { description }
}

/// Reads Cursor's local state database.
///
/// Read-only by construction: the file is opened with `SQLITE_OPEN_READONLY`
/// after being copied, so a busy editor cannot be disturbed and nothing here
/// can write. The copy is what makes that safe — Cursor keeps the live file
/// locked.
public struct CursorSessionStore: Sendable {

    public enum Error: Swift.Error, Equatable {
        case notFound
        case malformed
    }

    /// Key Cursor stores the Bearer token under. Camel-case on purpose: a
    /// neighbouring test forbids the snake-case spelling other tools use.
    static let tokenKey = "cursorAuth/accessToken"
    static let planKey = "cursorAuth/stripeMembershipType"

    public let databaseURL: URL

    public init(databaseURL: URL? = nil) {
        self.databaseURL = databaseURL ?? PlatformPaths.cursorStateDatabase
    }

    public func session() throws -> CursorSession {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw Error.notFound
        }

        let copy = try snapshotCopy()
        defer { try? FileManager.default.removeItem(at: copy.deletingLastPathComponent()) }

        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(copy.path, &db, flags, nil) == SQLITE_OK, let db else {
            sqlite3_close(db)
            throw Error.malformed
        }
        defer { sqlite3_close(db) }

        let token = try string(for: Self.tokenKey, in: db)
        guard let token, !token.isEmpty else { throw Error.notFound }
        let plan = try string(for: Self.planKey, in: db)

        return CursorSession(accessToken: token, planName: plan)
    }

    /// Copy the db (and its WAL siblings) into a throwaway directory so we
    /// never open the file Cursor itself has locked.
    private func snapshotCopy() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "ration-cursor-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appending(path: databaseURL.lastPathComponent)
        try FileManager.default.copyItem(at: databaseURL, to: dest)
        for suffix in ["-wal", "-shm"] {
            let extra = URL(fileURLWithPath: databaseURL.path + suffix)
            if FileManager.default.fileExists(atPath: extra.path) {
                try? FileManager.default.copyItem(
                    at: extra, to: URL(fileURLWithPath: dest.path + suffix))
            }
        }
        return dest
    }

    private func string(for key: String, in db: OpaquePointer) throws -> String? {
        let sql = "SELECT value FROM ItemTable WHERE key = ? LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw Error.malformed
        }
        defer { sqlite3_finalize(stmt) }

        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, key, -1, transient)

        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        guard let pointer = sqlite3_column_text(stmt, 0) else { return nil }
        return String(cString: pointer)
    }
}
