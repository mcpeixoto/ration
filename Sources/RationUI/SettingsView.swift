import RationKit
import SwiftUI

public struct SettingsView: View {

    @Bindable var settings: Settings

    public init(settings: Settings) {
        self.settings = settings
    }

    public var body: some View {
        TabView {
            general
                .tabItem { Label("General", systemImage: "gearshape") }
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

                Toggle("Colour the icon when close to a limit", isOn: $settings.useSeverityColor)
                Text("Turns amber as you approach a limit and red when you reach it.")
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
                    "Ration checks more often while the panel is open. "
                        + "The minimum is \(Int(PollSchedule.minimumInterval)) seconds."
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
        }
        .formStyle(.grouped)
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
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)

            VStack(spacing: 3) {
                Text("Ration")
                    .font(.title3.weight(.semibold))
                Text("Version \(Ration.version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(
                "Ration reads the Claude Code session already stored in your keychain "
                    + "and asks Anthropic how much of your plan you have used. "
                    + "It collects no analytics and stores nothing on disk."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 30)

            HStack(spacing: 16) {
                Link("Source", destination: URL(string: Links.repository)!)
                Link("Privacy", destination: URL(string: Links.privacy)!)
            }
            .font(.callout)

            Text("Not affiliated with or endorsed by Anthropic.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
    }
}
