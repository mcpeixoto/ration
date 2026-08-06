import Foundation
import RationKit

/// Stand-ins so previews render without a keychain or a network.
struct PreviewCredentialStore: CredentialStore {
    func credential() throws -> Credential {
        Credential(
            accessToken: "preview", expiresAt: Date(timeIntervalSinceNow: 3600),
            subscriptionType: "max", rateLimitTier: "default_claude_max_5x")
    }
}

struct PreviewLimitsClient: LimitsClient {
    let snapshot: UsageSnapshot
    func fetchUsage(token: String) async throws -> UsageSnapshot { snapshot }
}
