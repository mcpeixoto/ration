import RationKit
import SwiftUI

/// A collectible that reads as a trading card: art window, HP, type, a move,
/// foil, and a collector number.
struct CreatureCard: View {
    let creature: Creature
    var caught: Bool = true
    var style: Style = .full
    var foilPlaying: Bool = false

    enum Style { case mini, full }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tilt: CGSize = .zero

    var body: some View {
        switch style {
        case .mini: mini
        case .full: full
        }
    }

    // MARK: Mini

    private var mini: some View {
        VStack(spacing: 0) {
            HStack {
                Text(caught ? creature.name : "???")
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text("HP \(creature.life)")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
            }
            .padding(.horizontal, 7)
            .padding(.top, 6)

            artWindow
                .padding(.horizontal, 6)
                .padding(.vertical, 4)

            if caught {
                HStack(spacing: 0) {
                    miniStat("HP", creature.life)
                    miniStat("EN", creature.energy)
                    miniStat("ST", creature.strength)
                }
                .padding(.horizontal, 4)
            }

            Text(caught ? creature.requirement.deed : "Locked")
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
        }
        .background(paper, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(frameColor, lineWidth: caught ? 2 : 1)
        }
        .overlay {
            if caught, creature.rarity.hasFoil, foilPlaying, !reduceMotion {
                HoloFoil(rarity: creature.rarity, playing: true)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    // MARK: Full

    private var full: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(caught ? creature.name : "???")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                Spacer()
                Text("HP")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                Text("\(creature.life)")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.critical)
                Image(systemName: creature.typeGlyph)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(creature.rarity.color)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            artWindow
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .overlay {
                    if caught, creature.rarity.hasFoil, foilPlaying {
                        HoloFoil(rarity: creature.rarity, playing: !reduceMotion)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .padding(.horizontal, 10)
                            .padding(.top, 8)
                    }
                }

            HStack {
                Text(creature.typeName.uppercased())
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(creature.rarity.color.opacity(0.22), in: Capsule())
                Text(caught ? creature.rarity.label : "Unknown")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(creature.rarity.color)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            if caught {
                HStack(spacing: 0) {
                    stat("LIFE", creature.life, Theme.critical)
                    stat("ENERGY", creature.energy, Theme.warning)
                    stat("STR", creature.strength, Theme.accent)
                }
                .padding(.horizontal, 6)
                .padding(.top, 8)

                Text("NATURE · \(creature.nature.uppercased())")
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }

            Divider().padding(.horizontal, 12).padding(.top, 6)

            HStack(alignment: .firstTextBaseline) {
                Image(systemName: creature.typeGlyph)
                    .font(.system(size: 12, weight: .bold))
                Text(caught ? creature.ability : creature.requirement.deed)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(creature.strength)")
                    .font(.title3.weight(.bold).monospacedDigit())
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            if caught {
                Text(creature.flavor)
                    .font(.caption)
                    .italic()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            HStack {
                Text(creature.collectorNumber)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("RATION")
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.accent)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
        .background(paper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(frameColor, lineWidth: caught ? 3 : 1.2)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color.white.opacity(caught ? 0.22 : 0.06), lineWidth: 1)
                .padding(3)
        }
        .compositingGroup()
        .shadow(
            color: creature.rarity.color.opacity(caught ? 0.45 : 0),
            radius: creature.rarity >= .legendary ? 18 : 10, y: 5
        )
        .rotation3DEffect(
            .degrees(reduceMotion ? 0 : tilt.width * 0.12), axis: (x: 0, y: 1, z: 0)
        )
        .rotation3DEffect(
            .degrees(reduceMotion ? 0 : -tilt.height * 0.08), axis: (x: 1, y: 0, z: 0)
        )
        .onContinuousHover { phase in
            guard !reduceMotion else { return }
            switch phase {
            case .active(let point):
                tilt = CGSize(width: point.x - 120, height: point.y - 180)
            case .ended:
                withAnimation(.spring(duration: 0.4)) { tilt = .zero }
            }
        }
    }

    private func stat(_ label: String, _ value: Int, _ color: Color) -> some View {
        VStack(spacing: 1) {
            Text(label)
                .font(.system(size: 8, weight: .heavy, design: .rounded))
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.system(size: 14, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
    }

    private func miniStat(_ label: String, _ value: Int) -> some View {
        VStack(spacing: 0) {
            Text(label)
                .font(.system(size: 6, weight: .heavy, design: .rounded))
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.system(size: 9, weight: .heavy, design: .rounded).monospacedDigit())
        }
        .frame(maxWidth: .infinity)
    }

    private var artWindow: some View {
        CreaturePortrait(creature: creature, caught: caught)
            .padding(8)
            .frame(maxWidth: .infinity)
            .aspectRatio(1.15, contentMode: .fit)
            .background(
                LinearGradient(
                    colors: [
                        creature.rarity.color.opacity(caught ? 0.22 : 0.06),
                        Color.primary.opacity(0.06),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            }
    }

    private var paper: some ShapeStyle {
        LinearGradient(
            colors: [
                Color(
                    light: Color(red: 0.98, green: 0.96, blue: 0.92),
                    dark: Color(red: 0.20, green: 0.18, blue: 0.17)),
                Color(
                    light: Color(red: 0.93, green: 0.90, blue: 0.84),
                    dark: Color(red: 0.13, green: 0.12, blue: 0.11)),
            ],
            startPoint: .top, endPoint: .bottom)
    }

    private var frameColor: Color {
        caught ? creature.rarity.color : Color.primary.opacity(0.16)
    }
}

/// Rainbow foil plus a traveling shine. Plays on inspect, catch, and binder
/// tiles that have earned it.
struct HoloFoil: View {
    var rarity: CreatureRarity
    var playing: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: playing ? 1 / 24 : 10, paused: !playing)) {
            context in
            let t = context.date.timeIntervalSinceReferenceDate
            let travel = (sin(t * 0.7) + 1) / 2
            let spin = (t * 0.12).truncatingRemainder(dividingBy: 1)
            ZStack {
                AngularGradient(
                    colors: rarity.foilColors,
                    center: .center,
                    angle: .degrees(spin * 360)
                )
                .opacity(0.28)
                .blendMode(.overlay)
                LinearGradient(
                    colors: [.clear, Color.white.opacity(0.55), .clear],
                    startPoint: UnitPoint(x: travel - 0.22, y: 0),
                    endPoint: UnitPoint(x: travel + 0.22, y: 1)
                )
                .blendMode(.overlay)
            }
        }
        .allowsHitTesting(false)
    }
}

extension Creature {
    var typeName: String { requirement.typeName }
    var typeGlyph: String { requirement.typeGlyph }
}

extension UnlockRequirement {
    var typeName: String {
        switch self {
        case .anyUsage: "Spark"
        case .power: "Score"
        case .messages: "Prompt"
        case .sessions: "Window"
        case .cacheReads: "Cache"
        case .activeDays: "Heat"
        case .streak: "Streak"
        case .models: "Shift"
        case .providers: "Tool"
        case .nightOwl: "Night"
        case .singleDay: "Limit"
        case .earlyBird: "Dawn"
        case .dusk: "Dusk"
        case .cost: "Bill"
        }
    }

    var typeGlyph: String {
        switch self {
        case .anyUsage: "sparkle"
        case .power: "gauge.with.dots.needle.67percent"
        case .messages: "text.bubble.fill"
        case .sessions: "macwindow"
        case .cacheReads: "memorychip"
        case .activeDays: "calendar"
        case .streak: "flame.fill"
        case .models: "square.on.square"
        case .providers: "wrench.and.screwdriver"
        case .nightOwl: "moon.fill"
        case .singleDay: "square.stack.3d.up.fill"
        case .earlyBird: "sunrise.fill"
        case .dusk: "sunset.fill"
        case .cost: "dollarsign.circle.fill"
        }
    }

    /// What happened, or what still has to. Short enough for a binder tile.
    var deed: String {
        switch self {
        case .anyUsage: "First tokens"
        case .power(let n): "\(PowerFormat.compact(n)) Score"
        case .messages(let n): "\(n) messages"
        case .sessions(let n): "\(n) sessions"
        case .cacheReads(let n): "\(PowerFormat.compact(n)) cache"
        case .activeDays(let n): "\(n) days"
        case .streak(let n): "\(n)-day streak"
        case .models(let n): "\(n) models"
        case .providers(let n): "\(n) tools"
        case .nightOwl: "After 10pm"
        case .singleDay(let n): "\(PowerFormat.compact(n)) in one day"
        case .earlyBird: "Before 11am"
        case .dusk: "4–6pm"
        case .cost(let n): "$\(Int(n)) estimate"
        }
    }

    var hint: String {
        switch self {
        case .anyUsage: "Spend any tokens"
        case .power(let n): "Reach \(PowerFormat.compact(n)) Score"
        case .messages(let n): "Send \(n) messages"
        case .sessions(let n): "Log \(n) sessions"
        case .cacheReads(let n): "Read \(PowerFormat.compact(n)) cache tokens"
        case .activeDays(let n): "Use tokens on \(n) days"
        case .streak(let n): "Hold a \(n)-day streak"
        case .models(let n): "Use \(n) models"
        case .providers(let n): "Use \(n) tools"
        case .nightOwl: "Most tokens between 10pm and 5am"
        case .singleDay(let n): "\(PowerFormat.compact(n)) tokens in one day"
        case .earlyBird: "Most tokens between 6am and 11am"
        case .dusk: "Most tokens between 4pm and 7pm"
        case .cost(let n): "Reach a $\(Int(n)) usage estimate"
        }
    }
}

enum PowerFormat {
    static func compact(_ n: Int) -> String {
        switch n {
        case 1_000_000_000...:
            String(format: "%.1fB", Double(n) / 1_000_000_000)
        case 1_000_000...:
            String(format: "%.1fM", Double(n) / 1_000_000).replacingOccurrences(of: ".0", with: "")
        case 1_000...:
            String(format: "%.0fk", Double(n) / 1_000)
        default:
            "\(n)"
        }
    }
}
