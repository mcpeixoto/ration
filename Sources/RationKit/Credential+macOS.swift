#if os(macOS)

import Foundation
import Security

/// Reads Claude Code's credentials from the login keychain.
///
/// Read-only by construction: this type calls `SecItemCopyMatching` and
/// nothing else. There is no code path here that adds, updates, or deletes a
/// keychain item.
///
/// The first read triggers a system prompt, because the item's ACL was created
/// by Claude Code and does not list Ration. Choosing "Always Allow" adds Ration
/// to that ACL and the prompt does not return. `OnboardingView` explains this
/// before it happens.
public struct KeychainCredentialStore: CredentialStore {

    /// The service name Claude Code stores its credentials under.
    public static let service = "Claude Code-credentials"

    public init() {}

    public func credential() throws -> Credential {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { throw CredentialError.malformed }
            return try Credential.parse(from: data)
        case errSecItemNotFound:
            throw CredentialError.notFound
        case errSecAuthFailed, errSecUserCanceled, errSecInteractionNotAllowed:
            throw CredentialError.accessDenied
        default:
            throw CredentialError.keychain(status: status)
        }
    }
}

/// The credential store Ration uses on macOS.
public typealias DefaultCredentialStore = KeychainCredentialStore

#endif
