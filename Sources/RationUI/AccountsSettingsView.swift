import RationKit
import SwiftUI

/// The account behind every tool Ration knows about, and a switch for each one
/// it can actually meter.
///
/// Listing tools it cannot meter is deliberate. Copilot and Gemini keep their
/// quota behind a login Ration will not mint, and the Accounts tab says so
/// rather than quietly omitting them.
///
/// There is deliberately no way to add a *second* account of the same tool.
/// Each tool stores only the account you are signed into, and Ration reads
/// what they stored rather than keeping credentials of its own.
struct AccountsSettingsView: View {

    @Bindable var registry: ProviderRegistry
    @Bindable var settings: Settings

    /// Providers that can be metered and have not been switched off.
    private var selectable: [Provider] {
        registry.metered.map(\.provider)
    }

    /// Everything that can carry a gauge, switched on or not — so turning one
    /// off does not make its own switch disappear.
    private var accounts: [ProviderRegistry.Entry] {
        registry.entries.filter { $0.availability.hasQuota }
    }

    private var unmetered: [ProviderRegistry.Entry] {
        registry.entries.filter { !$0.availability.hasQuota }
    }

    var body: some View {
        Form {
            Section {
                Picker("Panel opens on", selection: $settings.primaryProvider) {
                    ForEach(selectable) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .disabled(selectable.count < 2)

                Text(
                    "The menu bar reports every account that is on. The panel "
                        + "opens on this one — switch at the top of it."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Accounts") {
                ForEach(accounts) { entry in
                    AccountRow(
                        entry: entry,
                        isEnabled: Binding(
                            get: { registry.isEnabled(entry.provider) },
                            set: { setEnabled($0, for: entry.provider) }
                        ))
                }

                if registry.isEverythingHidden {
                    Text(
                        "Every account is off. Ration is not reading anything, "
                            + "and the menu bar shows no usage."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            if !unmetered.isEmpty {
                Section("Not metered") {
                    ForEach(unmetered) { entry in
                        UnmeteredRow(entry: entry)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    /// The registry is the live truth; settings only persists it. Writing both
    /// here keeps that one-way relationship in one place.
    private func setEnabled(_ enabled: Bool, for provider: Provider) {
        registry.setEnabled(enabled, for: provider)
        settings.disabledProviders = registry.disabled
    }
}

/// One metered account: what it is, what Ration reads for it, and a switch.
private struct AccountRow: View {

    let entry: ProviderRegistry.Entry
    @Binding var isEnabled: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: entry.provider.symbolName)
                .frame(width: 16)
                .foregroundStyle(isEnabled ? Theme.accent : .secondary)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !source.isEmpty {
                    Text(source)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            Toggle("", isOn: $isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityLabel("Show \(entry.provider.toolName)")
        }
        .accessibilityElement(children: .contain)
    }

    /// The plan is the only name Ration has for an account: the session
    /// Claude Code stores carries no email and no account id.
    private var title: String {
        guard let plan = entry.poller.planName, !plan.isEmpty else {
            return entry.provider.toolName
        }
        return "\(entry.provider.toolName) — \(plan.capitalized)"
    }

    private var detail: String {
        guard isEnabled else { return "Hidden, and not being read." }

        switch entry.availability {
        case .ready:
            if let percent = entry.poller.state.snapshot?.primaryLimit?.percent {
                return "\(Int(percent.rounded()))% of the current window used."
            }
            return "Ready."
        default:
            return entry.availability.explanation ?? "Ready."
        }
    }

    /// What Ration reads to produce the row above — shown regardless of the
    /// toggle, because a user deciding whether to turn an account off is
    /// exactly who needs to know what reading it entails.
    private var source: String {
        switch entry.provider {
        case .claude:
            return "Reads the Claude Code session already on this Mac, and asks "
                + "api.anthropic.com for your limits."
        case .codex:
            return "Reads the session files Codex already writes to disk. "
                + "No request, no credential."
        case .cursor:
            return "Reads the session Cursor already stored on disk, and asks "
                + "api2.cursor.sh for your limits, burn rate, and usage log."
        default:
            return ""
        }
    }
}

/// A tool Ration can see but cannot meter. No switch: there is nothing to
/// turn off.
private struct UnmeteredRow: View {

    let entry: ProviderRegistry.Entry

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: entry.provider.symbolName)
                .frame(width: 16)
                .foregroundStyle(Color.secondary.opacity(0.5))
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.provider.toolName)
                    .foregroundStyle(.secondary)
                Text(entry.availability.explanation ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)
        }
        .accessibilityElement(children: .combine)
    }
}
