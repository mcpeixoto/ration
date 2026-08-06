//
// Renders the popover to PNG files, so the UI can be reviewed and README
// screenshots regenerated without taking a manual screenshot.
//
// Usage: swift run RationPreview [output-directory]
//

import AppKit
import RationKit
import RationUI
import SwiftUI

/// Renders through a real `NSHostingView` rather than `ImageRenderer`.
///
/// `ImageRenderer` draws SwiftUI primitives but cannot resolve AppKit-backed
/// controls, so every `Button` comes out as a placeholder glyph. Hosting the
/// view for real costs a run-loop turn and gives an honest picture.
@MainActor
func render<V: View>(_ view: V, to url: URL, scale: CGFloat, appearance: NSAppearance.Name) {
    let hosting = NSHostingView(
        rootView:
            view
            .environment(\.rationAnimatesEntrance, false)
            .environment(\.colorScheme, appearance == .darkAqua ? .dark : .light)
            .background(appearance == .darkAqua ? Color(white: 0.13) : Color(white: 0.96))
    )
    hosting.appearance = NSAppearance(named: appearance)
    hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)

    // Give AppKit a turn to lay out and resolve its controls before capturing.
    hosting.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.15))

    guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
        print("failed to render \(url.lastPathComponent)")
        return
    }
    // bitmapImageRepForCachingDisplay honours the backing scale factor of the
    // main screen, so ask for the pixel size we actually want.
    rep.size = hosting.bounds.size
    hosting.cacheDisplay(in: hosting.bounds, to: rep)

    guard let data = rep.representation(using: .png, properties: [:]) else {
        print("failed to encode \(url.lastPathComponent)")
        return
    }
    try? data.write(to: url)
    print("wrote \(url.lastPathComponent) (\(rep.pixelsWide)x\(rep.pixelsHigh))")
}

/// A representative account: an active session, a weekly limit, and a
/// model-scoped limit.
func sampleSnapshot() -> UsageSnapshot {
    UsageSnapshot(limits: [
        UsageLimit(
            kind: .session, group: .session, percent: 50,
            severity: .normal, resetsAt: Date(timeIntervalSinceNow: 3900), isActive: true),
        UsageLimit(
            kind: .weeklyAll, group: .weekly, percent: 52,
            severity: .normal, resetsAt: Date(timeIntervalSinceNow: 183_600), isActive: true),
        UsageLimit(
            kind: .weeklyScoped, group: .weekly, percent: 3,
            severity: .normal, resetsAt: Date(timeIntervalSinceNow: 183_600),
            scope: .init(modelDisplayName: "Fable"), isActive: false),
    ])
}

// `swift run RationPreview video <dir>` emits a frame sequence instead of
// the still screenshots.
let isVideo = CommandLine.arguments.count > 1 && CommandLine.arguments[1] == "video"

let outputDirectory = URL(
    fileURLWithPath: CommandLine.arguments.count > (isVideo ? 2 : 1)
        ? CommandLine.arguments[isVideo ? 2 : 1]
        : (isVideo ? ".build/video-frames" : "docs/images"))
try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

MainActor.assumeIsolated {
    // Without a shared application, AppKit will not resolve SF Symbols and the
    // header buttons render as placeholder glyphs.
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)

    if isVideo {
        do {
            try Video.render(to: outputDirectory, appearance: .darkAqua)
        } catch {
            print("video render failed: \(error)")
            exit(1)
        }
        exit(0)
    }

    let defaults = UserDefaults(suiteName: "com.mcpeixoto.Ration.preview")!
    defaults.removePersistentDomain(forName: "com.mcpeixoto.Ration.preview")
    let settings = Settings(defaults: defaults)
    settings.hasCompletedOnboarding = true

    let poller = UsagePoller(
        credentialStore: PreviewCredentialStore(),
        client: PreviewLimitsClient(snapshot: sampleSnapshot()))

    let transcripts = TranscriptStore(
        root: sampleTranscriptRoot(), supportDirectory: temporaryPreviewSupport())

    let popover = PopoverView(
        poller: poller, settings: settings, transcripts: transcripts,
        openSettings: {}, startSetup: {}, quit: {})

    // Drive one refresh so the poller holds the sample snapshot. The poller is
    // async and main-actor bound, so pump the run loop rather than blocking it.
    poller.start()
    let deadline = Date().addingTimeInterval(3)
    while poller.state.snapshot == nil && Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
    }
    poller.suspend()

    guard poller.state.snapshot != nil else {
        print("error: preview poller never produced a snapshot")
        exit(1)
    }

    // Scan the synthetic corpus so Activity and Metrics have data.
    transcripts.refresh()
    let scanDeadline = Date().addingTimeInterval(10)
    while transcripts.status != .ready && Date() < scanDeadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
    }

    render(
        popover, to: outputDirectory.appendingPathComponent("popover-dark.png"),
        scale: 2, appearance: .darkAqua)
    render(
        popover, to: outputDirectory.appendingPathComponent("popover-light.png"),
        scale: 2, appearance: .aqua)

    // The other two tabs, rendered standalone — the switcher is state inside
    // PopoverView and a static render can't click it.
    render(
        TabPreview(title: "Activity") {
            ActivityView(history: transcripts.history, status: .ready)
        },
        to: outputDirectory.appendingPathComponent("activity-dark.png"),
        scale: 2, appearance: .darkAqua)
    render(
        TabPreview(title: "Metrics") {
            MetricsView(history: transcripts.history, status: .ready)
        },
        to: outputDirectory.appendingPathComponent("metrics-dark.png"),
        scale: 2, appearance: .darkAqua)
    render(
        TabPreview(title: "Metrics") {
            MetricsView(history: transcripts.history, status: .ready)
        },
        to: outputDirectory.appendingPathComponent("metrics-light.png"),
        scale: 2, appearance: .aqua)

    render(
        OnboardingView(onContinue: {}),
        to: outputDirectory.appendingPathComponent("onboarding-dark.png"),
        scale: 2, appearance: .darkAqua)
}
