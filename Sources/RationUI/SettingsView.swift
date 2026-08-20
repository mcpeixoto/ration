import RationKit
import SwiftUI

public struct SettingsView: View {

    @Bindable var settings: Settings
    let registry: ProviderRegistry?
    let updater: (any UpdateControlling)?

    public init(
        settings: Settings,
        registry: ProviderRegistry? = nil,
        updater: (any UpdateControlling)? = nil
    ) {
        self.settings = settings
        self.registry = registry
        self.updater = updater
    }

    public var body: some View {
        TabView {
            general
                .tabItem { Label("General", systemImage: "gearshape") }
            if let registry {
                AccountsSettingsView(registry: registry, settings: settings)
                    .tabItem { Label("Accounts", systemImage: "person.2") }
            }
            about
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 440)
    }

    // MARK: General

    private var general: some View {
        Form {
            Section {
                Picker("Menu bar shows", selection: $settings.displayMode) {
                    ForEach(MenuBarDisplayMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                Text(settings.displayMode.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Show a weekly usage bar", isOn: $settings.showWeeklyBar)
                Text(
                    "A small bar beside the icon, filling up as the week's allowance "
                        + "is spent."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Toggle("Colour when close to a limit", isOn: $settings.useSeverityColor)
                Text("Turns amber past 80% and red past 90%.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Check every", selection: $settings.pollInterval) {
                    ForEach(Settings.pollIntervalOptions, id: \.self) { seconds in
                        Text(intervalLabel(seconds)).tag(seconds)
                    }
                }
                Text(
                    "Once a minute is the fastest Ration will check. "
                        + "Each tick reads every account you have switched on."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Notify me when I approach a limit", isOn: $settings.notifyOnThresholds)

                Toggle(
                    "Open at login",
                    isOn: Binding(
                        get: { settings.launchesAtLogin },
                        set: { settings.launchesAtLogin = $0 }
                    ))

                if let error = settings.launchAtLoginError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            if let updater, updater.canCheck {
                updateSection(updater)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func updateSection(_ updater: any UpdateControlling) -> some View {
        Section {
            Toggle(
                "Install updates automatically",
                isOn: Binding(
                    get: { updater.automaticallyChecks },
                    set: { updater.automaticallyChecks = $0 }
                ))

            HStack {
                Text(lastCheckLabel(updater.lastCheck))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Check Now") { updater.checkNow() }
                    .controlSize(.small)
            }

            Text(
                "Updates are downloaded from GitHub and verified against a signing key "
                    + "built into this app. An update that isn't signed by the Ration key "
                    + "is refused."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func lastCheckLabel(_ date: Date?) -> String {
        guard let date else { return "Not checked yet" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Last checked \(formatter.localizedString(for: date, relativeTo: Date()))"
    }

    private func intervalLabel(_ seconds: Double) -> String {
        seconds < 60
            ? "\(Int(seconds)) seconds"
            : "\(Int(seconds / 60)) minute\(seconds >= 120 ? "s" : "")"
    }

    // MARK: About

    private var about: some View {
        VStack(spacing: 14) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)

            VStack(spacing: 3) {
                Text("Ration")
                    .font(.title3.weight(.semibold))
                Text("Version \(Ration.version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(
                "Ration reads the sessions your tools already stored — Claude Code "
                    + "from its login, Cursor on disk, Codex in its session files — "
                    + "and shows how much of each plan you have used. "
                    + "It collects no analytics and stores nothing of yours on disk."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 30)

            HStack(spacing: 16) {
                Link("Source", destination: URL(string: Links.repository)!)
                Link("Privacy", destination: URL(string: Links.privacy)!)
                Link("Buy me a coffee", destination: URL(string: Links.coffee)!)
            }
            .font(.callout)

            Text("Not affiliated with Anthropic, OpenAI, or Anysphere.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
    }
}
