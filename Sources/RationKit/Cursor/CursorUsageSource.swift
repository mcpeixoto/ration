import Foundation

/// Cursor's usage, as a `UsageSource`.
///
/// Owns the local-state read as well as the request, because the two belong
/// together: the token is read, used once, and never held anywhere else. The
/// token lives in a sqlite file Cursor already wrote, not the keychain, so
/// this source never triggers a permission prompt.
public struct CursorUsageSource: UsageSource {

    public var provider: Provider { .cursor }

    private let supportDirectory: URL
    private let store: CursorSessionStore
    private let client: CursorLimitsClient

    public init(
        supportDirectory: URL? = nil,
        store: CursorSessionStore = CursorSessionStore(),
        client: CursorLimitsClient = CursorLimitsClient()
    ) {
        self.supportDirectory =
            supportDirectory
            ?? URL(fileURLWithPath: NSHomeDirectory())
            .appending(path: "Library/Application Support/Cursor")
        self.store = store
        self.client = client
    }

    public var promptsForPermission: Bool { false }

    public func availability() -> ProviderAvailability {
        guard FileManager.default.fileExists(atPath: supportDirectory.path) else {
            return .notInstalled
        }
        do {
            _ = try store.session()
            return .ready
        } catch CursorSessionStore.Error.notFound {
            return .noData(reason: "Sign in to Cursor first.")
        } catch {
            return .noData(reason: "Cursor is installed, but its session could not be read.")
        }
    }

    public func fetchUsage() async throws -> UsageSnapshot {
        let session: CursorSession
        do {
            session = try store.session()
        } catch CursorSessionStore.Error.notFound {
            throw LimitsError.noData(reason: "Sign in to Cursor first.")
        } catch {
            throw LimitsError.decoding(message: error.localizedDescription)
        }

        return try await client.fetchUsage(token: session.accessToken, planName: session.planName)
    }
}
