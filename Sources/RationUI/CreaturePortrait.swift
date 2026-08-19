import RationKit
import SwiftUI

/// A small scene of the creature, not a logo.
///
/// Multi-colour body, limbs, and a face. At stamp size the silhouette still
/// has to read as the deed that unlocked it.
struct CreaturePortrait: View {
    let creature: Creature
    var caught: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var art = CreatureArtStore.shared

    init(creature: Creature, caught: Bool = true) {
        self.creature = creature
        self.caught = caught
    }

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                GeometryReader { geo in
                    let s = min(geo.size.width, geo.size.height)
                    let _ = art.generation
                    ZStack {
                        if caught {
                            Circle()
                                .fill(ink.opacity(0.28))
                                .blur(radius: s * 0.08)
                                .frame(width: s * 0.78, height: s * 0.78)
                        }
                        if caught, let custom = art.image(for: creature.id) {
                            Image(nsImage: custom)
                                .resizable()
                                .scaledToFit()
                                .clipShape(
                                    RoundedRectangle(cornerRadius: s * 0.12, style: .continuous)
                                )
                                .padding(s * 0.04)
                        } else {
                            drawn(s)
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .modifier(IdleBob(enabled: caught && !reduceMotion, amplitude: s * 0.03))
                }
            }
            .accessibilityHidden(true)
    }

    private var ink: Color { caught ? creature.rarity.color : Color.primary.opacity(0.38) }
    private var shade: Color { Color.black.opacity(caught ? 0.18 : 0.08) }
    private var shine: Color { Color.white.opacity(caught ? 0.55 : 0.12) }

    @ViewBuilder
    private func drawn(_ s: CGFloat) -> some View {
        ZStack {
            Ellipse()
                .fill(Color.black.opacity(caught ? 0.16 : 0.06))
                .frame(width: s * 0.42, height: s * 0.10)
                .offset(y: s * 0.36)
            scene(s)
            if caught {
                sparkles(s)
            }
        }
    }

    @ViewBuilder
    private func scene(_ s: CGFloat) -> some View {
        switch creature.id {
        case "sparkit": ember(s)
        case "promptail": prompt(s)
        case "gaugeling": needle(s)
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
        case "draftling": draft(s)
        case "replybit": reply(s)
        case "tabbit": tab(s)
        case "diffling": diff(s)
        case "patchkit": patch(s)
        case "commito": commit(s)
        case "branchlet": branch(s)
        case "merjil": merge(s)
        case "rebasil": rebase(s)
        case "blamelite": blame(s)
        case "lintail": lint(s)
        case "buildrake": build(s)
        case "shipling": ship(s)
        case "crashowl": crash(s)
        case "dawnkit": dawn(s)
        case "duskwing": dusk(s)
        case "billow": bill(s)
        case "echoling": echo(s)
        case "vaultaur": vault(s)
        case "orbiton": orbit(s)
        case "floodwyrm": flood(s)
        case "summitox": summit(s)
        case "zenithar": zenith(s)
        case "foreveris": forever(s)
        default: mark(s)
        }
    }

    // MARK: Faces

    private func eyes(_ s: CGFloat, y: CGFloat = -0.04, spread: CGFloat = 0.09) -> some View {
        HStack(spacing: s * spread) {
            eye(s)
            eye(s)
        }
        .offset(y: s * y)
        .opacity(caught ? 1 : 0.35)
    }

    private func eye(_ s: CGFloat) -> some View {
        ZStack {
            Ellipse()
                .fill(Color.white)
                .frame(width: s * 0.13, height: s * 0.16)
            Ellipse()
                .fill(Color.black)
                .frame(width: s * 0.06, height: s * 0.08)
                .offset(x: s * 0.018, y: s * 0.012)
            Circle()
                .fill(Color.white)
                .frame(width: s * 0.028, height: s * 0.028)
                .offset(x: s * 0.028, y: -s * 0.022)
        }
    }

    private func blush(_ s: CGFloat, y: CGFloat = 0.06) -> some View {
        HStack(spacing: s * 0.22) {
            Capsule().fill(Color.pink.opacity(caught ? 0.45 : 0.12))
                .frame(width: s * 0.07, height: s * 0.03)
            Capsule().fill(Color.pink.opacity(caught ? 0.45 : 0.12))
                .frame(width: s * 0.07, height: s * 0.03)
        }
        .offset(y: s * y)
    }

    private func mouth(_ s: CGFloat, kind: Mouth, y: CGFloat = 0.10) -> some View {
        Group {
            switch kind {
            case .grin:
                Capsule()
                    .fill(Color.black.opacity(0.55))
                    .frame(width: s * 0.12, height: s * 0.03)
            case .o:
                Circle()
                    .stroke(Color.black.opacity(0.55), lineWidth: max(1.2, s * 0.012))
                    .frame(width: s * 0.06, height: s * 0.06)
            case .smug:
                Capsule()
                    .fill(Color.black.opacity(0.55))
                    .frame(width: s * 0.10, height: s * 0.022)
                    .rotationEffect(.degrees(18))
                    .offset(x: s * 0.02)
            case .fang:
                ZStack {
                    Capsule()
                        .fill(Color.black.opacity(0.5))
                        .frame(width: s * 0.12, height: s * 0.028)
                    Triangle()
                        .fill(Color.white)
                        .frame(width: s * 0.04, height: s * 0.05)
                        .offset(x: s * 0.02, y: s * 0.02)
                }
            case .w:
                Text("w")
                    .font(.system(size: s * 0.10, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.55))
            }
        }
        .offset(y: s * y)
        .opacity(caught ? 1 : 0)
    }

    private enum Mouth { case grin, o, smug, fang, w }

    private func sparkles(_ s: CGFloat) -> some View {
        let n = creature.rarity.rank
        return ZStack {
            ForEach(0..<n, id: \.self) { i in
                Image(systemName: "sparkle")
                    .font(.system(size: s * (0.05 + CGFloat(i % 2) * 0.02)))
                    .foregroundStyle(shine)
                    .offset(
                        x: s * (0.28 - CGFloat(i) * 0.08),
                        y: s * (-0.30 + CGFloat(i) * 0.07))
            }
        }
    }

    private func arm(_ s: CGFloat, x: CGFloat, y: CGFloat, rot: Double) -> some View {
        Capsule()
            .fill(ink)
            .frame(width: s * 0.07, height: s * 0.18)
            .rotationEffect(.degrees(rot))
            .offset(x: s * x, y: s * y)
    }

    private func foot(_ s: CGFloat, x: CGFloat) -> some View {
        Capsule()
            .fill(ink)
            .frame(width: s * 0.10, height: s * 0.06)
            .offset(x: s * x, y: s * 0.28)
    }

    // MARK: Creatures

    private func ember(_ s: CGFloat) -> some View {
        ZStack {
            EmberFlame()
                .fill(ink.opacity(0.45))
                .frame(width: s * 0.50, height: s * 0.64)
                .offset(x: s * 0.04, y: s * 0.02)
            EmberFlame()
                .fill(ink)
                .frame(width: s * 0.44, height: s * 0.60)
            EmberFlame()
                .fill(Color.yellow.opacity(caught ? 0.85 : 0.2))
                .frame(width: s * 0.22, height: s * 0.32)
                .offset(y: s * 0.10)
            Ellipse()
                .fill(Color.white.opacity(caught ? 0.75 : 0.15))
                .frame(width: s * 0.10, height: s * 0.14)
                .offset(y: s * 0.16)
            arm(s, x: -0.22, y: 0.10, rot: 40)
            arm(s, x: 0.22, y: 0.10, rot: -40)
            eyes(s, y: 0.04)
            blush(s, y: 0.14)
            mouth(s, kind: .o, y: 0.18)
        }
    }

    private func prompt(_ s: CGFloat) -> some View {
        ZStack {
            PromptTail()
                .fill(ink.opacity(0.85))
                .frame(width: s * 0.22, height: s * 0.28)
                .offset(x: s * 0.22, y: s * 0.18)
            PromptBubble()
                .fill(ink)
                .frame(width: s * 0.64, height: s * 0.50)
            PromptBubble()
                .fill(Color.white.opacity(caught ? 0.22 : 0.06))
                .frame(width: s * 0.52, height: s * 0.38)
                .offset(y: -s * 0.02)
            VStack(alignment: .leading, spacing: s * 0.04) {
                Capsule().fill(ink.opacity(0.55)).frame(width: s * 0.28, height: s * 0.04)
                Capsule().fill(ink.opacity(0.35)).frame(width: s * 0.18, height: s * 0.04)
            }
            .offset(x: -s * 0.06, y: -s * 0.08)
            Rectangle()
                .fill(ink)
                .frame(width: s * 0.035, height: s * 0.12)
                .offset(x: s * 0.18, y: -s * 0.02)
            eyes(s, y: -0.06)
            blush(s, y: 0.04)
            mouth(s, kind: .w, y: 0.10)
            foot(s, x: -0.12)
            foot(s, x: 0.12)
        }
    }

    private func needle(_ s: CGFloat) -> some View {
        let line = max(5, s * 0.08)
        return ZStack {
            Circle().fill(ink.opacity(0.22)).frame(width: s * 0.70, height: s * 0.70)
            Circle().stroke(ink, lineWidth: line).frame(width: s * 0.58, height: s * 0.58)
            Circle()
                .trim(from: 0, to: 0.62)
                .stroke(ink, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: s * 0.58, height: s * 0.58)
            Capsule()
                .fill(ink)
                .frame(width: line * 0.55, height: s * 0.26)
                .offset(y: -s * 0.13)
                .rotationEffect(.degrees(130), anchor: .bottom)
            Circle().fill(ink).frame(width: line, height: line)
            eyes(s, y: 0.02, spread: 0.07)
            mouth(s, kind: .smug, y: 0.14)
            foot(s, x: -0.14)
            foot(s, x: 0.14)
        }
    }

    private func moth(_ s: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(Color.yellow.opacity(caught ? 0.85 : 0.2))
                .frame(width: s * 0.12, height: s * 0.12)
                .offset(x: s * 0.26, y: -s * 0.24)
            Circle()
                .fill(Color.yellow.opacity(caught ? 0.35 : 0.08))
                .blur(radius: 4)
                .frame(width: s * 0.22, height: s * 0.22)
                .offset(x: s * 0.26, y: -s * 0.24)
            MothWings()
                .fill(ink.opacity(0.75))
                .frame(width: s * 0.78, height: s * 0.50)
            Circle()
                .fill(Color.white.opacity(caught ? 0.35 : 0.1))
                .frame(width: s * 0.10, height: s * 0.10)
                .offset(x: -s * 0.18, y: -s * 0.02)
            Circle()
                .fill(Color.white.opacity(caught ? 0.35 : 0.1))
                .frame(width: s * 0.10, height: s * 0.10)
                .offset(x: s * 0.12, y: -s * 0.02)
            Capsule()
                .fill(ink)
                .frame(width: s * 0.12, height: s * 0.36)
            Capsule()
                .stroke(ink, lineWidth: 1.5)
                .frame(width: s * 0.10, height: s * 0.18)
                .offset(x: -s * 0.08, y: -s * 0.28)
                .rotationEffect(.degrees(-25))
            Capsule()
                .stroke(ink, lineWidth: 1.5)
                .frame(width: s * 0.10, height: s * 0.18)
                .offset(x: s * 0.08, y: -s * 0.28)
                .rotationEffect(.degrees(25))
            eyes(s, y: -0.02, spread: 0.05)
            mouth(s, kind: .o, y: 0.10)
        }
    }

    private func wisp(_ s: CGFloat) -> some View {
        ZStack {
            Circle().fill(ink.opacity(0.30)).frame(width: s * 0.50, height: s * 0.50)
                .offset(y: -s * 0.14)
            Circle().fill(ink.opacity(0.55)).frame(width: s * 0.36, height: s * 0.36)
            Circle().fill(ink).frame(width: s * 0.20, height: s * 0.20)
                .offset(y: s * 0.18)
            Ellipse()
                .fill(shine)
                .frame(width: s * 0.16, height: s * 0.10)
                .offset(x: -s * 0.06, y: -s * 0.20)
            eyes(s, y: -0.12)
            mouth(s, kind: .w, y: -0.02)
        }
    }

    private func cell(_ s: CGFloat) -> some View {
        let w = s * 0.52
        let h = s * 0.46
        return ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(ink)
                .frame(width: w, height: h)
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 0)
                    .fill(shade)
                    .frame(height: h * 0.22)
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 4),
                    spacing: 3
                ) {
                    ForEach(0..<8, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(i == 4 ? Color.yellow.opacity(caught ? 0.95 : 0.25) : shine)
                            .frame(height: (h * 0.55) / 2 - 1)
                    }
                }
                .padding(5)
            }
            .frame(width: w, height: h)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            arm(s, x: -0.32, y: 0.04, rot: 25)
            arm(s, x: 0.32, y: 0.04, rot: -25)
            eyes(s, y: -0.12, spread: 0.10)
            mouth(s, kind: .grin, y: -0.02)
            foot(s, x: -0.14)
            foot(s, x: 0.14)
        }
    }

    private func session(_ s: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(ink)
                .frame(width: s * 0.62, height: s * 0.48)
            HStack(spacing: 4) {
                Circle().fill(Color.red.opacity(caught ? 0.85 : 0.25)).frame(width: s * 0.06)
                Circle().fill(Color.yellow.opacity(caught ? 0.85 : 0.25)).frame(width: s * 0.06)
                Circle().fill(Color.green.opacity(caught ? 0.85 : 0.25)).frame(width: s * 0.06)
                Spacer()
            }
            .padding(.horizontal, 8)
            .offset(y: -s * 0.16)
            .frame(width: s * 0.62)
            Triangle()
                .fill(ink)
                .frame(width: s * 0.16, height: s * 0.18)
                .rotationEffect(.degrees(20))
                .offset(x: s * 0.28, y: -s * 0.22)
            eyes(s, y: 0.02)
            blush(s, y: 0.12)
            mouth(s, kind: .grin, y: 0.16)
            foot(s, x: -0.12)
            foot(s, x: 0.12)
        }
    }

    private func coil(_ s: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(ink.opacity(0.30), lineWidth: 4)
                .frame(width: s * 0.26, height: s * 0.26)
            CoilLine()
                .stroke(ink, style: StrokeStyle(lineWidth: s * 0.08, lineCap: .round))
                .frame(width: s * 0.64, height: s * 0.64)
            Circle()
                .fill(ink)
                .frame(width: s * 0.22, height: s * 0.22)
                .offset(x: s * 0.22, y: -s * 0.18)
            eyes(s, y: -0.20, spread: 0.04)
                .offset(x: s * 0.22)
            mouth(s, kind: .fang, y: -0.10)
                .offset(x: s * 0.22)
        }
    }

    private func context(_ s: CGFloat) -> some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(ink.opacity(1 - Double(i) * 0.22))
                    .frame(width: s * 0.46 - CGFloat(i) * 6, height: s * 0.34)
                    .offset(y: CGFloat(i) * s * -0.10)
            }
            Triangle()
                .fill(ink)
                .frame(width: s * 0.12, height: s * 0.12)
                .offset(x: -s * 0.16, y: -s * 0.28)
            Triangle()
                .fill(ink)
                .frame(width: s * 0.12, height: s * 0.12)
                .offset(x: s * 0.16, y: -s * 0.28)
            eyes(s, y: 0.02)
            mouth(s, kind: .smug, y: 0.14)
            foot(s, x: -0.12)
            foot(s, x: 0.12)
        }
    }

    private func shift(_ s: CGFloat) -> some View {
        ZStack {
            HStack(spacing: s * -0.10) {
                ForEach(0..<3, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(ink.opacity(0.50 + Double(i) * 0.22))
                        .frame(width: s * 0.24, height: s * 0.40 + CGFloat(i == 1 ? 10 : 0))
                }
            }
            eyes(s, y: -0.04, spread: 0.16)
            mouth(s, kind: .o, y: 0.10)
            foot(s, x: -0.16)
            foot(s, x: 0.16)
        }
    }

    private func streak(_ s: CGFloat) -> some View {
        let d = s * 0.16
        return ZStack {
            Capsule().fill(ink.opacity(0.45)).frame(width: s * 0.70, height: s * 0.06)
            HStack(spacing: s * 0.02) {
                ForEach(0..<5, id: \.self) { i in
                    Circle()
                        .fill(i == 4 ? ink : ink.opacity(0.55 + Double(i) * 0.1))
                        .frame(width: d, height: d)
                }
            }
            eyes(s, y: -0.02, spread: 0.22)
            mouth(s, kind: .grin, y: 0.10)
        }
    }

    private func pace(_ s: CGFloat) -> some View {
        ZStack {
            PaceProjection()
                .stroke(
                    ink.opacity(0.28),
                    style: StrokeStyle(lineWidth: 2, dash: [4, 4])
                )
                .frame(width: s * 0.72, height: s * 0.40)
            PaceLine()
                .stroke(ink, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                .frame(width: s * 0.72, height: s * 0.40)
            EmberFlame()
                .fill(ink)
                .frame(width: s * 0.22, height: s * 0.30)
                .offset(x: s * 0.22, y: -s * 0.18)
            eyes(s, y: -0.20, spread: 0.04)
                .offset(x: s * 0.22)
            mouth(s, kind: .o, y: -0.10)
                .offset(x: s * 0.22)
        }
    }

    private func week(_ s: CGFloat) -> some View {
        ZStack {
            Ellipse()
                .fill(ink)
                .frame(width: s * 0.42, height: s * 0.32)
                .offset(y: s * 0.10)
            WeekBars()
                .fill(ink)
                .frame(width: s * 0.62, height: s * 0.32)
                .offset(y: -s * 0.12)
            Triangle()
                .fill(ink)
                .frame(width: s * 0.12, height: s * 0.10)
                .offset(x: s * 0.22, y: s * 0.02)
            eyes(s, y: 0.06)
            blush(s, y: 0.16)
            mouth(s, kind: .fang, y: 0.18)
            foot(s, x: -0.12)
            foot(s, x: 0.14)
        }
    }

    private func braid(_ s: CGFloat) -> some View {
        ZStack {
            BraidLines()
                .stroke(ink, style: StrokeStyle(lineWidth: s * 0.10, lineCap: .round))
                .frame(width: s * 0.34, height: s * 0.48)
                .offset(y: s * 0.08)
            Circle().fill(ink).frame(width: s * 0.28, height: s * 0.28)
                .offset(x: -s * 0.16, y: -s * 0.16)
            Circle().fill(ink).frame(width: s * 0.28, height: s * 0.28)
                .offset(x: s * 0.16, y: -s * 0.16)
            eye(s).offset(x: -s * 0.16, y: -s * 0.16)
            eye(s).offset(x: s * 0.16, y: -s * 0.16)
            mouth(s, kind: .smug, y: -0.08)
                .offset(x: -s * 0.16)
            mouth(s, kind: .grin, y: -0.08)
                .offset(x: s * 0.16)
            foot(s, x: -0.10)
            foot(s, x: 0.10)
        }
    }

    private func night(_ s: CGFloat) -> some View {
        ZStack {
            Image(systemName: "moon.fill")
                .font(.system(size: s * 0.48, weight: .regular))
                .foregroundStyle(ink)
            Circle()
                .fill(ink)
                .frame(width: s * 0.36, height: s * 0.36)
                .offset(y: s * 0.10)
            HStack(spacing: s * 0.05) {
                Image(systemName: "star.fill").font(.system(size: s * 0.09))
                Image(systemName: "star.fill").font(.system(size: s * 0.06))
            }
            .foregroundStyle(Color.yellow.opacity(caught ? 0.95 : 0.25))
            .offset(x: s * 0.26, y: -s * 0.24)
            eyes(s, y: 0.04)
            blush(s, y: 0.14)
            mouth(s, kind: .w, y: 0.18)
        }
    }

    private func trio(_ s: CGFloat) -> some View {
        ZStack {
            Circle().fill(ink).frame(width: s * 0.58, height: s * 0.58)
            HStack(spacing: s * 0.04) {
                Circle().fill(Color.white).frame(width: s * 0.12, height: s * 0.14)
                Circle().fill(Color.white).frame(width: s * 0.12, height: s * 0.14)
                Circle().fill(Color.white).frame(width: s * 0.12, height: s * 0.14)
            }
            .offset(y: -s * 0.08)
            HStack(spacing: s * 0.04) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle().fill(Color.black).frame(width: s * 0.05, height: s * 0.06)
                }
            }
            .offset(y: -s * 0.07)
            HStack(spacing: s * 0.08) {
                Image(systemName: "sparkle").font(.system(size: s * 0.08))
                Image(systemName: "chevron.right").font(.system(size: s * 0.08, weight: .bold))
                Image(systemName: "computermouse").font(.system(size: s * 0.08))
            }
            .foregroundStyle(shine)
            .offset(y: s * 0.14)
            mouth(s, kind: .grin, y: 0.04)
            arm(s, x: -0.30, y: 0.08, rot: 30)
            arm(s, x: 0.30, y: 0.08, rot: -30)
            foot(s, x: -0.12)
            foot(s, x: 0.12)
        }
    }

    private func wall(_ s: CGFloat) -> some View {
        ZStack {
            WallBricks()
                .fill(ink)
                .frame(width: s * 0.64, height: s * 0.42)
            Path { p in
                p.move(to: CGPoint(x: s * 0.18, y: s * 0.02))
                p.addLine(to: CGPoint(x: s * 0.28, y: s * 0.22))
                p.addLine(to: CGPoint(x: s * 0.22, y: s * 0.38))
            }
            .stroke(Color.black.opacity(0.35), lineWidth: 2)
            .offset(x: -s * 0.32, y: -s * 0.20)
            arm(s, x: -0.36, y: 0.02, rot: 15)
            arm(s, x: 0.36, y: 0.02, rot: -15)
            eyes(s, y: -0.04)
            mouth(s, kind: .smug, y: 0.08)
            foot(s, x: -0.16)
            foot(s, x: 0.16)
        }
    }

    private func mark(_ s: CGFloat) -> some View {
        ZStack {
            Circle().stroke(ink, lineWidth: max(5, s * 0.08))
                .frame(width: s * 0.52, height: s * 0.52)
            Capsule()
                .fill(ink)
                .frame(width: s * 0.08, height: s * 0.28)
                .offset(y: -s * 0.06)
                .rotationEffect(.degrees(-28))
            Circle().fill(ink).frame(width: s * 0.10, height: s * 0.10)
            eyes(s, y: 0.02)
            blush(s, y: 0.12)
            mouth(s, kind: .smug, y: 0.16)
        }
    }

    private func draft(_ s: CGFloat) -> some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                PromptBubble()
                    .fill(ink.opacity(i == 0 ? 0.35 : 1 - Double(i) * 0.15))
                    .frame(width: s * 0.46 - CGFloat(i) * 6, height: s * 0.28)
                    .offset(y: CGFloat(i) * s * -0.12)
            }
            eyes(s, y: -0.04)
            mouth(s, kind: .o, y: 0.08)
            foot(s, x: -0.10)
            foot(s, x: 0.10)
        }
    }

    private func reply(_ s: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(ink.opacity(0.45))
                .frame(width: s * 0.48, height: s * 0.36)
                .offset(x: -s * 0.08, y: -s * 0.08)
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(ink)
                .frame(width: s * 0.48, height: s * 0.36)
                .offset(x: s * 0.08, y: s * 0.06)
            eyes(s, y: 0.04)
            mouth(s, kind: .grin, y: 0.16)
            foot(s, x: -0.06)
            foot(s, x: 0.16)
        }
    }

    private func tab(_ s: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(ink)
                .frame(width: s * 0.56, height: s * 0.40)
                .offset(y: s * 0.06)
            UnevenRoundedRectangle(
                topLeadingRadius: 8, bottomLeadingRadius: 0,
                bottomTrailingRadius: 0, topTrailingRadius: 8, style: .continuous
            )
            .fill(ink)
            .frame(width: s * 0.28, height: s * 0.14)
            .offset(x: -s * 0.12, y: -s * 0.20)
            Triangle().fill(ink).frame(width: s * 0.10, height: s * 0.10)
                .offset(x: -s * 0.18, y: -s * 0.28)
            Triangle().fill(ink).frame(width: s * 0.10, height: s * 0.10)
                .offset(x: s * 0.18, y: -s * 0.04)
            eyes(s, y: 0.04)
            mouth(s, kind: .w, y: 0.16)
        }
    }

    private func diff(_ s: CGFloat) -> some View {
        ZStack {
            UnevenRoundedRectangle(
                topLeadingRadius: 18, bottomLeadingRadius: 18,
                bottomTrailingRadius: 4, topTrailingRadius: 4, style: .continuous
            )
            .fill(ink)
            .frame(width: s * 0.28, height: s * 0.48)
            .offset(x: -s * 0.14)
            UnevenRoundedRectangle(
                topLeadingRadius: 4, bottomLeadingRadius: 4,
                bottomTrailingRadius: 18, topTrailingRadius: 18, style: .continuous
            )
            .stroke(ink, style: StrokeStyle(lineWidth: 3, dash: [5, 3]))
            .frame(width: s * 0.28, height: s * 0.48)
            .offset(x: s * 0.14)
            eyes(s, y: -0.06, spread: 0.18)
            mouth(s, kind: .smug, y: 0.08)
            foot(s, x: -0.16)
            foot(s, x: 0.16)
        }
    }

    private func patch(_ s: CGFloat) -> some View {
        ZStack {
            Circle().fill(ink).frame(width: s * 0.50, height: s * 0.50)
            Capsule().fill(Color.white.opacity(caught ? 0.85 : 0.25))
                .frame(width: s * 0.32, height: s * 0.10)
                .rotationEffect(.degrees(-18))
            Capsule().fill(Color.white.opacity(caught ? 0.85 : 0.25))
                .frame(width: s * 0.32, height: s * 0.10)
                .rotationEffect(.degrees(72))
            PromptTail().fill(ink).frame(width: s * 0.16, height: s * 0.22)
                .offset(x: s * 0.26, y: s * 0.18)
            eyes(s, y: -0.08)
            mouth(s, kind: .grin, y: 0.06)
            arm(s, x: -0.28, y: 0.10, rot: 25)
            foot(s, x: -0.12)
            foot(s, x: 0.12)
        }
    }

    private func commit(_ s: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(ink)
                .frame(width: s * 0.42, height: s * 0.50)
            Capsule().fill(ink).frame(width: s * 0.12, height: s * 0.22)
                .offset(y: -s * 0.32)
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.white.opacity(caught ? 0.30 : 0.08))
                .frame(width: s * 0.24, height: s * 0.16)
            eyes(s, y: 0.02)
            mouth(s, kind: .smug, y: 0.16)
            arm(s, x: -0.28, y: 0.08, rot: 20)
            arm(s, x: 0.28, y: 0.08, rot: -20)
        }
    }

    private func branch(_ s: CGFloat) -> some View {
        ZStack {
            Capsule().fill(ink).frame(width: s * 0.10, height: s * 0.36)
                .offset(y: s * 0.16)
            Capsule().fill(ink).frame(width: s * 0.10, height: s * 0.32)
                .rotationEffect(.degrees(-38))
                .offset(x: -s * 0.14, y: -s * 0.08)
            Capsule().fill(ink).frame(width: s * 0.10, height: s * 0.32)
                .rotationEffect(.degrees(38))
                .offset(x: s * 0.14, y: -s * 0.08)
            Circle().fill(ink).frame(width: s * 0.22, height: s * 0.22)
                .offset(x: -s * 0.22, y: -s * 0.22)
            Circle().fill(ink).frame(width: s * 0.22, height: s * 0.22)
                .offset(x: s * 0.22, y: -s * 0.22)
            eye(s).offset(x: -s * 0.22, y: -s * 0.22)
            eye(s).offset(x: s * 0.22, y: -s * 0.22)
            mouth(s, kind: .o, y: -0.14).offset(x: -s * 0.22)
            mouth(s, kind: .grin, y: -0.14).offset(x: s * 0.22)
        }
    }

    private func merge(_ s: CGFloat) -> some View {
        ZStack {
            BraidLines()
                .stroke(ink, style: StrokeStyle(lineWidth: s * 0.10, lineCap: .round))
                .frame(width: s * 0.40, height: s * 0.40)
                .offset(y: -s * 0.08)
            Circle().fill(ink).frame(width: s * 0.40, height: s * 0.40)
                .offset(y: s * 0.14)
            eyes(s, y: 0.12)
            blush(s, y: 0.22)
            mouth(s, kind: .w, y: 0.24)
        }
    }

    private func rebase(_ s: CGFloat) -> some View {
        ZStack {
            ForEach(0..<4, id: \.self) { i in
                Capsule()
                    .fill(ink.opacity(1 - Double(i) * 0.18))
                    .frame(width: s * 0.46, height: s * 0.12)
                    .offset(x: CGFloat(i) * s * 0.04, y: CGFloat(i) * s * -0.10)
            }
            eyes(s, y: -0.22)
            mouth(s, kind: .smug, y: -0.10)
            foot(s, x: -0.10)
            foot(s, x: 0.14)
        }
    }

    private func blame(_ s: CGFloat) -> some View {
        ZStack {
            Circle().fill(ink).frame(width: s * 0.42, height: s * 0.42)
            Capsule().fill(ink).frame(width: s * 0.12, height: s * 0.36)
                .rotationEffect(.degrees(55))
                .offset(x: s * 0.28, y: s * 0.02)
            Circle().fill(ink).frame(width: s * 0.10, height: s * 0.10)
                .offset(x: s * 0.40, y: -s * 0.10)
            eyes(s, y: -0.06)
            mouth(s, kind: .smug, y: 0.08)
            foot(s, x: -0.12)
            foot(s, x: 0.10)
        }
    }

    private func lint(_ s: CGFloat) -> some View {
        ZStack {
            Circle().stroke(ink, lineWidth: max(4, s * 0.06))
                .frame(width: s * 0.36, height: s * 0.36)
                .offset(x: -s * 0.08, y: -s * 0.08)
            Capsule().fill(ink).frame(width: s * 0.08, height: s * 0.28)
                .rotationEffect(.degrees(40))
                .offset(x: s * 0.16, y: s * 0.16)
            PromptTail().fill(ink).frame(width: s * 0.18, height: s * 0.24)
                .offset(x: s * 0.26, y: s * 0.08)
            eyes(s, y: -0.10, spread: 0.05)
            mouth(s, kind: .o, y: 0.02)
        }
    }

    private func build(_ s: CGFloat) -> some View {
        ZStack {
            Circle().stroke(ink, lineWidth: max(6, s * 0.08))
                .frame(width: s * 0.48, height: s * 0.48)
            ForEach(0..<6, id: \.self) { i in
                Capsule().fill(ink)
                    .frame(width: s * 0.10, height: s * 0.18)
                    .offset(y: -s * 0.28)
                    .rotationEffect(.degrees(Double(i) * 60))
            }
            Circle().fill(ink).frame(width: s * 0.22, height: s * 0.22)
            eyes(s, y: 0.0, spread: 0.04)
            mouth(s, kind: .o, y: 0.10)
        }
    }

    private func ship(_ s: CGFloat) -> some View {
        ZStack {
            Triangle().fill(ink).frame(width: s * 0.36, height: s * 0.22)
                .offset(y: -s * 0.24)
            Capsule().fill(ink).frame(width: s * 0.28, height: s * 0.48)
            Triangle().fill(ink).frame(width: s * 0.14, height: s * 0.16)
                .rotationEffect(.degrees(-90))
                .offset(x: -s * 0.22, y: s * 0.04)
            Triangle().fill(ink).frame(width: s * 0.14, height: s * 0.16)
                .rotationEffect(.degrees(90))
                .offset(x: s * 0.22, y: s * 0.04)
            eyes(s, y: -0.04)
            mouth(s, kind: .grin, y: 0.08)
        }
    }

    private func crash(_ s: CGFloat) -> some View {
        ZStack {
            Circle().fill(ink).frame(width: s * 0.52, height: s * 0.52)
            Path { p in
                p.move(to: CGPoint(x: s * 0.08, y: -s * 0.16))
                p.addLine(to: CGPoint(x: s * 0.16, y: 0))
                p.addLine(to: CGPoint(x: s * 0.10, y: s * 0.16))
            }
            .stroke(Color.black.opacity(0.35), lineWidth: 2)
            Triangle().fill(Color.yellow.opacity(caught ? 0.95 : 0.25))
                .frame(width: s * 0.12, height: s * 0.18)
                .offset(x: s * 0.22, y: -s * 0.28)
            eyes(s, y: -0.04, spread: 0.12)
            mouth(s, kind: .o, y: 0.10)
        }
    }

    private func dawn(_ s: CGFloat) -> some View {
        ZStack {
            ForEach(0..<8, id: \.self) { i in
                Capsule().fill(ink.opacity(0.85))
                    .frame(width: s * 0.06, height: s * 0.16)
                    .offset(y: -s * 0.30)
                    .rotationEffect(.degrees(Double(i) * 45))
            }
            Circle().fill(ink).frame(width: s * 0.42, height: s * 0.42)
            eyes(s, y: -0.02)
            blush(s, y: 0.10)
            mouth(s, kind: .grin, y: 0.14)
        }
    }

    private func dusk(_ s: CGFloat) -> some View {
        ZStack {
            ForEach(0..<6, id: \.self) { i in
                Capsule().fill(ink.opacity(0.55))
                    .frame(width: s * 0.07, height: s * 0.20)
                    .offset(y: -s * 0.26)
                    .rotationEffect(.degrees(Double(i) * 30 - 75))
            }
            Circle().fill(ink).frame(width: s * 0.44, height: s * 0.44)
            Capsule().fill(Color.black.opacity(caught ? 0.35 : 0.12))
                .frame(width: s * 0.14, height: s * 0.04)
                .offset(x: -s * 0.08, y: -s * 0.06)
            Capsule().fill(Color.black.opacity(caught ? 0.35 : 0.12))
                .frame(width: s * 0.14, height: s * 0.04)
                .offset(x: s * 0.08, y: -s * 0.06)
            mouth(s, kind: .w, y: 0.10)
        }
    }

    private func bill(_ s: CGFloat) -> some View {
        ZStack {
            Circle().fill(ink).frame(width: s * 0.56, height: s * 0.56)
            Circle().stroke(shine, lineWidth: 2)
                .frame(width: s * 0.42, height: s * 0.42)
            Text("S")
                .font(.system(size: s * 0.22, weight: .heavy, design: .rounded))
                .foregroundStyle(shine)
                .offset(y: -s * 0.02)
            eyes(s, y: -0.12, spread: 0.12)
            mouth(s, kind: .o, y: 0.14)
        }
    }

    private func echo(_ s: CGFloat) -> some View {
        ZStack {
            Circle().stroke(ink.opacity(0.30), lineWidth: 3)
                .frame(width: s * 0.70, height: s * 0.70)
            Circle().stroke(ink.opacity(0.55), lineWidth: 3)
                .frame(width: s * 0.52, height: s * 0.52)
            Circle().fill(ink).frame(width: s * 0.34, height: s * 0.34)
            eyes(s, y: -0.04, spread: 0.05)
            mouth(s, kind: .o, y: 0.08)
        }
    }

    private func vault(_ s: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(ink)
                .frame(width: s * 0.56, height: s * 0.36)
                .offset(y: s * 0.08)
            UnevenRoundedRectangle(
                topLeadingRadius: 10, bottomLeadingRadius: 2,
                bottomTrailingRadius: 2, topTrailingRadius: 10, style: .continuous
            )
            .fill(ink.opacity(0.85))
            .frame(width: s * 0.56, height: s * 0.16)
            .offset(y: -s * 0.14)
            Circle().stroke(shine, lineWidth: 2)
                .frame(width: s * 0.10, height: s * 0.10)
                .offset(y: s * 0.10)
            eyes(s, y: -0.14, spread: 0.10)
            mouth(s, kind: .smug, y: 0.18)
        }
    }

    private func orbit(_ s: CGFloat) -> some View {
        ZStack {
            Ellipse().stroke(ink, lineWidth: 3)
                .frame(width: s * 0.70, height: s * 0.28)
                .rotationEffect(.degrees(-18))
            Circle().fill(ink).frame(width: s * 0.40, height: s * 0.40)
            Circle().fill(ink).frame(width: s * 0.12, height: s * 0.12)
                .offset(x: s * 0.30, y: -s * 0.16)
            eyes(s, y: -0.02)
            mouth(s, kind: .grin, y: 0.10)
        }
    }

    private func flood(_ s: CGFloat) -> some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Capsule()
                    .fill(ink.opacity(1 - Double(i) * 0.22))
                    .frame(width: s * 0.62 - CGFloat(i) * 8, height: s * 0.16)
                    .offset(y: CGFloat(i) * s * 0.12)
            }
            Circle().fill(ink).frame(width: s * 0.24, height: s * 0.24)
                .offset(x: s * 0.22, y: -s * 0.16)
            eyes(s, y: -0.18, spread: 0.04)
                .offset(x: s * 0.22)
            mouth(s, kind: .fang, y: -0.08)
                .offset(x: s * 0.22)
        }
    }

    private func summit(_ s: CGFloat) -> some View {
        ZStack {
            Triangle().fill(ink.opacity(0.55)).frame(width: s * 0.28, height: s * 0.36)
                .offset(x: -s * 0.16, y: s * 0.08)
            Triangle().fill(ink).frame(width: s * 0.48, height: s * 0.56)
            Capsule().fill(Color.white.opacity(caught ? 0.85 : 0.2))
                .frame(width: s * 0.04, height: s * 0.14)
                .offset(y: -s * 0.34)
            eyes(s, y: 0.06)
            mouth(s, kind: .smug, y: 0.18)
        }
    }

    private func zenith(_ s: CGFloat) -> some View {
        ZStack {
            ForEach(0..<10, id: \.self) { i in
                Capsule().fill(ink.opacity(0.75))
                    .frame(width: s * 0.05, height: s * (i.isMultiple(of: 2) ? 0.22 : 0.14))
                    .offset(y: -s * 0.28)
                    .rotationEffect(.degrees(Double(i) * 36))
            }
            Circle().fill(ink).frame(width: s * 0.36, height: s * 0.36)
            eyes(s, y: -0.02, spread: 0.06)
            mouth(s, kind: .w, y: 0.10)
        }
    }

    private func forever(_ s: CGFloat) -> some View {
        ZStack {
            CoilLine()
                .stroke(ink, style: StrokeStyle(lineWidth: s * 0.08, lineCap: .round))
                .frame(width: s * 0.56, height: s * 0.40)
                .rotationEffect(.degrees(80))
            Circle().fill(ink).frame(width: s * 0.22, height: s * 0.22)
                .offset(x: s * 0.18, y: -s * 0.08)
            eyes(s, y: -0.10, spread: 0.04)
                .offset(x: s * 0.18)
            mouth(s, kind: .grin, y: 0.0)
                .offset(x: s * 0.18)
        }
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

private struct PromptTail: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.maxY),
                control: CGPoint(x: rect.maxX, y: rect.minY))
            p.addQuadCurve(
                to: CGPoint(x: rect.minX + rect.width * 0.2, y: rect.midY),
                control: CGPoint(x: rect.midX, y: rect.maxY))
            p.closeSubpath()
        }
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

private struct IdleBob: ViewModifier {
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
