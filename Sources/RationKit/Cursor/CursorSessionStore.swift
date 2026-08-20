import Foundation
#if canImport(SQLite3)
import SQLite3
#else
import CSqlite3
#endif

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
/// Read-only by construction: every path opens the file with
/// `SQLITE_OPEN_READONLY`, so a busy editor cannot be disturbed and nothing
/// here can write.
///
/// The live file is tried first. Copying it was the original approach, but
/// `state.vscdb` is a working database that grows without bound — 11 GB on a
/// machine that has used Cursor heavily — and duplicating it into the temp
/// directory to read two rows costs minutes of I/O and gigabytes of disk on
/// every poll. A read-only connection is enough for the common case; the copy
/// stays as the fallback for when SQLite refuses, which is what happens if
/// Cursor holds the WAL index and Ration cannot map it.
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

        if let session = try? read(at: databaseURL.path) {
            return session
        }

        // SQLite would not open the live file — Cursor is holding it in a way
        // this process cannot read through. Fall back to the copy.
        let copy = try snapshotCopy()
        defer { try? FileManager.default.removeItem(at: copy.deletingLastPathComponent()) }
        return try read(at: copy.path)
    }

    /// Opens one database read-only and pulls the two values Ration needs.
    private func read(at path: String) throws -> CursorSession {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK, let db else {
            sqlite3_close(db)
            throw Error.malformed
        }
        defer { sqlite3_close(db) }

        let token = try string(for: Self.tokenKey, in: db)
        guard let token, !token.isEmpty else { throw Error.notFound }
        let plan = try string(for: Self.planKey, in: db)

        return CursorSession(accessToken: token, planName: plan)
    }

    /// Copies the db (and its WAL siblings) into a throwaway directory, for
    /// when the live file cannot be opened at all.
    ///
    /// Expensive by nature — the file is as large as Cursor has let it grow —
    /// so this runs only after a direct read has failed.
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
