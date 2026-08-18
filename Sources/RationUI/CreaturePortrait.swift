import RationKit
import SwiftUI

/// One silhouette per creature, drawn as a filled path.
///
/// No shared eyes, no type orb. At postage-stamp size the *shape* has to
/// tell them apart — colour is a confirmation, not the identity.
struct CreaturePortrait: View {
    let creature: Creature
    var caught: Bool = true

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                silhouette(s)
                    .foregroundStyle(caught ? creature.rarity.color : Color.primary.opacity(0.28))
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func silhouette(_ s: CGFloat) -> some View {
        switch creature.id {
        case "sparkit": EmberShape().frame(width: s * 0.42, height: s * 0.62)
        case "promptail": PromptShape().frame(width: s * 0.58, height: s * 0.42)
        case "gaugeling":
            NeedleMark(fill: 0.62, line: s * 0.09).frame(width: s * 0.62, height: s * 0.62)
        case "tokenoth": MothShape().frame(width: s * 0.72, height: s * 0.46)
        case "cachewisp": WispShape().frame(width: s * 0.36, height: s * 0.64)
        case "heatmite": CellShape().frame(width: s * 0.48, height: s * 0.48)
        case "sessiondrake": SessionShape().frame(width: s * 0.62, height: s * 0.48)
        case "limitwyrm": CoilShape().frame(width: s * 0.58, height: s * 0.58)
        case "contextaur": ContextShape().frame(width: s * 0.50, height: s * 0.58)
        case "modelith": ShiftShape().frame(width: s * 0.62, height: s * 0.46)
        case "streakon": StreakShape().frame(width: s * 0.70, height: s * 0.28)
        case "burnrate": PaceShape().frame(width: s * 0.70, height: s * 0.42)
        case "weeklyrex": WeekShape().frame(width: s * 0.64, height: s * 0.42)
        case "braidon": BraidShape().frame(width: s * 0.36, height: s * 0.64)
        case "nightshift":
            ZStack {
                Circle()
                Circle()
                    .frame(width: s * 0.38, height: s * 0.38)
                    .offset(x: s * 0.12, y: -s * 0.08)
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
            .frame(width: s * 0.52, height: s * 0.52)
        case "omnivore": TrioShape().frame(width: s * 0.64, height: s * 0.56)
        case "wallback": WallShape().frame(width: s * 0.62, height: s * 0.46)
        default: NeedleMark(fill: 0.72, line: s * 0.09).frame(width: s * 0.62, height: s * 0.62)
        }
    }
}

// MARK: - Shapes
//
// Each path is the whole creature. Coordinates are 0…1 inside `rect`.

private struct EmberShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.maxY * 0.72),
                control: CGPoint(x: rect.maxX, y: rect.height * 0.28))
            p.addQuadCurve(
                to: CGPoint(x: rect.midX, y: rect.maxY),
                control: CGPoint(x: rect.maxX * 0.82, y: rect.maxY))
            p.addQuadCurve(
                to: CGPoint(x: rect.minX, y: rect.maxY * 0.72),
                control: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.maxY))
            p.addQuadCurve(
                to: CGPoint(x: rect.midX, y: rect.minY),
                control: CGPoint(x: rect.minX, y: rect.height * 0.28))
        }
    }
}

private struct PromptShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX * 0.62, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX * 0.62, y: rect.maxY))
            p.closeSubpath()
            p.move(to: CGPoint(x: rect.maxX * 0.38, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX * 0.62, y: rect.height * 0.32))
            p.addLine(to: CGPoint(x: rect.maxX * 0.62, y: rect.height * 0.68))
            p.closeSubpath()
        }
    }
}

/// The same ring language as `RingGauge`: track + trimmed accent stroke.
private struct NeedleMark: View {
    var fill: CGFloat
    var line: CGFloat

    var body: some View {
        ZStack {
            Circle().stroke(.primary.opacity(0.18), lineWidth: line)
            Circle()
                .trim(from: 0, to: fill)
                .stroke(
                    Color.primary,
                    style: StrokeStyle(lineWidth: line, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
    }
}

private struct MothShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.addEllipse(
                in: CGRect(
                    x: rect.minX, y: rect.minY + rect.height * 0.12,
                    width: rect.width * 0.46, height: rect.height * 0.76))
            p.addEllipse(
                in: CGRect(
                    x: rect.maxX - rect.width * 0.46, y: rect.minY + rect.height * 0.12,
                    width: rect.width * 0.46, height: rect.height * 0.76))
            p.addRoundedRect(
                in: CGRect(
                    x: rect.midX - rect.width * 0.07, y: rect.minY,
                    width: rect.width * 0.14, height: rect.height),
                cornerSize: CGSize(width: rect.width * 0.07, height: rect.width * 0.07))
        }
    }
}

private struct WispShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.addEllipse(
                in: CGRect(
                    x: rect.midX - rect.width * 0.28, y: rect.minY,
                    width: rect.width * 0.56, height: rect.height * 0.42))
            p.addEllipse(
                in: CGRect(
                    x: rect.midX - rect.width * 0.22, y: rect.height * 0.28,
                    width: rect.width * 0.44, height: rect.height * 0.38))
            p.addEllipse(
                in: CGRect(
                    x: rect.midX - rect.width * 0.14, y: rect.height * 0.58,
                    width: rect.width * 0.28, height: rect.height * 0.42))
        }
    }
}

private struct CellShape: Shape {
    func path(in rect: CGRect) -> Path {
        let inset = rect.insetBy(dx: rect.width * 0.08, dy: rect.height * 0.08)
        var p = Path(
            roundedRect: rect,
            cornerSize: CGSize(width: rect.width * 0.18, height: rect.height * 0.18))
        p.addRoundedRect(
            in: inset, cornerSize: CGSize(width: inset.width * 0.12, height: inset.height * 0.12))
        return p
    }
}

private struct SessionShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path(
            roundedRect: rect,
            cornerSize: CGSize(width: rect.width * 0.12, height: rect.height * 0.12))
        p.addRect(
            CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.22))
        return p
    }
}

private struct CoilShape: Shape {
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let turns = 3.2
        let steps = 80
        var p = Path()
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let angle = t * turns * 2 * .pi - .pi / 2
            let radius = (0.08 + t * 0.42) * Double(min(rect.width, rect.height))
            let point = CGPoint(
                x: c.x + CGFloat(cos(angle) * radius),
                y: c.y + CGFloat(sin(angle) * radius))
            if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
        }
        return p.strokedPath(StrokeStyle(lineWidth: rect.width * 0.11, lineCap: .round))
    }
}

private struct ContextShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        for i in 0..<3 {
            let y = rect.minY + CGFloat(i) * rect.height * 0.18
            let inset = CGFloat(i) * rect.width * 0.06
            p.addRoundedRect(
                in: CGRect(
                    x: rect.minX + inset, y: y,
                    width: rect.width - inset * 2, height: rect.height * 0.48),
                cornerSize: CGSize(width: 6, height: 6))
        }
        return p
    }
}

private struct ShiftShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width * 0.36
        let h = rect.height * 0.72
        p.addRoundedRect(
            in: CGRect(x: rect.minX, y: rect.midY - h / 2, width: w, height: h),
            cornerSize: CGSize(width: 8, height: 8))
        p.addRoundedRect(
            in: CGRect(x: rect.midX - w / 2, y: rect.minY, width: w, height: h),
            cornerSize: CGSize(width: 8, height: 8))
        p.addRoundedRect(
            in: CGRect(x: rect.maxX - w, y: rect.midY - h / 2, width: w, height: h),
            cornerSize: CGSize(width: 8, height: 8))
        return p
    }
}

private struct StreakShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let count = 5
        let d = min(rect.height, rect.width / 6)
        for i in 0..<count {
            let x = rect.minX + CGFloat(i) * (rect.width - d) / CGFloat(count - 1)
            p.addEllipse(in: CGRect(x: x, y: rect.midY - d / 2, width: d, height: d))
        }
        return p
    }
}

private struct PaceShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.22, y: rect.height * 0.62))
        p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.42, y: rect.height * 0.72))
        p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.68, y: rect.height * 0.28))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

private struct WeekShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let heights: [CGFloat] = [0.35, 0.55, 0.45, 0.80, 0.62, 0.28, 0.50]
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

private struct BraidShape: Shape {
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
        return p.strokedPath(StrokeStyle(lineWidth: rect.width * 0.22, lineCap: .round))
    }
}

private struct TrioShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let d = rect.width * 0.42
        p.addEllipse(
            in: CGRect(x: rect.midX - d / 2, y: rect.minY, width: d, height: d))
        p.addEllipse(
            in: CGRect(x: rect.minX, y: rect.maxY - d, width: d, height: d))
        p.addEllipse(
            in: CGRect(x: rect.maxX - d, y: rect.maxY - d, width: d, height: d))
        return p
    }
}

private struct WallShape: Shape {
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
