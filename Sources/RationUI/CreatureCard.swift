import RationKit
import SwiftUI

/// A full trading-card face: evolution line, illustration, species and size,
/// a Life / Energy / Power / Speed stat block, an ability on the higher
/// rarities, attacks with energy costs, and a weakness/resistance/retreat
/// footer. The card stock stays dark in both appearances — a card is an
/// object, not a panel.
struct CreatureCard: View {
    let creature: Creature
    var caught: Bool = true
    var style: Style = .full
    var foilPlaying: Bool = false

    enum Style { case mini, full }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tilt: CGSize = .zero

    private var lore: CreatureLore { creature.lore }
    private var key: Color { caught ? lore.energy.color : Color(white: 0.5) }

    var body: some View {
        switch style {
        case .mini: mini
        case .full: full
        }
    }

    // MARK: Mini

    private var mini: some View {
        VStack(spacing: 3) {
            HStack(spacing: 3) {
                Text(caught ? creature.name : "???")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                Text(caught ? "\(lore.life)" : "??")
                    .font(.system(size: 10, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(caught ? .white : Color.white.opacity(0.4))
            }

            artWindow(corner: 5, border: 1.5, aspect: 1.45)

            HStack(spacing: 3) {
                energyPip(lore.energy, size: 9)
                Text(caught ? creature.requirement.deed : "Locked")
                    .font(.system(size: 7.5, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(Color.white.opacity(0.62))
                Spacer(minLength: 0)
                Text(creature.rarity.pipGlyph)
                    .font(.system(size: 7))
                    .foregroundStyle(caught ? creature.rarity.color : Color.white.opacity(0.25))
            }
        }
        .padding(5)
        .foregroundStyle(.white)
        .background(stock(corner: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(edge, lineWidth: caught ? 1.5 : 1)
        }
        .overlay {
            if caught, creature.rarity.hasFoil, foilPlaying, !reduceMotion {
                HoloFoil(rarity: creature.rarity, playing: true)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
        }
    }

    // MARK: Full

    private var full: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            artWindow(corner: 6, border: 2, aspect: 1.95)
            speciesStrip
            statBlock
            if caught, let ability = lore.ability {
                abilityBlock(ability)
            }
            if caught {
                attacks
            } else {
                lockedNote
            }
            unlockStrip
            if caught {
                Text(creature.flavor)
                    .font(.system(size: 8))
                    .italic()
                    .foregroundStyle(Color.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            footer
        }
        .padding(9)
        .foregroundStyle(.white)
        .background(stock(corner: 13))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(edge, lineWidth: caught ? 2 : 1)
        }
        .overlay {
            if caught, creature.rarity.hasFoil, foilPlaying {
                HoloFoil(rarity: creature.rarity, playing: !reduceMotion)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
        }
        .compositingGroup()
        .shadow(
            color: creature.rarity.color.opacity(caught ? 0.4 : 0),
            radius: creature.rarity >= .legendary ? 18 : 10, y: 5
        )
        .rotation3DEffect(
            .degrees(reduceMotion ? 0 : tilt.width * 0.1), axis: (x: 0, y: 1, z: 0)
        )
        .rotation3DEffect(
            .degrees(reduceMotion ? 0 : -tilt.height * 0.06), axis: (x: 1, y: 0, z: 0)
        )
        .onContinuousHover { phase in
            guard !reduceMotion else { return }
            switch phase {
            case .active(let point):
                tilt = CGSize(width: point.x - 140, height: point.y - 200)
            case .ended:
                withAnimation(.spring(duration: 0.4)) { tilt = .zero }
            }
        }
    }

    // MARK: Pieces

    private var header: some View {
        HStack(alignment: .lastTextBaseline, spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(stageLine)
                    .font(.system(size: 7, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(caught ? creature.name : "???")
                    .font(.system(size: 21, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Spacer(minLength: 0)
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("HP")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.55))
                Text(caught ? "\(lore.life)" : "??")
                    .font(.system(size: 21, weight: .heavy, design: .rounded).monospacedDigit())
                energyPip(lore.energy, size: 20)
            }
        }
    }

    private var stageLine: String {
        guard caught else { return "LOCKED · \(creature.collectorNumber)" }
        switch lore.stage {
        case .basic:
            return "BASIC"
        default:
            let from = lore.evolvesFrom.map { " · EVOLVES FROM \($0.uppercased())" } ?? ""
            return lore.stage.label.uppercased() + from
        }
    }

    private func artWindow(corner: CGFloat, border: CGFloat, aspect: CGFloat) -> some View {
        CreaturePortrait(creature: creature, caught: caught)
            .padding(2)
            .frame(maxWidth: .infinity)
            .aspectRatio(aspect, contentMode: .fit)
            .background {
                RadialGradient(
                    colors: [key.opacity(caught ? 0.22 : 0.08), Color.black.opacity(0.72)],
                    center: UnitPoint(x: 0.5, y: 0.06),
                    startRadius: 0, endRadius: 150
                )
            }
            .overlay {
                LinearGradient(
                    colors: [Color.white.opacity(0.12), .clear],
                    startPoint: .topTrailing, endPoint: .center
                )
                .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(key.opacity(0.55), lineWidth: border)
            }
    }

    private var speciesStrip: some View {
        HStack(spacing: 6) {
            Text(caught ? lore.species : "Unidentified")
                .font(.system(size: 8))
                .italic()
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(caught ? lore.size : "— m · — kg")
                .font(.system(size: 7, weight: .medium, design: .monospaced))
        }
        .foregroundStyle(Color.white.opacity(0.68))
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 3))
    }

    private var statBlock: some View {
        HStack(alignment: .top, spacing: 8) {
            statCell("ENERGY", lore.energyCost, Double(lore.energyCost) / 9)
            statCell("LIFE", lore.life, Double(lore.life) / 300)
            statCell("POWER", lore.power, Double(lore.power) / 240)
            statCell("SPEED", lore.speed, Double(lore.speed) / 100)
        }
        .padding(.vertical, 3)
    }

    private func statCell(_ label: String, _ value: Int, _ fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 6, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.5))
            Text(caught ? "\(value)" : "—")
                .font(.system(size: 13, weight: .heavy, design: .rounded).monospacedDigit())
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule()
                    .fill(key)
                    .scaleEffect(x: caught ? max(0.04, min(1, fraction)) : 0, anchor: .leading)
            }
            .frame(height: 2.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func abilityBlock(_ ability: CreatureAbility) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 5) {
                Text("ABILITY")
                    .font(.system(size: 6, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.black.opacity(0.85))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(key, in: RoundedRectangle(cornerRadius: 2))
                Text(ability.name)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
            }
            Text(ability.text)
                .font(.system(size: 8))
                .foregroundStyle(Color.white.opacity(0.66))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(key.opacity(0.14), in: RoundedRectangle(cornerRadius: 4))
        .overlay(alignment: .leading) { Rectangle().fill(key).frame(width: 2) }
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var attacks: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(lore.attacks.enumerated()), id: \.offset) { _, attack in
                attackRow(attack)
            }
        }
    }

    private func attackRow(_ attack: CreatureAttack) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                HStack(spacing: 2) {
                    ForEach(0..<max(1, attack.energyCost), id: \.self) { _ in
                        energyPip(lore.energy, size: 10)
                    }
                }
                Text(attack.name)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                Text("\(attack.damage)")
                    .font(.system(size: 14, weight: .heavy, design: .rounded).monospacedDigit())
            }
            if !attack.text.isEmpty {
                Text(attack.text)
                    .font(.system(size: 8))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, 4)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.09)).frame(height: 1)
        }
    }

    private var lockedNote: some View {
        Text(creature.requirement.hint)
            .font(.system(size: 9))
            .foregroundStyle(Color.white.opacity(0.55))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
    }

    private var unlockStrip: some View {
        HStack(spacing: 5) {
            Circle().fill(key).frame(width: 4, height: 4)
            Text("UNLOCK · \(creature.requirement.deed.uppercased())")
                .font(.system(size: 7, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 4))
    }

    private var footer: some View {
        VStack(spacing: 4) {
            HStack(alignment: .top, spacing: 4) {
                footerCell("WEAKNESS") {
                    HStack(spacing: 3) {
                        energyPip(lore.energy.weakness, size: 9)
                        Text("×2").font(.system(size: 7, design: .monospaced))
                    }
                }
                footerCell("RESISTANCE") {
                    HStack(spacing: 3) {
                        energyPip(lore.energy.resistance, size: 9)
                        Text("−20").font(.system(size: 7, design: .monospaced))
                    }
                }
                footerCell("RETREAT") {
                    HStack(spacing: 2) {
                        ForEach(0..<CreatureLore.retreat(for: creature.rarity), id: \.self) { _ in
                            Circle()
                                .fill(Color.white.opacity(0.28))
                                .frame(width: 8, height: 8)
                        }
                    }
                }
            }
            .padding(.top, 4)
            .overlay(alignment: .top) {
                Rectangle().fill(Color.white.opacity(0.09)).frame(height: 1)
            }

            HStack(spacing: 6) {
                Text(creature.collectorNumber)
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                Text(creature.rarity.label.uppercased())
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(creature.rarity.color)
                Spacer(minLength: 0)
                Text("RATION")
                    .font(.system(size: 8, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.accent)
            }
            .foregroundStyle(Color.white.opacity(0.55))
        }
    }

    private func footerCell<Content: View>(
        _ label: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 5.5, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.5))
            content()
                .foregroundStyle(Color.white.opacity(0.75))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func energyPip(_ energy: CreatureEnergy, size: CGFloat) -> some View {
        Text(energy.glyph)
            .font(.system(size: size * 0.5, weight: .bold))
            .foregroundStyle(Color.black.opacity(0.8))
            .frame(width: size, height: size)
            .background {
                Circle().fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.6), energy.color],
                        center: UnitPoint(x: 0.34, y: 0.28),
                        startRadius: 0, endRadius: size))
            }
            .overlay { Circle().strokeBorder(energy.color, lineWidth: 1) }
            .opacity(caught ? 1 : 0.4)
    }

    // MARK: Stock

    private func stock(corner: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.13, green: 0.11, blue: 0.10),
                        Color(red: 0.09, green: 0.08, blue: 0.07),
                    ],
                    startPoint: .top, endPoint: .bottom)
            )
            .overlay {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [key.opacity(caught ? 0.16 : 0.04), .clear],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
            }
    }

    private var edge: Color {
        caught ? creature.rarity.color.opacity(0.75) : Color.white.opacity(0.14)
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
