import RationKit
import SwiftUI

/// Every tool Ration knows about, and the truth about each one.
///
/// Listing tools it cannot meter is deliberate. "Where is Cursor?" deserves an
/// answer in the app rather than in an issue thread, and the answer — its usage
/// lives behind a login on its website, and Ration will not read your browser's
/// cookies to get it — is a design decision worth stating out loud.
struct ProvidersSettingsView: View {

    @Bindable var registry: ProviderRegistry
    @Bindable var settings: Settings

    private var meterable: [Provider] {
        registry.metered.map(\.provider)
    }

    var body: some View {
        Form {
            Section {
                Picker("Menu bar shows", selection: $settings.primaryProvider) {
                    ForEach(meterable) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .disabled(meterable.count < 2)

                Text(
                    "The menu bar reports one tool. The panel shows them all — "
                        + "switch at the top of it."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Detected") {
                ForEach(registry.entries) { entry in
                    ProviderStatusRow(entry: entry)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct ProviderStatusRow: View {

    let entry: ProviderRegistry.Entry

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: entry.provider.symbolName)
                .frame(width: 16)
                .foregroundStyle(tint)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.provider.toolName)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)
        }
        .accessibilityElement(children: .combine)
    }

    private var tint: Color {
        switch entry.availability {
        case .ready: Theme.accent
        case .noData: .secondary
        case .notInstalled, .quotaNotReadable: Color.secondary.opacity(0.5)
        }
    }

    private var detail: String {
        switch entry.availability {
        case .ready:
            if let percent = entry.poller.state.snapshot?.primaryLimit?.percent {
                return "\(Int(percent.rounded()))% of the current window used."
            }
            return "Ready."
        default:
            return entry.availability.explanation ?? ""
        }
    }
}
