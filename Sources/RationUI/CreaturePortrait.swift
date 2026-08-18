import RationKit
import SwiftUI

/// A small scene of the deed that unlocked this creature.
///
/// One picture per id, no shared face. At stamp size the *event* has to
/// read — a flame, a prompt, a needle — colour only confirms it.
struct CreaturePortrait: View {
    let creature: Creature
    var caught: Bool = true

    var body: some View {
        // Color.clear + aspectRatio gives the tile an intrinsic square. A bare
        // GeometryReader inside a grid cell reports no height, so the drawing
        // used to collapse to nothing.
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                GeometryReader { geo in
                    let s = min(geo.size.width, geo.size.height)
                    scene(s)
                        .foregroundStyle(
                            caught ? creature.rarity.color : Color.primary.opacity(0.28)
                        )
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func scene(_ s: CGFloat) -> some View {
        switch creature.id {
        case "sparkit": ember(s)
        case "promptail": prompt(s)
        case "gaugeling": needle(s, fill: 0.62)
        case "tokenoth": moth(s)
        case "cachewisp": wisp(s)
        case "heatmite": cell(s)
        case "sessiondrake": session(s)
        case "limitwyrm": coil(s)
        case "contextaur": context(s)
        case "modelith": shift(s)
        case "streakon": streak(s)
        case "burnrate": pace(s)
        case "weeklyrex": week(s)
        case "braidon": braid(s)
        case "nightshift": night(s)
        case "omnivore": trio(s)
        case "wallback": wall(s)
        default: needle(s, fill: 0.78)
        }
    }

    // MARK: Scenes

    /// First tokens: a flame catching.
    private func ember(_ s: CGFloat) -> some View {
        ZStack {
            EmberFlame()
                .frame(width: s * 0.42, height: s * 0.58)
            Circle()
                .frame(width: s * 0.16, height: s * 0.16)
                .offset(y: s * 0.28)
        }
    }

    /// 25 messages: a prompt bubble with a waiting cursor.
    private func prompt(_ s: CGFloat) -> some View {
        ZStack {
            PromptBubble()
                .frame(width: s * 0.62, height: s * 0.48)
            VStack(alignment: .leading, spacing: s * 0.05) {
                Capsule().frame(width: s * 0.28, height: s * 0.045)
                Capsule().frame(width: s * 0.18, height: s * 0.045)
            }
            .offset(x: -s * 0.04, y: -s * 0.04)
        }
    }

    /// The menu-bar ring, with a needle on the number.
    private func needle(_ s: CGFloat, fill: CGFloat) -> some View {
        let line = max(4, s * 0.09)
        return ZStack {
            Circle().stroke(.primary.opacity(0.18), lineWidth: line)
            Circle()
                .trim(from: 0, to: fill)
                .stroke(Color.primary, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Capsule()
                .frame(width: line * 0.55, height: s * 0.28)
                .offset(y: -s * 0.10)
                .rotationEffect(.degrees(Double(fill) * 360 - 90), anchor: .bottom)
                .offset(y: s * 0.02)
            Circle().frame(width: line, height: line)
        }
        .frame(width: s * 0.62, height: s * 0.62)
    }

    /// Tokens as a moth at a lamp.
    private func moth(_ s: CGFloat) -> some View {
        ZStack {
            Circle()
                .frame(width: s * 0.14, height: s * 0.14)
                .offset(x: s * 0.22, y: -s * 0.18)
            MothWings()
                .frame(width: s * 0.70, height: s * 0.48)
                .offset(x: -s * 0.04, y: s * 0.06)
        }
    }

    /// Cache: something almost not there.
    private func wisp(_ s: CGFloat) -> some View {
        ZStack {
            Circle().opacity(0.35).frame(width: s * 0.42, height: s * 0.42)
                .offset(y: -s * 0.12)
            Circle().opacity(0.55).frame(width: s * 0.32, height: s * 0.32)
            Circle().frame(width: s * 0.18, height: s * 0.18)
                .offset(y: s * 0.16)
        }
    }

    /// Five active days: a calendar, one cell lit.
    private func cell(_ s: CGFloat) -> some View {
        let w = s * 0.56
        let h = s * 0.50
        return ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 0)
                    .frame(height: h * 0.22)
                    .opacity(0.35)
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 4),
                    spacing: 2
                ) {
                    ForEach(0..<8, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1)
                            .opacity(i == 4 ? 1 : 0.28)
                            .frame(height: (h * 0.62) / 2 - 1)
                    }
                }
                .padding(4)
            }
        }
        .frame(width: w, height: h)
        .compositingGroup()
    }

    /// A session window opening.
    private func session(_ s: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
            Capsule()
                .frame(width: s * 0.10, height: s * 0.10)
                .padding(6)
            Circle()
                .stroke(Color.primary, lineWidth: 1.5)
                .frame(width: s * 0.22, height: s * 0.22)
                .overlay(alignment: .top) {
                    Capsule().frame(width: 1.5, height: s * 0.07)
                }
                .offset(x: s * 0.18, y: s * 0.16)
        }
        .frame(width: s * 0.62, height: s * 0.48)
    }

    /// Weekly cap: a coil around a ring you cannot leave.
    private func coil(_ s: CGFloat) -> some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.25), lineWidth: 3)
                .frame(width: s * 0.28, height: s * 0.28)
            CoilLine()
                .stroke(Color.primary, style: StrokeStyle(lineWidth: s * 0.07, lineCap: .round))
                .frame(width: s * 0.62, height: s * 0.62)
        }
    }

    /// Cached files, stacked.
    private func context(_ s: CGFloat) -> some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .frame(width: s * 0.42 - CGFloat(i) * 4, height: s * 0.32)
                    .offset(y: CGFloat(i) * s * -0.10)
                    .opacity(1 - Double(i) * 0.22)
            }
        }
    }

    /// Three models in the room at once.
    private func shift(_ s: CGFloat) -> some View {
        HStack(spacing: s * -0.08) {
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .frame(width: s * 0.22, height: s * 0.36 + CGFloat(i == 1 ? 8 : 0))
                    .opacity(0.55 + Double(i) * 0.2)
            }
        }
    }

    /// Five days in a row.
    private func streak(_ s: CGFloat) -> some View {
        let d = s * 0.12
        return ZStack {
            Capsule().frame(width: s * 0.64, height: 3).opacity(0.45)
            HStack(spacing: s * 0.05) {
                ForEach(0..<5, id: \.self) { _ in
                    Circle().frame(width: d, height: d)
                }
            }
        }
    }

    /// Pace running ahead of the projection.
    private func pace(_ s: CGFloat) -> some View {
        ZStack {
            PaceProjection()
                .stroke(
                    Color.primary.opacity(0.3),
                    style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
            PaceLine()
                .stroke(
                    Color.primary,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        }
        .frame(width: s * 0.70, height: s * 0.42)
    }

    /// Seven days; the weekly limit does not reset with the session.
    private func week(_ s: CGFloat) -> some View {
        WeekBars()
            .frame(width: s * 0.68, height: s * 0.42)
    }

    /// Two tools, one score.
    private func braid(_ s: CGFloat) -> some View {
        BraidLines()
            .stroke(Color.primary, style: StrokeStyle(lineWidth: s * 0.09, lineCap: .round))
            .frame(width: s * 0.36, height: s * 0.64)
    }

    /// Most of the work after 10pm.
    private func night(_ s: CGFloat) -> some View {
        ZStack {
            Image(systemName: "moon.fill")
                .font(.system(size: s * 0.42, weight: .regular))
            HStack(spacing: s * 0.06) {
                Image(systemName: "star.fill").font(.system(size: s * 0.10))
                Image(systemName: "star.fill").font(.system(size: s * 0.07))
            }
            .offset(x: s * 0.22, y: -s * 0.18)
        }
    }

    /// Claude, Codex, Cursor.
    private func trio(_ s: CGFloat) -> some View {
        HStack(spacing: s * 0.06) {
            Circle().frame(width: s * 0.18, height: s * 0.18)
            RoundedRectangle(cornerRadius: 3).frame(width: s * 0.18, height: s * 0.18)
            Diamond().frame(width: s * 0.16, height: s * 0.16)
        }
    }

    /// The cap you hit on a huge day.
    private func wall(_ s: CGFloat) -> some View {
        WallBricks()
            .frame(width: s * 0.64, height: s * 0.44)
    }
}

// MARK: - Paths

private struct EmberFlame: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.maxY * 0.70),
                control: CGPoint(x: rect.maxX, y: rect.height * 0.22))
            p.addQuadCurve(
                to: CGPoint(x: rect.midX, y: rect.maxY),
                control: CGPoint(x: rect.maxX * 0.78, y: rect.maxY))
            p.addQuadCurve(
                to: CGPoint(x: rect.minX, y: rect.maxY * 0.70),
                control: CGPoint(x: rect.minX + rect.width * 0.22, y: rect.maxY))
            p.addQuadCurve(
                to: CGPoint(x: rect.midX, y: rect.minY),
                control: CGPoint(x: rect.minX, y: rect.height * 0.22))
        }
    }
}

private struct PromptBubble: Shape {
    func path(in rect: CGRect) -> Path {
        let bubble = rect.insetBy(dx: 0, dy: rect.height * 0.08)
            .divided(atDistance: rect.height * 0.72, from: .minYEdge).slice
        var p = Path(
            roundedRect: bubble,
            cornerSize: CGSize(width: 10, height: 10))
        p.move(to: CGPoint(x: bubble.minX + bubble.width * 0.18, y: bubble.maxY))
        p.addLine(to: CGPoint(x: bubble.minX + bubble.width * 0.08, y: rect.maxY))
        p.addLine(to: CGPoint(x: bubble.minX + bubble.width * 0.34, y: bubble.maxY))
        p.closeSubpath()
        return p
    }
}

private struct MothWings: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.addEllipse(
                in: CGRect(
                    x: rect.minX, y: rect.minY + rect.height * 0.10,
                    width: rect.width * 0.46, height: rect.height * 0.80))
            p.addEllipse(
                in: CGRect(
                    x: rect.maxX - rect.width * 0.46, y: rect.minY + rect.height * 0.10,
                    width: rect.width * 0.46, height: rect.height * 0.80))
            p.addRoundedRect(
                in: CGRect(
                    x: rect.midX - rect.width * 0.07, y: rect.minY,
                    width: rect.width * 0.14, height: rect.height * 0.92),
                cornerSize: CGSize(width: rect.width * 0.07, height: rect.width * 0.07))
        }
    }
}

private struct CoilLine: Shape {
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let steps = 80
        var p = Path()
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let angle = t * 3.2 * 2 * .pi - .pi / 2
            let radius = (0.10 + t * 0.40) * Double(min(rect.width, rect.height))
            let point = CGPoint(
                x: c.x + CGFloat(cos(angle) * radius),
                y: c.y + CGFloat(sin(angle) * radius))
            if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
        }
        return p
    }
}

private struct PaceLine: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX, y: rect.maxY * 0.82))
            p.addLine(to: CGPoint(x: rect.width * 0.28, y: rect.height * 0.58))
            p.addLine(to: CGPoint(x: rect.width * 0.48, y: rect.height * 0.64))
            p.addLine(to: CGPoint(x: rect.width * 0.78, y: rect.height * 0.18))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }
    }
}

private struct PaceProjection: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX, y: rect.maxY * 0.55))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.height * 0.38))
        }
    }
}

private struct WeekBars: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let heights: [CGFloat] = [0.35, 0.55, 0.45, 0.82, 0.62, 0.28, 0.50]
        let gap = rect.width * 0.06
        let w = (rect.width - gap * 6) / 7
        for (i, h) in heights.enumerated() {
            let x = rect.minX + CGFloat(i) * (w + gap)
            let bar = rect.height * h
            p.addRoundedRect(
                in: CGRect(x: x, y: rect.maxY - bar, width: w, height: bar),
                cornerSize: CGSize(width: w / 2, height: w / 2))
        }
        return p
    }
}

private struct BraidLines: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + rect.width * 0.22, y: rect.minY))
        p.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.22, y: rect.maxY),
            control1: CGPoint(x: rect.maxX, y: rect.height * 0.33),
            control2: CGPoint(x: rect.minX, y: rect.height * 0.66))
        p.move(to: CGPoint(x: rect.maxX - rect.width * 0.22, y: rect.minY))
        p.addCurve(
            to: CGPoint(x: rect.maxX - rect.width * 0.22, y: rect.maxY),
            control1: CGPoint(x: rect.minX, y: rect.height * 0.33),
            control2: CGPoint(x: rect.maxX, y: rect.height * 0.66))
        return p
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

private struct WallBricks: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let rows = 3
        let cols = 4
        let gap: CGFloat = 3
        let h = (rect.height - gap * CGFloat(rows - 1)) / CGFloat(rows)
        let w = (rect.width - gap * CGFloat(cols - 1)) / CGFloat(cols)
        for row in 0..<rows {
            let offset = row.isMultiple(of: 2) ? 0 : w / 2
            let count = row.isMultiple(of: 2) ? cols : cols - 1
            for col in 0..<count {
                let x = rect.minX + offset + CGFloat(col) * (w + gap)
                let y = rect.minY + CGFloat(row) * (h + gap)
                p.addRoundedRect(
                    in: CGRect(x: x, y: y, width: w, height: h),
                    cornerSize: CGSize(width: 2, height: 2))
            }
        }
        return p
    }
}
