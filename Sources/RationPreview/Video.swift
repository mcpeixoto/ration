import AppKit
import RationKit
import RationUI
import SwiftUI

/// Renders a frame sequence for the demo video.
///
/// The motion is real: every frame is the actual SwiftUI view fed different
/// data, not a mockup or a keyframed animation. The ring sweeps because the
/// percentage genuinely rises; the metrics bars grow because the history
/// genuinely gets longer.
@MainActor
enum Video {

    static let fps = Timeline.fps

    static func render(to directory: URL, appearance: NSAppearance.Name) throws {
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)

        var frame = 0
        let history = try loadedHistory()

        for index in 0..<Timeline.frameCount {
            let time = Double(index) / Double(Timeline.fps)
            let url = directory.appendingPathComponent(String(format: "frame-%05d.png", frame))
            renderFrame(
                MacBookScene(
                    state: Timeline.state(at: time),
                    history: history,
                    metricsDays: Timeline.metricsDays(at: time)),
                to: url, appearance: appearance)
            frame += 1
        }

        print("wrote \(frame) frames to \(directory.path)")
    }

    // MARK: Helpers

    /// Ease-in-out, so the motion starts and settles gently instead of
    /// snapping — the same curve the app's own animations use.
    private static func ease(_ t: Double) -> Double {
        t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
    }

    /// Scans the synthetic corpus once and returns the rolled-up history.
    private static func loadedHistory() throws -> UsageHistory {
        let store = TranscriptStore(
            root: sampleTranscriptRoot(), supportDirectory: temporaryPreviewSupport())
        store.refresh()

        let deadline = Date().addingTimeInterval(20)
        while store.status != .ready && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        return store.history
    }

    /// Keeps only the most recent `days` of history, so replaying it frame by
    /// frame makes the metrics genuinely accumulate.
    private static func truncate(_ history: UsageHistory, toLast days: Int) -> UsageHistory {
        let calendar = Calendar.current
        guard let cutoff = calendar.date(byAdding: .day, value: -days, to: Date()) else {
            return history
        }
        return UsageHistory(days: history.days.filter { $0.key >= cutoff })
    }

    private static func renderFrame(
        _ view: some View, to url: URL, appearance: NSAppearance.Name
    ) {
        let hosting = NSHostingView(
            rootView:
                view
                .environment(\.rationAnimatesEntrance, false)
                .environment(\.colorScheme, appearance == .darkAqua ? .dark : .light)
        )
        hosting.appearance = NSAppearance(named: appearance)
        // A fixed frame keeps every frame the same size — ffmpeg rejects a
        // sequence whose dimensions wobble.
        hosting.frame = NSRect(
            x: 0, y: 0, width: Timeline.stage.width, height: Timeline.stage.height)
        hosting.layoutSubtreeIfNeeded()

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        rep.size = hosting.bounds.size
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}

// MARK: - Framing

/// The panel chrome, so each act looks like the real app rather than a
/// floating fragment.
private struct DemoPanel<Content: View>: View {
    let tab: PanelTab
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Text("Ration").font(.headline)
                Text("Max")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "arrow.clockwise").foregroundStyle(.secondary)
                Image(systemName: "gearshape").foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)

            StaticTabBar(selection: tab)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)

            Divider()
            content
            Spacer(minLength: 0)
        }
        .frame(width: 340, height: 540, alignment: .top)
        .background(
            Color(red: 0.11, green: 0.10, blue: 0.10),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.5), radius: 18, y: 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DemoBackground())
    }
}

/// The tab bar without the interactive state, since a frame sequence has no
/// clicks to respond to.
private struct StaticTabBar: View {
    let selection: PanelTab

    var body: some View {
        HStack(spacing: 2) {
            ForEach(PanelTab.meterTabs) { tab in
                HStack(spacing: 4) {
                    Image(systemName: tab.symbol).font(.system(size: 9))
                    Text(tab.title).font(.caption).lineLimit(1).minimumScaleFactor(0.75)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .foregroundStyle(selection == tab ? Color.primary : .secondary)
                .background {
                    if selection == tab {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(.primary.opacity(0.09))
                    }
                }
            }
        }
        .padding(2)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.primary.opacity(0.05))
        }
    }
}

/// A warm backdrop that picks up the app's own accent, so the panel reads as
/// a product shot rather than a screenshot on a grey rectangle.
private struct DemoBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.09, green: 0.07, blue: 0.06),
                    Color(red: 0.16, green: 0.10, blue: 0.08),
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            // A soft bloom behind the panel, in the accent colour.
            RadialGradient(
                colors: [Color(red: 0.85, green: 0.47, blue: 0.34).opacity(0.22), .clear],
                center: .center, startRadius: 10, endRadius: 340
            )
        }
        .ignoresSafeArea()
    }
}

// MARK: - Act 1 content

/// The Usage tab at a point in its sweep. `progress` scales every limit, so
/// the ring and the bars rise together the way they do on a real refresh.
private struct UsageDemo: View {
    let progress: Double

    private var snapshot: UsageSnapshot {
        UsageSnapshot(limits: [
            UsageLimit(
                kind: .session, group: .session, percent: 50 * progress,
                severity: .normal, resetsAt: Date(timeIntervalSinceNow: 3900), isActive: true),
            UsageLimit(
                kind: .weeklyAll, group: .weekly, percent: 52 * progress,
                severity: .normal, resetsAt: Date(timeIntervalSinceNow: 183_600), isActive: true),
            UsageLimit(
                kind: .weeklyScoped, group: .weekly, percent: 3 * progress,
                severity: .normal, resetsAt: Date(timeIntervalSinceNow: 183_600),
                scope: .init(modelDisplayName: "Fable"), isActive: false),
        ])
    }

    var body: some View {
        let hero = snapshot.sessionLimit!
        let rest = snapshot.limits.filter { $0.id != hero.id }

        VStack(spacing: 0) {
            VStack(spacing: 10) {
                RingGauge(percent: hero.percent, severity: hero.severity)
                VStack(spacing: 3) {
                    Text("Session").font(.subheadline.weight(.semibold))
                    Text(RelativeTime.sentence(until: hero.resetsAt ?? Date()))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.top, 20)
            .padding(.bottom, 18)

            VStack(spacing: 2) {
                ForEach(rest) { limit in
                    LimitRowView(limit: limit, now: Date())
                }
            }
            .padding(.horizontal, 6)
        }
    }
}
