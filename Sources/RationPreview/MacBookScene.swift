import AppKit
import RationKit
import RationUI
import SwiftUI

// MARK: - Timeline

/// The state of the scene at one instant.
///
/// Everything the video shows is derived from this, so the animation is one
/// pure function of time rather than a pile of per-frame special cases.
struct SceneState {
    var cursor: CGPoint
    /// 0 = closed, 1 = fully open. Drives the panel's scale and opacity.
    var panelOpen: Double
    var tab: PanelTab
    /// Scales every limit, so the ring sweeps up the way a real refresh does.
    var usageProgress: Double
    /// Squashes the cursor slightly at the moment of a click.
    var clickPulse: Double
}

/// The script. Times are seconds; the renderer samples this per frame.
enum Timeline {

    static let fps = 24
    static let duration = 13.0
    static var frameCount: Int { Int(duration * Double(fps)) }

    // Stage and laptop geometry. Every position below is derived from these
    // so the scene stays consistent if the stage is resized.
    static let stage = CGSize(width: 1280, height: 820)
    static let lid = CGSize(width: 1100, height: 700)
    static let bezel: CGFloat = 11
    static let baseHeight: CGFloat = 16

    /// Top-left of the screen (inside the bezel), in stage coordinates.
    static var screenOrigin: CGPoint {
        let stackHeight = lid.height + baseHeight
        return CGPoint(
            x: (stage.width - lid.width) / 2 + bezel,
            y: (stage.height - stackHeight) / 2 + bezel)
    }
    static var screenSize: CGSize {
        CGSize(width: lid.width - bezel * 2, height: lid.height - bezel * 2)
    }

    static let menuBarHeight: CGFloat = 24
    static let panelSize = CGSize(width: 340, height: 500)

    /// Panel sits under the menu bar, tucked against the right edge — where a
    /// real menu bar dropdown lands.
    static var panelOrigin: CGPoint {
        CGPoint(
            x: screenOrigin.x + screenSize.width - panelSize.width - 14,
            y: screenOrigin.y + menuBarHeight + 4)
    }
    /// Offset of the panel within the desktop's own coordinate space.
    static var panelOffset: CGSize {
        CGSize(
            width: panelOrigin.x - screenOrigin.x,
            height: panelOrigin.y - screenOrigin.y)
    }

    /// Ration's menu bar item, roughly — left of wifi/battery/clock.
    static var trayItem: CGPoint {
        CGPoint(
            x: screenOrigin.x + screenSize.width - 147,
            y: screenOrigin.y + menuBarHeight / 2)
    }

    /// The tab bar is centred in the panel, so derive each tab from that.
    static var tabY: CGFloat { panelOrigin.y + 62 }
    private static var tabBarLeading: CGFloat { panelOrigin.x + 14 }
    static var usageTab: CGPoint { CGPoint(x: tabBarLeading + 40, y: tabY) }
    static var activityTab: CGPoint { CGPoint(x: tabBarLeading + 118, y: tabY) }
    static var trendsTab: CGPoint { CGPoint(x: tabBarLeading + 152, y: tabY) }
    static var detailTab: CGPoint { CGPoint(x: tabBarLeading + 224, y: tabY) }

    static var restingCursor: CGPoint {
        CGPoint(x: stage.width / 2 - 120, y: stage.height - 190)
    }

    static func state(at time: Double) -> SceneState {
        var state = SceneState(
            cursor: restingCursor,
            panelOpen: 0, tab: .usage, usageProgress: 0, clickPulse: 0)

        // 0.0–1.4  cursor travels to the menu bar item
        state.cursor = point(from: restingCursor, to: trayItem, t: ease(span(time, 0.2, 1.4)))

        // 1.4–1.6  click
        state.clickPulse = pulse(time, at: 1.45)

        // 1.5–2.1  panel springs open
        state.panelOpen = ease(span(time, 1.5, 2.1))

        // 1.6–4.2  the ring sweeps to its real value
        state.usageProgress = ease(span(time, 1.7, 4.2))

        // 4.6–5.2  cursor to the Activity tab, click at 5.2
        if time >= 4.4 {
            state.cursor = point(from: trayItem, to: activityTab, t: ease(span(time, 4.4, 5.2)))
        }
        if time >= 5.25 { state.tab = .activity }
        state.clickPulse = max(state.clickPulse, pulse(time, at: 5.25))

        // 8.0–8.7  cursor to Metrics, click at 8.7
        if time >= 8.0 {
            state.cursor = point(from: activityTab, to: trendsTab, t: ease(span(time, 8.0, 8.7)))
        }
        if time >= 8.75 { state.tab = .trends }
        state.clickPulse = max(state.clickPulse, pulse(time, at: 8.75))

        // 11.8–13.0  cursor drifts away, leaving the panel on screen
        if time >= 11.8 {
            state.cursor = point(
                from: trendsTab,
                to: CGPoint(x: trendsTab.x - 190, y: trendsTab.y + 250),
                t: ease(span(time, 11.8, 13.0)))
        }

        return state
    }

    /// Metrics assemble as history accumulates — 1 day per frame or so.
    static func metricsDays(at time: Double) -> Int {
        max(2, Int(ease(span(time, 8.8, 11.6)) * 90))
    }

    // MARK: Curves

    /// Normalised progress through a window, clamped outside it.
    private static func span(_ t: Double, _ start: Double, _ end: Double) -> Double {
        guard end > start else { return t >= end ? 1 : 0 }
        return min(max((t - start) / (end - start), 0), 1)
    }

    private static func ease(_ t: Double) -> Double {
        t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
    }

    private static func point(from: CGPoint, to: CGPoint, t: Double) -> CGPoint {
        CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t)
    }

    /// A brief spike around `at`, for the click squash.
    private static func pulse(_ t: Double, at moment: Double, width: Double = 0.16) -> Double {
        let d = abs(t - moment)
        return d > width ? 0 : cos(d / width * .pi / 2)
    }
}

// MARK: - Scene

/// The full stage: a MacBook, a desktop, the menu bar, the panel, a cursor.
struct MacBookScene: View {

    let state: SceneState
    let history: UsageHistory
    let metricsDays: Int

    var body: some View {
        ZStack {
            Backdrop()

            MacBook {
                Desktop {
                    ZStack(alignment: .topLeading) {
                        MenuBarStrip(usageProgress: state.usageProgress)

                        if state.panelOpen > 0.01 {
                            panel
                                .scaleEffect(
                                    0.94 + 0.06 * state.panelOpen, anchor: .topTrailing
                                )
                                .opacity(state.panelOpen)
                                .offset(
                                    x: Timeline.panelOffset.width,
                                    y: Timeline.panelOffset.height)
                        }
                    }
                }
            }

            Cursor(pulse: state.clickPulse)
                .position(state.cursor)
        }
        .frame(width: Timeline.stage.width, height: Timeline.stage.height)
    }

    @ViewBuilder
    private var panel: some View {
        DemoPanelChrome(tab: state.tab) {
            switch state.tab {
            case .usage:
                SweepingUsage(progress: state.usageProgress)
            case .activity:
                ActivityView(history: history, status: .ready)
            case .trends:
                TrendsView(history: truncated, status: .ready)
            case .breakdown:
                BreakdownView(history: truncated, status: .ready)
            }
        }
    }

    /// A snapshot mid-week and slightly over pace, so the projection card has
    /// something interesting to say in the demo.
    private var demoSnapshot: UsageSnapshot {
        UsageSnapshot(limits: [
            UsageLimit(
                kind: .weeklyAll, group: .weekly, percent: 52, severity: .normal,
                resetsAt: Date(timeIntervalSinceNow: 3 * 24 * 3600), isActive: true)
        ])
    }

    private var truncated: UsageHistory {
        let calendar = Calendar.current
        guard let cutoff = calendar.date(byAdding: .day, value: -metricsDays, to: Date()) else {
            return history
        }
        return UsageHistory(days: history.days.filter { $0.key >= cutoff })
    }
}

// MARK: - Stage furniture

/// The area outside the laptop.
private struct Backdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.07, green: 0.06, blue: 0.06),
                    Color(red: 0.15, green: 0.09, blue: 0.07),
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(
                colors: [Color(red: 0.85, green: 0.47, blue: 0.34).opacity(0.18), .clear],
                center: .center, startRadius: 20, endRadius: 520)
        }
    }
}

/// A stylised MacBook. Not a photo-real render — a clean silhouette reads
/// better at video sizes and keeps every frame cheap to draw.
private struct MacBook<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            // Lid
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.24), Color(white: 0.14)],
                            startPoint: .top, endPoint: .bottom))

                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color(white: 0.42), lineWidth: 1)

                content
                    .frame(
                        width: Timeline.screenSize.width, height: Timeline.screenSize.height,
                        alignment: .topLeading
                    )
                    // Clip so a dropdown can never spill past the bezel.
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                // The notch, which is most of what makes it read as a MacBook.
                VStack {
                    UnevenRoundedRectangle(
                        bottomLeadingRadius: 5, bottomTrailingRadius: 5, style: .continuous
                    )
                    .fill(Color(white: 0.16))
                    .frame(width: 108, height: 15)
                    Spacer()
                }
                .padding(.top, 11)
            }
            .frame(width: Timeline.lid.width, height: Timeline.lid.height)

            // Hinge and base, drawn as a shallow trapezoid.
            Base()
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.30), Color(white: 0.17)],
                        startPoint: .top, endPoint: .bottom)
                )
                .frame(width: Timeline.lid.width + 82, height: Timeline.baseHeight)
                .overlay(alignment: .top) {
                    Capsule()
                        .fill(Color(white: 0.10))
                        .frame(width: 92, height: 4)
                        .padding(.top, 1)
                }
        }
        .shadow(color: .black.opacity(0.55), radius: 34, y: 18)
    }
}

private struct Base: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let inset: CGFloat = 22
        path.move(to: CGPoint(x: rect.minX + inset, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Wallpaper behind the menu bar and panel.
private struct Desktop<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.09, blue: 0.13),
                    Color(red: 0.24, green: 0.14, blue: 0.12),
                    Color(red: 0.36, green: 0.19, blue: 0.14),
                ],
                startPoint: .top, endPoint: .bottom)
            content
        }
    }
}

/// The macOS menu bar, with Ration's item in it — including the new weekly bar.
private struct MenuBarStrip: View {
    let usageProgress: Double

    private var weekly: Double { 52 * usageProgress }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "apple.logo")
                Text("Finder").fontWeight(.semibold)
                Text("File")
                Text("Edit")
                Text("View")
            }
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.85))
            .padding(.leading, 12)

            Spacer()

            HStack(spacing: 12) {
                // Ration's item.
                HStack(spacing: 4) {
                    Image(systemName: "gauge.with.dots.needle.50percent")
                    Text("\(Int(50 * usageProgress))%")
                        .font(.system(size: 11))
                        .monospacedDigit()
                    TrayBar(fraction: weekly / 100)
                }
                .foregroundStyle(.white)

                Image(systemName: "wifi")
                Image(systemName: "battery.75percent")
                Text("22:31").monospacedDigit()
            }
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.85))
            .padding(.trailing, 12)
        }
        .frame(height: Timeline.menuBarHeight)
        .background(.black.opacity(0.34))
    }
}

/// The weekly bar as it appears in the menu bar, at video scale.
private struct TrayBar: View {
    let fraction: Double

    private var color: Color {
        switch fraction {
        case ..<0.8: Color(red: 0.894, green: 0.545, blue: 0.416)
        case ..<0.9: Color(red: 0.949, green: 0.706, blue: 0.235)
        default: Color(red: 0.949, green: 0.365, blue: 0.314)
        }
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(.white.opacity(0.3)).frame(width: 22, height: 4)
            Capsule().fill(color).frame(width: max(22 * fraction, 4), height: 4)
        }
        .frame(width: 22, height: 4)
    }
}

/// The macOS pointer, drawn rather than screenshotted so it stays crisp.
private struct Cursor: View {
    let pulse: Double

    var body: some View {
        ArrowShape()
            .fill(.white)
            .overlay(ArrowShape().stroke(.black.opacity(0.55), lineWidth: 1))
            .frame(width: 17, height: 25)
            .shadow(color: .black.opacity(0.4), radius: 3, y: 2)
            .scaleEffect(1 - 0.16 * pulse, anchor: .topLeading)
            .overlay {
                // A ring that flashes outward on click, so the interaction
                // reads even without a real click sound.
                if pulse > 0.02 {
                    Circle()
                        .strokeBorder(.white.opacity(0.5 * pulse), lineWidth: 2)
                        .frame(width: 10 + 26 * (1 - pulse), height: 10 + 26 * (1 - pulse))
                }
            }
    }
}

private struct ArrowShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 0, y: h * 0.78))
        path.addLine(to: CGPoint(x: w * 0.27, y: h * 0.60))
        path.addLine(to: CGPoint(x: w * 0.45, y: h))
        path.addLine(to: CGPoint(x: w * 0.66, y: h * 0.92))
        path.addLine(to: CGPoint(x: w * 0.48, y: h * 0.54))
        path.addLine(to: CGPoint(x: w * 0.80, y: h * 0.52))
        path.closeSubpath()
        return path
    }
}

// MARK: - Panel pieces

/// Panel chrome without interactive state, since a frame sequence has no
/// clicks to respond to.
struct DemoPanelChrome<Content: View>: View {
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

            StaticTabs(selection: tab)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)

            Divider()
            content
            Spacer(minLength: 0)
        }
        .frame(
            width: Timeline.panelSize.width, height: Timeline.panelSize.height,
            alignment: .top
        )
        .background(
            Color(red: 0.13, green: 0.12, blue: 0.12),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.10), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
        .environment(\.colorScheme, .dark)
    }
}

private struct StaticTabs: View {
    let selection: PanelTab

    var body: some View {
        HStack(spacing: 2) {
            ForEach(PanelTab.allCases) { tab in
                Text(tab.title)
                    .font(.caption)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .foregroundStyle(selection == tab ? Color.primary : .secondary)
                    .background {
                        if selection == tab {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(.primary.opacity(0.10))
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

/// The Usage tab mid-sweep. `progress` scales every limit together.
struct SweepingUsage: View {
    let progress: Double

    private var limits: [UsageLimit] {
        [
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
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                RingGauge(percent: limits[0].percent, severity: .normal)
                VStack(spacing: 3) {
                    Text("Session").font(.subheadline.weight(.semibold))
                    Text("resets in 1h 5m")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.top, 18)
            .padding(.bottom, 16)

            VStack(spacing: 2) {
                ForEach(limits.dropFirst()) { limit in
                    LimitRowView(limit: limit, now: Date())
                }
            }
            .padding(.horizontal, 6)
        }
    }
}
