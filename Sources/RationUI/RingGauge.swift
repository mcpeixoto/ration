import RationKit
import SwiftUI

/// The headline ring.
///
/// Drawn with real vector strokes at final size rather than by scaling up
/// SwiftUI's `.accessoryCircularCapacity` gauge, which is laid out for a 58pt
/// complication and turns blurry the moment you enlarge it.
struct RingGauge: View {

    let percent: Double
    let severity: Severity

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.rationAnimatesEntrance) private var animatesEntrance

    /// `nil` until the view decides how to present itself, so a context that
    /// never runs `onAppear` — an `ImageRenderer` snapshot, say — still draws
    /// the true value instead of an empty ring.
    @State private var displayed: Double?

    private let lineWidth: CGFloat = 11

    var body: some View {
        ZStack {
            track
            progress
            readout
        }
        .frame(width: Theme.ringSize, height: Theme.ringSize)
        .onAppear {
            guard animatesEntrance, !reduceMotion else {
                displayed = clamped
                return
            }
            displayed = 0
            withAnimation(.smooth(duration: 0.9, extraBounce: 0.1)) {
                displayed = clamped
            }
        }
        .onChange(of: percent) { _, _ in
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.5)) {
                displayed = clamped
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityValue("\(MenuBarPresentation.percentText(percent)) used")
    }

    private var clamped: Double { min(max(percent, 0), 100) }
    private var shown: Double { displayed ?? clamped }

    private var track: some View {
        Circle()
            .stroke(Theme.track, lineWidth: lineWidth)
    }

    private var progress: some View {
        Circle()
            .trim(from: 0, to: shown / 100)
            .stroke(
                AngularGradient(
                    colors: [tint.opacity(0.7), tint, tint],
                    center: .center,
                    startAngle: .degrees(-90),
                    endAngle: .degrees(270)
                ),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            // Start the sweep at twelve o'clock rather than three.
            .rotationEffect(.degrees(-90))
    }

    private var tint: Color {
        severity.accentColor
    }

    /// The number and its unit are one text run, so the `%` tracks the digits
    /// instead of drifting away from them as the value changes width.
    ///
    /// Deliberately *not* `.contentTransition(.numericText())`. That effect
    /// rasterizes the text into per-digit layers, which reads as soft on a
    /// non-Retina display — and it is redundant here, because `shown` is
    /// already an animated value, so the digits count up on their own.
    private var readout: some View {
        (Text("\(Int(shown.rounded(.down)))")
            .font(.system(size: 33, weight: .semibold, design: .rounded))
            + Text("%")
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .foregroundColor(.secondary))
            .monospacedDigit()
            .foregroundStyle(.primary)
            .lineLimit(1)
    }
}

// MARK: - Bar

/// The capsule bar used for every limit below the ring.
///
/// Hand-drawn rather than `ProgressView(.linear)` so it can share the ring's
/// rounded caps, tint, and animation timing.
struct LimitBar: View {

    let percent: Double
    let severity: Severity

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.rationAnimatesEntrance) private var animatesEntrance
    /// See `RingGauge.displayed` for why this starts as `nil`.
    @State private var displayed: Double?

    private let height: CGFloat = 6

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.track)

                Capsule()
                    .fill(severity.accentColor.gradient)
                    .frame(
                        width: max(
                            geometry.size.width * shown / 100, shown > 0 ? height : 0))
            }
        }
        .frame(height: height)
        .onAppear {
            guard animatesEntrance, !reduceMotion else {
                displayed = clamped
                return
            }
            displayed = 0
            withAnimation(.smooth(duration: 0.7)) { displayed = clamped }
        }
        .onChange(of: percent) { _, _ in
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.45)) { displayed = clamped }
        }
    }

    private var clamped: Double { min(max(percent, 0), 100) }
    private var shown: Double { displayed ?? clamped }
}
