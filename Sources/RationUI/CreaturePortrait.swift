import RationKit
import SwiftUI

/// The illustration in a card's art window.
///
/// Twenty-six archetypes, one per `CreatureArt`, drawn in code and animated on
/// their own loops — the scene from the set's design, tuned per creature by
/// `CreatureArtParams`. Colour is the creature's energy; nothing here knows
/// about rarity.
struct CreaturePortrait: View {
    let creature: Creature
    var caught: Bool = true
    var shiny: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.rationArtTime) private var artTime
    private var store = CreatureArtStore.shared

    init(creature: Creature, caught: Bool = true, shiny: Bool = false) {
        self.creature = creature
        self.caught = caught
        self.shiny = shiny
    }

    var body: some View {
        GeometryReader { geo in
            let _ = store.generation
            ZStack {
                // A redrawn portrait is a fixed image, so it cannot take the shiny
                // colourway — fall back to the drawn scene, which can.
                if caught, !shiny, let custom = store.image(for: creature.id) {
                    Image(nsImage: custom)
                        .resizable()
                        .scaledToFill()
                } else {
                    ArtScene(
                        kind: creature.lore.art,
                        params: creature.artParams,
                        key: key,
                        animates: caught && !reduceMotion,
                        fixedTime: artTime)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .opacity(caught ? 1 : 0.4)
            .saturation(caught ? 1 : 0)
        }
        .accessibilityHidden(true)
    }

    private var key: Color {
        caught ? creature.lore.energy.keyColor(shiny: shiny) : Color.primary.opacity(0.5)
    }
}

// MARK: - Scene

private struct ArtScene: View {
    let kind: CreatureArt
    let params: CreatureArtParams
    let key: Color
    let animates: Bool
    /// When set, the scene is drawn at this instant instead of following the
    /// display link — the video renderer's way of staying deterministic.
    let fixedTime: Double?

    var body: some View {
        if let fixedTime {
            GeometryReader { geo in
                Frame(kind: kind, params: params, key: key, size: geo.size, t: fixedTime)
            }
        } else {
            TimelineView(
                .animation(minimumInterval: animates ? 1 / 30 : 3600, paused: !animates)
            ) { context in
                GeometryReader { geo in
                    Frame(
                        kind: kind, params: params, key: key, size: geo.size,
                        t: animates ? context.date.timeIntervalSinceReferenceDate : 0)
                }
            }
        }
    }
}

/// One drawn frame. Split out so the timeline only re-runs this body.
private struct Frame: View {
    let kind: CreatureArt
    let params: CreatureArtParams
    let key: Color
    let size: CGSize
    let t: Double

    var body: some View {
        ZStack {
            switch kind {
            case .flame: flame
            case .orbit: orbit
            case .gauge: gauge
            case .wings: wings
            case .wisp: wisp
            case .grid: grid
            case .window: window
            case .spiral: spiral
            case .slabs: slabs
            case .prism: prism
            case .chain: chain
            case .comet: comet
            case .bars: bars
            case .braid: braid
            case .moon: moon
            case .cluster: cluster
            case .wall: wall
            case .vortex: vortex
            case .shards: shards
            case .eye: eye
            case .lattice: lattice
            case .wave: wave
            case .pillars: pillars
            case .droplet: droplet
            case .hourglass: hourglass
            case .steps: steps
            }
        }
        .frame(width: size.width, height: size.height)
    }

    // MARK: Geometry helpers

    private var w: CGFloat { size.width }
    private var h: CGFloat { size.height }
    /// A share of the frame's width. Sizes in the design are width-relative.
    private func x(_ f: CGFloat) -> CGFloat { f * w }
    private func y(_ f: CGFloat) -> CGFloat { f * h }
    private var unit: CGFloat { min(w, h) }

    private var ground: Color { Color(red: 0.09, green: 0.075, blue: 0.067) }
    private func k(_ opacity: Double) -> Color { key.opacity(opacity) }

    private var down: LinearGradient {
        LinearGradient(
            colors: [key, Color.white.opacity(0.05)], startPoint: .top, endPoint: .bottom)
    }

    // MARK: Flame — the body flickers while embers rise out of frame

    private var flame: some View {
        let s = params.speed ?? 2.2
        return ZStack {
            Blob(topRX: 0.5, topRY: 0.62, bottomRX: 0.42, bottomRY: 0.38)
                .fill(down)
                .frame(width: x(0.34), height: y(0.54))
                .scaleEffect(flick(s), anchor: .bottom)
                .blur(radius: unit * 0.006)
                .position(x: x(0.5), y: y(0.86) - y(0.27))

            Blob(topRX: 0.5, topRY: 0.60, bottomRX: 0.45, bottomRY: 0.40)
                .fill(Color(white: 0.98).opacity(0.82))
                .frame(width: x(0.16), height: y(0.30))
                .scaleEffect(flick(s * 0.66), anchor: .bottom)
                .position(x: x(0.5), y: y(0.83) - y(0.15))

            if params.twin {
                Blob(topRX: 0.5, topRY: 0.62, bottomRX: 0.42, bottomRY: 0.38)
                    .fill(k(0.7))
                    .frame(width: x(0.18), height: y(0.30))
                    .scaleEffect(flick(s * 1.35), anchor: .bottom)
                    .position(x: x(0.35), y: y(0.87) - y(0.15))
            }

            ForEach(0..<(params.sparks ?? 4), id: \.self) { i in
                let p = ph(t, 2.4 + Double(i) * 0.5, Double(i) * 0.45)
                Circle()
                    .fill(key)
                    .frame(width: x(0.05), height: x(0.05))
                    .scaleEffect(0.9 - 0.55 * CGFloat(p))
                    .opacity(rise(p))
                    .position(
                        x: x(0.245 + CGFloat(i) * 0.14),
                        y: y(0.70) + y(0.3 - 1.6 * CGFloat(p)))
            }
        }
    }

    /// The flame's squash and stretch, as authored: 1 → 1.14/0.9 → 0.95/1.05 → 1.
    private func flick(_ period: Double) -> CGSize {
        let p = ph(t, period)
        return CGSize(
            width: piecewise(p, [(0, 1), (0.45, 0.90), (0.7, 1.05), (1, 1)]),
            height: piecewise(p, [(0, 1), (0.45, 1.14), (0.7, 0.95), (1, 1)]))
    }

    private func rise(_ p: Double) -> Double {
        p < 0.25 ? p / 0.25 : max(0, 1 - (p - 0.25) / 0.75)
    }

    // MARK: Orbit — a breathing core, satellites that never re-align

    private var orbit: some View {
        let count = params.count ?? 4
        let s = params.speed ?? 7
        let box = CGRect(x: x(0.14), y: y(0.14), width: x(0.72), height: y(0.72))
        return ZStack {
            Circle()
                .fill(key)
                .frame(width: x(0.22), height: x(0.22))
                .shadow(color: k(0.6), radius: unit * 0.09)
                .scaleEffect(0.9 + 0.18 * CGFloat(osc(ph(t, 3.1))))
                .opacity(0.72 + 0.28 * osc(ph(t, 3.1)))
                .position(x: x(0.5), y: y(0.5))

            ForEach(0..<count, id: \.self) { i in
                let spin = ph(t, s + Double(i) * 1.7) * (i % 2 == 1 ? -360 : 360)
                let dot = x(0.09)
                Circle()
                    .fill(i % 2 == 1 ? Color.white.opacity(0.8) : key)
                    .frame(width: dot, height: dot)
                    .position(
                        x: box.midX,
                        y: box.minY + box.height * CGFloat(i) * 0.09 + dot / 2
                    )
                    .rotationEffect(.degrees(spin))
            }
        }
    }

    // MARK: Gauge — the ring sweeps, the needle swings and settles

    private var gauge: some View {
        let d = x(params.big ? 0.74 : 0.62)
        let line = d * 0.075
        let fill = params.fill ?? 0.62
        return ZStack {
            Circle()
                .strokeBorder(Color.white.opacity(0.12), lineWidth: line)
                .frame(width: d, height: d)

            Circle()
                .trim(from: 0, to: fill > 0.6 ? 0.5 : 0.25)
                .stroke(key, lineWidth: line)
                .frame(width: d - line, height: d - line)
                .rotationEffect(.degrees(-45 + ph(t, params.speed ?? 9) * 360))

            Capsule()
                .fill(Color.white.opacity(0.9))
                .frame(width: max(2, d * 0.035), height: d * 0.34)
                .offset(y: -d * 0.17)
                .rotationEffect(.degrees(-40 + 80 * osc(ph(t, 3.4))))

            Circle().fill(key).frame(width: d * 0.14, height: d * 0.14)
        }
        .position(x: x(0.5), y: y(0.5))
    }

    // MARK: Wings — opposing beats, the lamp glowing on the downbeat

    private var wings: some View {
        let s = params.speed ?? 1.5
        return ZStack {
            Circle()
                .fill(Color(red: 1, green: 0.965, blue: 0.925).opacity(0.9))
                .frame(width: x(0.13), height: x(0.13))
                .shadow(
                    color: Color(red: 1, green: 0.86, blue: 0.7).opacity(0.7), radius: unit * 0.1
                )
                .scaleEffect(0.9 + 0.18 * CGFloat(osc(ph(t, s * 2))))
                .position(x: x(0.795), y: y(0.245))

            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [key, Color.white.opacity(0.14)],
                        startPoint: .bottomLeading, endPoint: .topTrailing)
                )
                .frame(width: x(0.285), height: y(0.45))
                .scaleEffect(x: 1 - 0.58 * CGFloat(osc(ph(t, s))), anchor: .trailing)
                .rotationEffect(.degrees(-14), anchor: .trailing)
                .position(x: x(0.5) - x(0.1425), y: y(0.5))

            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [key, Color.white.opacity(0.14)],
                        startPoint: .bottomTrailing, endPoint: .topLeading)
                )
                .frame(width: x(0.285), height: y(0.45))
                .scaleEffect(x: 1 - 0.58 * CGFloat(osc(ph(t, s, s / 2))), anchor: .leading)
                .rotationEffect(.degrees(14), anchor: .leading)
                .position(x: x(0.5) + x(0.1425), y: y(0.5))

            Capsule()
                .fill(Color.white.opacity(0.72))
                .frame(width: x(0.056), height: y(0.48))
                .position(x: x(0.5), y: y(0.5))
        }
    }

    // MARK: Wisp — blurred bodies bobbing out of sync

    private var wisp: some View {
        let count = params.count ?? 3
        let base: CGFloat = params.small ? 0.20 : 0.30
        return ZStack {
            ForEach(0..<count, id: \.self) { i in
                let d = x(base - CGFloat(i) * 0.04)
                let bob = -0.07 + 0.14 * osc(ph(t, 2.6 + Double(i) * 0.8, Double(i) * 0.4))
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.white.opacity(0.85), key, .clear],
                            center: UnitPoint(x: 0.35, y: 0.3),
                            startRadius: 0, endRadius: d * 0.62)
                    )
                    .frame(width: d, height: d)
                    .blur(radius: unit * 0.012)
                    .opacity(0.9 - Double(i) * 0.15)
                    .position(
                        x: x(0.30 + (i % 2 == 1 ? 0.14 : -0.06)) + d / 2,
                        y: y(0.24 + CGFloat(i) * 0.15 + CGFloat(bob)) + d / 2)
            }
        }
    }

    // MARK: Grid — cells lighting in a scattered order

    private var grid: some View {
        let count = params.count ?? 16
        let cols = count > 16 ? 5 : 4
        let rows = (count + cols - 1) / cols
        let s = params.speed ?? 2.8
        let side = min(x(0.62), y(0.9))
        let gap = side * 0.05
        let cell = (side - gap * CGFloat(cols - 1)) / CGFloat(cols)
        return VStack(spacing: gap) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: gap) {
                    ForEach(0..<cols, id: \.self) { col in
                        let i = row * cols + col
                        let delay = Double((i * 137) % 100) / 100 * s
                        RoundedRectangle(cornerRadius: cell * 0.14)
                            .fill(key)
                            .frame(width: cell, height: cell)
                            .scaleEffect(0.88 + 0.12 * CGFloat(osc(ph(t, s, delay))))
                            .opacity(i < count ? 0.22 + 0.78 * osc(ph(t, s, delay)) : 0)
                    }
                }
            }
        }
        .position(x: x(0.5), y: y(0.5))
    }

    // MARK: Window — the frame breathes, the status dot pulses

    private var window: some View {
        let bw = x(0.64)
        let bh = y(0.62)
        let radius = bw * 0.05
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: radius).fill(Color.white.opacity(0.06))
            Rectangle().fill(k(0.45)).frame(height: bh * 0.26)
            Circle()
                .fill(Color.white.opacity(0.85))
                .frame(width: bw * 0.08, height: bw * 0.08)
                .offset(x: bw * 0.06, y: bh * 0.07)
            Circle()
                .strokeBorder(Color.white.opacity(0.75), lineWidth: max(1.5, bw * 0.014))
                .frame(width: bw * 0.30, height: bw * 0.30)
                .scaleEffect(0.88 + 0.12 * CGFloat(osc(ph(t, 2.4))))
                .opacity(0.22 + 0.78 * osc(ph(t, 2.4)))
                .offset(x: bw * 0.35, y: bh * 0.52)
        }
        .frame(width: bw, height: bh)
        .clipShape(RoundedRectangle(cornerRadius: radius))
        .overlay {
            RoundedRectangle(cornerRadius: radius)
                .strokeBorder(key, lineWidth: max(1.5, bw * 0.016))
        }
        .scaleEffect(0.9 + 0.18 * CGFloat(osc(ph(t, 3.6))))
        .position(x: x(0.5), y: y(0.5))
    }

    // MARK: Spiral — nested rings turning against each other

    private var spiral: some View {
        let rings = params.rings ?? 4
        let s = params.speed ?? 7
        return ZStack {
            ForEach(0..<rings, id: \.self) { i in
                let d = min(x(0.26 + CGFloat(i) * 0.14), y(0.95))
                Circle()
                    .strokeBorder(
                        key,
                        style: StrokeStyle(
                            lineWidth: max(1.5, unit * 0.018),
                            dash: [unit * 0.05, unit * 0.05])
                    )
                    .frame(width: d, height: d)
                    .opacity(1 - Double(i) * 0.16)
                    .rotationEffect(
                        .degrees(ph(t, s + Double(i) * 3) * (i % 2 == 1 ? -360 : 360)))
            }
        }
        .position(x: x(0.5), y: y(0.5))
    }

    // MARK: Slabs — stacked layers sliding past each other

    private var slabs: some View {
        let count = params.count ?? 4
        let s = params.speed ?? 4
        return ZStack {
            ForEach(0..<count, id: \.self) { i in
                let slide = -0.09 + 0.18 * osc(ph(t, s + Double(i) * 0.6, Double(i) * 0.25))
                RoundedRectangle(cornerRadius: unit * 0.03)
                    .fill(i == 0 ? key : k(Double(72 - i * 12) / 100))
                    .frame(width: x(0.52 - CGFloat(i) * 0.06), height: y(0.13))
                    .shadow(color: .black.opacity(0.4), radius: unit * 0.03, y: unit * 0.01)
                    .position(
                        x: x(0.5) + x(CGFloat(slide)) * 0.5,
                        y: y(0.645 - CGFloat(i) * 0.11))
            }
        }
    }

    // MARK: Prism — a turning body, split light fanning out

    private var prism: some View {
        let bands: [Color] = [
            Color(red: 1.0, green: 0.616, blue: 0.431),
            Color(red: 0.561, green: 0.780, blue: 1.0),
            Color(red: 0.557, green: 0.878, blue: 0.659),
            Color(red: 0.835, green: 0.659, blue: 1.0),
        ]
        return ZStack {
            Triangle()
                .fill(
                    LinearGradient(
                        colors: [key, Color.white.opacity(0.5)],
                        startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .frame(width: x(0.40), height: x(0.40))
                .rotationEffect(.degrees(ph(t, 16) * 360))
                .position(x: x(0.5), y: y(0.5))

            ForEach(0..<(params.fan ? 4 : 3), id: \.self) { i in
                let p = ph(t, 2 + Double(i) * 0.6, Double(i) * 0.3)
                Capsule()
                    .fill(bands[i])
                    .frame(width: x(0.26), height: y(0.05))
                    .opacity(0.75 * (0.2 + 0.8 * osc(p)))
                    .scaleEffect(0.65 + 0.53 * CGFloat(osc(p)))
                    .position(x: x(0.77), y: y(0.325 + CGFloat(i) * 0.12))
            }
        }
    }

    // MARK: Chain — still links, a highlight sliding down them

    private var chain: some View {
        let count = params.count ?? 5
        let s = params.speed ?? 3.6
        let d = x(0.17)
        return HStack(spacing: -x(0.04)) {
            ForEach(0..<count, id: \.self) { i in
                let p = ph(t, s, Double(i) * (s / Double(count)))
                Circle()
                    .strokeBorder(key, lineWidth: max(2, d * 0.18))
                    .frame(width: d, height: d)
                    .scaleEffect(0.88 + 0.12 * CGFloat(osc(p)))
                    .opacity(0.22 + 0.78 * osc(p))
            }
        }
        .position(x: x(0.5), y: y(0.5))
    }

    // MARK: Comet — head and tail streaking across, then resetting

    private var comet: some View {
        let p = ph(t, params.speed ?? 3.2)
        let head = x(0.06)
        return ZStack {
            HStack(spacing: -head * 0.15) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.clear, key], startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(width: x(0.34), height: max(2, head * 0.25))
                Circle()
                    .fill(Color(white: 0.98))
                    .frame(width: head, height: head)
                    .shadow(color: key, radius: unit * 0.07)
            }
            .opacity(streak(p))
            .position(
                x: x(0.30) + x(-1.5 + 3 * CGFloat(p)),
                y: y(0.38) + y(0.55 - 1.1 * CGFloat(p)))

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.35), .clear],
                        startPoint: .leading, endPoint: .trailing)
                )
                .frame(width: x(0.76), height: 1)
                .position(x: x(0.5), y: y(0.82))
        }
    }

    private func streak(_ p: Double) -> Double {
        if p < 0.18 { return p / 0.18 }
        if p > 0.82 { return max(0, (1 - p) / 0.18) }
        return 1
    }

    // MARK: Bars — staggered growth, tallest last

    private var bars: some View {
        let count = params.count ?? 7
        let s = params.speed ?? 3
        let heights: [CGFloat] = [0.42, 0.62, 0.5, 0.9, 0.7, 0.34, 0.56, 0.78, 0.46]
        let width = x(0.68)
        let gap = width * 0.04
        let bar = (width - gap * CGFloat(count - 1)) / CGFloat(count)
        return HStack(alignment: .bottom, spacing: gap) {
            ForEach(0..<count, id: \.self) { i in
                RoundedRectangle(cornerRadius: bar * 0.2)
                    .fill(
                        LinearGradient(colors: [key, k(0.3)], startPoint: .top, endPoint: .bottom)
                    )
                    .frame(width: bar, height: y(0.58) * heights[i % heights.count])
                    .scaleEffect(
                        y: 0.42 + 0.58 * CGFloat(osc(ph(t, s, Double(i) * 0.14))), anchor: .bottom)
            }
        }
        .frame(height: y(0.58), alignment: .bottom)
        .position(x: x(0.5), y: y(0.5))
    }

    // MARK: Braid — two strands crossing, the whole thing bobbing

    private var braid: some View {
        let s = params.speed ?? 4
        let bob = -0.07 + 0.14 * osc(ph(t, s))
        return ZStack {
            BraidStrand(mirrored: false)
                .stroke(key, lineWidth: max(2, unit * 0.026))
            BraidStrand(mirrored: true)
                .stroke(Color.white.opacity(0.8), lineWidth: max(2, unit * 0.026))
            Capsule()
                .fill(k(0.55))
                .frame(width: x(0.44), height: y(0.08))
                .scaleEffect(0.88 + 0.12 * CGFloat(osc(ph(t, 2.6))))
                .opacity(0.22 + 0.78 * osc(ph(t, 2.6)))
                .offset(y: y(0.64) * -0.04)
        }
        .frame(width: x(0.38), height: y(0.64))
        .position(x: x(0.5), y: y(0.5) + y(CGFloat(bob)))
    }

    // MARK: Moon — a drifting crescent under uneven stars

    private var moon: some View {
        let d = x(0.44)
        let bob = -0.07 + 0.14 * osc(ph(t, 6))
        let stars: [(CGFloat, CGFloat)] = [(0.22, 0.18), (0.74, 0.30), (0.16, 0.62), (0.68, 0.74)]
        return ZStack {
            ZStack(alignment: .topLeading) {
                Circle().fill(key)
                Circle()
                    .fill(ground)
                    .frame(width: d * 0.96, height: d * 1.28)
                    .offset(x: d * 0.26, y: -d * 0.14)
            }
            .frame(width: d, height: d)
            .clipShape(Circle())
            .shadow(color: k(0.55), radius: unit * 0.12)
            .position(x: x(0.5), y: y(0.5) + y(CGFloat(bob)))

            ForEach(0..<stars.count, id: \.self) { i in
                let p = ph(t, 1.8 + Double(i) * 0.7, Double(i) * 0.4)
                let sd = x(0.03 + CGFloat(i % 2) * 0.02)
                Circle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: sd, height: sd)
                    .scaleEffect(0.65 + 0.53 * CGFloat(osc(p)))
                    .opacity(0.2 + 0.8 * osc(p))
                    .position(x: x(stars[i].0), y: y(stars[i].1))
            }

            if params.lantern {
                RoundedRectangle(cornerRadius: unit * 0.03)
                    .fill(Color(red: 1, green: 0.86, blue: 0.67).opacity(0.35))
                    .overlay {
                        RoundedRectangle(cornerRadius: unit * 0.03)
                            .strokeBorder(key, lineWidth: max(1.5, unit * 0.016))
                    }
                    .frame(width: x(0.16), height: y(0.20))
                    .scaleEffect(0.88 + 0.12 * CGFloat(osc(ph(t, 3))))
                    .opacity(0.22 + 0.78 * osc(ph(t, 3)))
                    .position(x: x(0.5), y: y(0.80))
            }
        }
    }

    // MARK: Cluster — nodes twinkling in rotation, never all lit

    private var cluster: some View {
        let count = params.count ?? 6
        let radius: CGFloat = params.big ? 0.30 : 0.26
        let d = x(params.big ? 0.13 : 0.10)
        return ZStack {
            Circle()
                .strokeBorder(
                    Color.white.opacity(0.28),
                    style: StrokeStyle(lineWidth: 1, dash: [unit * 0.04, unit * 0.04])
                )
                .frame(width: x(0.40), height: x(0.40))
                .rotationEffect(.degrees(ph(t, 22) * 360))
                .position(x: x(0.5), y: y(0.5))

            ForEach(0..<count, id: \.self) { i in
                let angle = Double(i) / Double(count) * 2 * .pi
                let p = ph(t, 2 + Double(i % 4) * 0.55, Double(i) * 0.25)
                Group {
                    if i % 3 == 1 {
                        RoundedRectangle(cornerRadius: d * 0.2).fill(key)
                    } else {
                        Circle().fill(i % 3 == 2 ? Color.white.opacity(0.85) : key)
                    }
                }
                .frame(width: d, height: d)
                .scaleEffect(0.65 + 0.53 * CGFloat(osc(p)))
                .opacity(0.2 + 0.8 * osc(p))
                .position(
                    x: x(0.5) + x(radius) * CGFloat(cos(angle)),
                    y: y(0.5) + x(radius) * CGFloat(sin(angle)))
            }
        }
    }

    // MARK: Wall — courses jittering, one brick running hot

    private var wall: some View {
        let rows = params.rows ?? 3
        let width = x(0.66)
        let height = y(0.62)
        let gap = height * 0.05
        let rowHeight = (height - gap * CGFloat(rows - 1)) / CGFloat(rows)
        let jitter = shake(ph(t, 2.6))
        return VStack(spacing: gap) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: width * 0.04) {
                    ForEach(0..<4, id: \.self) { col in
                        let hot = row == 1 && col == 2
                        RoundedRectangle(cornerRadius: rowHeight * 0.12)
                            .fill(hot ? key : k(0.34))
                            .overlay {
                                RoundedRectangle(cornerRadius: rowHeight * 0.12)
                                    .strokeBorder(k(0.55), lineWidth: 1)
                            }
                            .frame(height: rowHeight)
                            .opacity(hot ? 0.22 + 0.78 * osc(ph(t, 1.8)) : 1)
                    }
                }
                .padding(.leading, row % 2 == 1 ? width * 0.09 : 0)
            }
        }
        .frame(width: width, height: height)
        .position(
            x: x(0.5) + jitter.width * unit * 0.006,
            y: y(0.5) + jitter.height * unit * 0.006)
    }

    private func shake(_ p: Double) -> CGSize {
        CGSize(
            width: piecewise(p, [(0, 0), (0.2, -1.5), (0.6, 1.5), (1, 0)]),
            height: piecewise(p, [(0, 0), (0.2, 1), (0.6, -1), (1, 0)]))
    }

    // MARK: Vortex — counter-rotating rings around a pulsing core

    private var vortex: some View {
        let rings = params.rings ?? 5
        let s = params.speed ?? 9
        let gold = Color(red: 1, green: 0.882, blue: 0.667)
        let line = max(2, unit * 0.026)
        return ZStack {
            ForEach(0..<rings, id: \.self) { i in
                let d = min(x(0.22 + CGFloat(i) * 0.13), y(0.95))
                let spin = ph(t, max(1, s - Double(i) * 0.9)) * (i % 2 == 1 ? -360 : 360)
                ZStack {
                    Circle()
                        .trim(from: 0.875, to: 1)
                        .stroke(
                            params.gold && i % 2 == 1 ? gold.opacity(0.9) : key,
                            style: StrokeStyle(lineWidth: line, lineCap: .round))
                    Circle()
                        .trim(from: 0, to: 0.125)
                        .stroke(
                            params.gold && i % 2 == 1 ? gold.opacity(0.9) : key,
                            style: StrokeStyle(lineWidth: line, lineCap: .round))
                    Circle()
                        .trim(from: 0.5, to: 0.75)
                        .stroke(k(0.35), style: StrokeStyle(lineWidth: line))
                }
                .frame(width: d, height: d)
                .rotationEffect(.degrees(spin))
            }

            Circle()
                .fill(Color(white: 0.98))
                .frame(width: x(0.13), height: x(0.13))
                .shadow(color: key, radius: unit * 0.11)
                .scaleEffect(0.9 + 0.18 * CGFloat(osc(ph(t, 2.4))))
        }
        .position(x: x(0.5), y: y(0.5))
    }

    // MARK: Shards — fragments drifting on independent paths

    private var shards: some View {
        let count = params.count ?? 5
        let spots: [(CGFloat, CGFloat)] = [
            (0.16, 0.22), (0.62, 0.16), (0.30, 0.58), (0.70, 0.60), (0.44, 0.34),
            (0.10, 0.62), (0.80, 0.36),
        ]
        return ZStack {
            ForEach(0..<count, id: \.self) { i in
                let spot = spots[i % spots.count]
                let d = x((params.big ? 0.20 : 0.16) - CGFloat(i % 3) * 0.03)
                let motion = drift(ph(t, 5 + Double(i) * 1.1, Double(i) * 0.35))
                Group {
                    if i % 3 == 0 {
                        Triangle().fill(shardFill(i))
                    } else {
                        Diamond().fill(shardFill(i))
                    }
                }
                .frame(width: d, height: d)
                .rotationEffect(.degrees(Double(i) * 24 - 30 + motion.angle))
                .position(
                    x: x(spot.0) + d / 2 + x(CGFloat(motion.dx)),
                    y: y(spot.1) + d / 2 + y(CGFloat(motion.dy)))
            }
        }
    }

    private func shardFill(_ i: Int) -> AnyShapeStyle {
        i % 2 == 1
            ? AnyShapeStyle(
                LinearGradient(
                    colors: [key, Color.white.opacity(0.35)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
            : AnyShapeStyle(k(0.6))
    }

    private func drift(_ p: Double) -> (dx: Double, dy: Double, angle: Double) {
        (
            piecewise(p, [(0, 0), (0.33, 0.07), (0.66, -0.06), (1, 0)]),
            piecewise(p, [(0, 0), (0.33, -0.06), (0.66, 0.05), (1, 0)]),
            piecewise(p, [(0, 0), (0.33, 10), (0.66, -10), (1, 0)])
        )
    }

    // MARK: Eye — the iris scans, the lid glow pulses behind it

    private var eye: some View {
        let ew = x(0.66)
        let eh = y(0.56)
        return Ellipse()
            .fill(
                params.night
                    ? Color(red: 0.31, green: 0.35, blue: 0.71).opacity(0.16)
                    : Color.white.opacity(0.05)
            )
            .overlay {
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [k(0.4), .clear],
                            center: .center, startRadius: 0, endRadius: ew * 0.5)
                    )
                    .scaleEffect(0.88 + 0.12 * CGFloat(osc(ph(t, 3.2))))
                    .opacity(0.22 + 0.78 * osc(ph(t, 3.2)))
            }
            .overlay {
                Circle()
                    .fill(key)
                    .frame(width: ew * 0.26, height: ew * 0.26)
                    .overlay {
                        Circle()
                            .fill(Color(red: 0.08, green: 0.07, blue: 0.06))
                            .frame(width: ew * 0.11, height: ew * 0.11)
                    }
                    .offset(x: ew * 0.5 * CGFloat(-0.3 + 0.6 * osc(ph(t, 4.6))))
            }
            .clipShape(Ellipse())
            .overlay {
                Ellipse().strokeBorder(key, lineWidth: max(2, unit * 0.022))
            }
            .frame(width: ew, height: eh)
            .position(x: x(0.5), y: y(0.5))
    }

    // MARK: Lattice — a mesh scrolling under a fixed glow

    private var lattice: some View {
        let step = unit * (params.dense ? 0.09 : 0.13)
        let offset = CGFloat(ph(t, 3.4)) * step
        return ZStack {
            DiagonalMesh(step: step, offset: offset, mirrored: false)
                .stroke(k(0.7), lineWidth: 1)
            DiagonalMesh(step: step, offset: offset, mirrored: true)
                .stroke(k(0.45), lineWidth: 1)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.9), .clear],
                        center: .center, startRadius: 0, endRadius: x(0.13))
                )
                .frame(width: x(0.26), height: x(0.26))
                .scaleEffect(0.9 + 0.18 * CGFloat(osc(ph(t, 3.6))))
                .position(x: x(0.5), y: y(0.5))
        }
        .opacity(0.85)
    }

    // MARK: Wave — a phase offset that reads as a travelling swell

    private var wave: some View {
        let count = params.count ?? 9
        let width = x(0.74)
        let gap = width * 0.03
        let bar = (width - gap * CGFloat(count - 1)) / CGFloat(count)
        let band = y(0.46)
        return HStack(spacing: gap) {
            ForEach(0..<count, id: \.self) { i in
                let p = ph(t, 2.4, Double(i) * 0.12)
                Capsule()
                    .fill(
                        LinearGradient(colors: [key, k(0.25)], startPoint: .top, endPoint: .bottom)
                    )
                    .frame(width: bar, height: band * 0.58)
                    .scaleEffect(y: 0.8 + 0.35 * CGFloat(osc(p)))
                    .offset(y: band * CGFloat(0.2 - 0.4 * osc(p)))
            }
        }
        .frame(width: width, height: band)
        .position(x: x(0.5), y: y(0.5))
    }

    // MARK: Pillars — columns breathing left to right

    private var pillars: some View {
        let count = params.count ?? 6
        let width = x(0.68)
        let gap = width * 0.05
        let column = (width - gap * CGFloat(count - 1)) / CGFloat(count)
        return HStack(alignment: .bottom, spacing: gap) {
            ForEach(0..<count, id: \.self) { i in
                UnevenRoundedRectangle(
                    topLeadingRadius: column * 0.2, bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0, topTrailingRadius: column * 0.2
                )
                .fill(
                    LinearGradient(colors: [k(0.9), k(0.2)], startPoint: .top, endPoint: .bottom)
                )
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.white.opacity(0.7))
                        .frame(height: max(1.5, unit * 0.018))
                }
                .frame(width: column, height: y(0.56) * (0.52 + CGFloat(i % 3) * 0.18))
                .scaleEffect(
                    0.9 + 0.18 * CGFloat(osc(ph(t, 3.2 + Double(i % 3) * 0.5, Double(i) * 0.2))),
                    anchor: .bottom)
            }
        }
        .frame(height: y(0.56), alignment: .bottom)
        .position(x: x(0.5), y: y(0.5))
    }

    // MARK: Droplet — a swelling bead under expanding ripples

    private var droplet: some View {
        ZStack {
            ForEach(0..<2, id: \.self) { i in
                let p = ph(t, 3, Double(i) * 1.5)
                Circle()
                    .strokeBorder(key, lineWidth: max(1.5, unit * 0.018))
                    .frame(width: x(0.40), height: x(0.40))
                    .scaleEffect(0.35 + 1.35 * CGFloat(p))
                    .opacity(0.85 * (1 - p))
            }
            UnevenRoundedRectangle(
                topLeadingRadius: x(0.16), bottomLeadingRadius: x(0.02),
                bottomTrailingRadius: x(0.16), topTrailingRadius: x(0.16)
            )
            .fill(
                LinearGradient(
                    colors: [Color.white.opacity(0.85), key],
                    startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .frame(width: x(0.32), height: x(0.32))
            .rotationEffect(.degrees(45))
            .scaleEffect(0.9 + 0.18 * CGFloat(osc(ph(t, 3))))
        }
        .position(x: x(0.5), y: y(0.5))
    }

    // MARK: Hourglass — grains falling through a still frame

    private var hourglass: some View {
        let gw = x(0.40)
        let gh = y(0.66)
        return ZStack {
            VStack(spacing: 0) {
                TriangleDown()
                    .fill(
                        LinearGradient(colors: [key, k(0.25)], startPoint: .top, endPoint: .bottom))
                Triangle()
                    .fill(
                        LinearGradient(colors: [k(0.25), key], startPoint: .top, endPoint: .bottom))
            }
            .frame(width: gw, height: gh)

            ForEach(0..<2, id: \.self) { i in
                let p = ph(t, 1.9, Double(i) * 0.9)
                let d = gw * (i == 0 ? 0.05 : 0.04)
                Circle()
                    .fill(Color(white: 0.98).opacity(i == 0 ? 0.95 : 0.8))
                    .frame(width: d, height: d)
                    .opacity(fall(p))
                    .offset(y: gh * CGFloat(-0.35 + 0.7 * p))
            }
        }
        .position(x: x(0.5), y: y(0.5))
    }

    private func fall(_ p: Double) -> Double {
        if p < 0.2 { return p / 0.2 }
        if p > 0.9 { return max(0, (1 - p) / 0.1) }
        return 1
    }

    // MARK: Steps — a terrace lighting bottom to top

    private var steps: some View {
        let count = params.count ?? 5
        let width = x(0.66)
        let slot = width / CGFloat(count)
        let stepWidth = slot * 0.88
        return ZStack(alignment: .bottomLeading) {
            ForEach(0..<count, id: \.self) { i in
                let p = ph(t, 3, Double(i) * 0.28)
                UnevenRoundedRectangle(
                    topLeadingRadius: stepWidth * 0.1, bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0, topTrailingRadius: stepWidth * 0.1
                )
                .fill(k(Double(40 + i * 12) / 100))
                .overlay(alignment: .top) {
                    Rectangle().fill(key).frame(height: max(1.5, unit * 0.018))
                }
                .frame(width: stepWidth, height: y(0.62) * (0.24 + CGFloat(i) * 0.19))
                .scaleEffect(0.88 + 0.12 * CGFloat(osc(p)), anchor: .bottom)
                .opacity(0.22 + 0.78 * osc(p))
                .offset(x: slot * CGFloat(i))
            }
        }
        .frame(width: width, height: y(0.62), alignment: .bottomLeading)
        .position(x: x(0.5), y: y(0.5))
    }
}

// MARK: - Motion

/// Where a loop of `period` seconds sits right now, 0…1.
private func ph(_ t: Double, _ period: Double, _ delay: Double = 0) -> Double {
    guard period > 0 else { return 0 }
    let x = (t - delay) / period
    return x - floor(x)
}

/// An ease-in-out swing from 0 to 1 and back, matching a CSS 0/50/100 loop.
private func osc(_ p: Double) -> Double {
    0.5 - 0.5 * cos(2 * .pi * p)
}

/// Linear interpolation through authored keyframe stops.
private func piecewise(_ p: Double, _ stops: [(Double, Double)]) -> Double {
    guard let first = stops.first else { return 0 }
    if p <= first.0 { return first.1 }
    for i in 1..<stops.count where p <= stops[i].0 {
        let span = stops[i].0 - stops[i - 1].0
        guard span > 0 else { return stops[i].1 }
        return stops[i - 1].1
            + (stops[i].1 - stops[i - 1].1) * (p - stops[i - 1].0) / span
    }
    return stops[stops.count - 1].1
}

// MARK: - Paths

/// A rectangle with per-edge corner radii given as fractions, the way the
/// design writes them (`50% 50% 42% 42% / 62% 62% 38% 38%`).
private struct Blob: Shape {
    var topRX: CGFloat
    var topRY: CGFloat
    var bottomRX: CGFloat
    var bottomRY: CGFloat

    func path(in rect: CGRect) -> Path {
        let c: CGFloat = 0.5523
        let trx = min(topRX * rect.width, rect.width / 2)
        let topY = topRY * rect.height
        let brx = min(bottomRX * rect.width, rect.width / 2)
        let bottomY = bottomRY * rect.height

        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + topY))
        p.addCurve(
            to: CGPoint(x: rect.minX + trx, y: rect.minY),
            control1: CGPoint(x: rect.minX, y: rect.minY + topY * (1 - c)),
            control2: CGPoint(x: rect.minX + trx * (1 - c), y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - trx, y: rect.minY))
        p.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + topY),
            control1: CGPoint(x: rect.maxX - trx * (1 - c), y: rect.minY),
            control2: CGPoint(x: rect.maxX, y: rect.minY + topY * (1 - c)))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomY))
        p.addCurve(
            to: CGPoint(x: rect.maxX - brx, y: rect.maxY),
            control1: CGPoint(x: rect.maxX, y: rect.maxY - bottomY * (1 - c)),
            control2: CGPoint(x: rect.maxX - brx * (1 - c), y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + brx, y: rect.maxY))
        p.addCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - bottomY),
            control1: CGPoint(x: rect.minX + brx * (1 - c), y: rect.maxY),
            control2: CGPoint(x: rect.minX, y: rect.maxY - bottomY * (1 - c)))
        p.closeSubpath()
        return p
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.closeSubpath()
        }
    }
}

private struct TriangleDown: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.closeSubpath()
        }
    }
}

private struct Diamond: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            p.closeSubpath()
        }
    }
}

/// One of the two 45° line families behind a lattice creature.
private struct DiagonalMesh: Shape {
    var step: CGFloat
    var offset: CGFloat
    var mirrored: Bool

    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard step > 0 else { return p }
        var x = -rect.height + offset.truncatingRemainder(dividingBy: step)
        while x < rect.width + rect.height {
            if mirrored {
                p.move(to: CGPoint(x: rect.maxX - x, y: rect.minY))
                p.addLine(to: CGPoint(x: rect.maxX - x - rect.height, y: rect.maxY))
            } else {
                p.move(to: CGPoint(x: rect.minX + x, y: rect.minY))
                p.addLine(to: CGPoint(x: rect.minX + x + rect.height, y: rect.maxY))
            }
            x += step
        }
        return p
    }
}

/// Half of a braid: a strand that crosses the middle and comes back.
private struct BraidStrand: Shape {
    var mirrored: Bool

    func path(in rect: CGRect) -> Path {
        let start = mirrored ? rect.maxX - rect.width * 0.22 : rect.minX + rect.width * 0.22
        let c1 = mirrored ? rect.minX : rect.maxX
        let c2 = mirrored ? rect.maxX : rect.minX
        return Path { p in
            p.move(to: CGPoint(x: start, y: rect.minY))
            p.addCurve(
                to: CGPoint(x: start, y: rect.maxY),
                control1: CGPoint(x: c1, y: rect.minY + rect.height * 0.33),
                control2: CGPoint(x: c2, y: rect.minY + rect.height * 0.66))
        }
    }
}

/// A slow float, for anything that should not sit perfectly still.
struct IdleBob: ViewModifier {
    var enabled: Bool
    var amplitude: CGFloat

    func body(content: Content) -> some View {
        TimelineView(.animation(minimumInterval: enabled ? 1 / 24 : 10, paused: !enabled)) {
            context in
            let t = context.date.timeIntervalSinceReferenceDate
            content.offset(y: enabled ? sin(t * 2.2) * amplitude : 0)
        }
    }
}
