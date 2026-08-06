import SwiftUI

/// Shown once, before Ration touches the keychain for the first time.
///
/// The first read triggers a macOS permission prompt, because the credential
/// item belongs to Claude Code. An unexplained system dialog asking about a
/// keychain item is exactly the kind of thing people should be suspicious of —
/// so we explain it first, in our own words, and let them start it deliberately.
public struct OnboardingView: View {

    let onContinue: () -> Void

    public init(onContinue: @escaping () -> Void) {
        self.onContinue = onContinue
    }

    public var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)

                Text("Ration")
                    .font(.title2.weight(.semibold))

                Text("Your Claude usage, in the menu bar.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 28)
            .padding(.bottom, 22)

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                Row(
                    symbol: "key.fill",
                    title: "macOS will ask for permission",
                    detail:
                        "Ration reads the login session Claude Code already saved in your keychain. "
                        + "Because that item belongs to Claude Code, macOS will ask you to approve access. "
                        + "Choose “Always Allow” so it only asks once."
                )

                Row(
                    symbol: "eye.slash.fill",
                    title: "Read-only, and only one secret",
                    detail:
                        "Ration reads the access token and nothing else — not your refresh token, "
                        + "not your MCP server logins. It never writes to your keychain."
                )

                Row(
                    symbol: "network.badge.shield.half.filled",
                    title: "One request, one destination",
                    detail:
                        "The token is used for a single call to api.anthropic.com to read your usage. "
                        + "No analytics, no telemetry, nothing stored on disk."
                )
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)

            Divider()

            HStack {
                Link("View the source", destination: URL(string: Links.repository)!)
                    .font(.callout)

                Spacer()

                Button("Continue", action: onContinue)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 460)
    }

    private struct Row: View {
        let symbol: String
        let title: String
        let detail: String

        var body: some View {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 22)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.callout.weight(.medium))
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

enum Links {
    static let repository = "https://github.com/mcpeixoto/ration"
    static let privacy = "https://github.com/mcpeixoto/ration/blob/main/PRIVACY.md"
}
