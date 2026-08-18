import RationKit
import SwiftUI

/// A collectible card: illustration, name, rarity, collector number.
///
/// Mini is the binder tile — no foil. Full is the inspect/catch object, and
/// the only place a holofoil is allowed to move.
struct CreatureCard: View {
    let creature: Creature
    var caught: Bool = true
    var style: Style = .full
    var foilPlaying: Bool = false

    enum Style { case mini, full }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        switch style {
        case .mini: mini
        case .full: full
        }
    }

    private var mini: some View {
        VStack(spacing: 4) {
            CreaturePortrait(creature: creature, caught: caught)
                .frame(minHeight: 72)
                .padding(.horizontal, 8)
                .padding(.top, 8)
            Text(caught ? creature.name : "Locked")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Text(creature.requirement.deed)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 4)
                .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity)
        .background(paper, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(frameColor, lineWidth: caught ? 1.5 : 1)
        }
    }

    private var full: some View {
        VStack(alignment: .leading, spacing: 0) {
            CreaturePortrait(creature: creature, caught: caught)
                .padding(18)
                .frame(maxWidth: .infinity)
                .aspectRatio(1.05, contentMode: .fit)

            Text(caught ? creature.name : "Locked")
                .font(.title3.weight(.semibold))
                .padding(.horizontal, 14)

            Text(creature.requirement.deed)
                .font(.caption.weight(.medium))
                .foregroundStyle(caught ? creature.rarity.color : .secondary)
                .padding(.horizontal, 14)
                .padding(.top, 2)

            if caught {
                Text(creature.flavor)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 10)

            Text(creature.collectorNumber)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
        }
        .background(paper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(frameColor, lineWidth: caught && creature.rarity >= .rare ? 2 : 1.2)
        }
        .overlay {
            if caught, creature.rarity.hasFoil, foilPlaying {
                HoloFoil(rarity: creature.rarity, playing: !reduceMotion)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .shadow(
            color: creature.rarity.color.opacity(caught ? 0.28 : 0),
            radius: creature.rarity >= .legendary ? 16 : 8, y: 4)
    }

    private var paper: some ShapeStyle {
        Color.primary.opacity(0.05)
    }

    private var frameColor: Color {
        caught ? creature.rarity.color.opacity(0.9) : Color.primary.opacity(0.16)
    }
}

/// Close-up material only. Never drawn on binder tiles.
struct HoloFoil: View {
    var rarity: CreatureRarity
    var playing: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: playing ? 1 / 24 : 10, paused: !playing)) {
            context in
            let t = context.date.timeIntervalSinceReferenceDate
            let travel = (sin(t * 0.55) + 1) / 2
            LinearGradient(
                colors: [.clear, Color.white.opacity(0.38), .clear],
                startPoint: UnitPoint(x: travel - 0.18, y: 0),
                endPoint: UnitPoint(x: travel + 0.18, y: 1)
            )
            .blendMode(.overlay)
        }
        .allowsHitTesting(false)
    }
}

extension UnlockRequirement {
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
