import CLinuxTray
import Foundation
import RationKit

/// A trading-card face, drawn in Cairo.
///
/// Same anatomy as the macOS card: evolution line, illustration, species and
/// size, a Life / Energy / Power / Speed stat block, an ability on the higher
/// rarities, attacks with energy costs, and a weakness / resistance / retreat
/// footer. Card stock stays dark in both appearances — a card is an object,
/// not a panel.
enum CardFace {

    /// Mini cards fill the binder grid; the full face opens in the inspector.
    enum Style {
        case mini
        case full
    }

    // MARK: Palette

    /// The card's key colour: pips, stat bars, art window, ability rail.
    /// Tuned for dark stock, so these do not switch with the desktop theme.
    static func energyColor(_ energy: CreatureEnergy) -> RGBA {
        switch energy {
        case .ember: RGBA(0.894, 0.545, 0.416)
        case .signal: RGBA(0.373, 0.663, 0.882)
        case .cache: RGBA(0.310, 0.749, 0.545)
        case .cycle: RGBA(0.859, 0.667, 0.263)
        case .depth: RGBA(0.694, 0.514, 0.871)
        case .night: RGBA(0.553, 0.580, 0.878)
        case .alloy: RGBA(0.502, 0.769, 0.804)
        case .void: RGBA(0.882, 0.365, 0.302)
        }
    }

    static func rarityColor(_ rarity: CreatureRarity, palette: Palette) -> RGBA {
        switch rarity {
        case .common: RGBA(0.72, 0.72, 0.72)
        case .uncommon: RGBA(0.40, 0.82, 0.55)
        case .rare: RGBA(0.45, 0.65, 1.0)
        case .epic: RGBA(0.75, 0.50, 0.95)
        case .legendary: palette.warning
        case .mythic: palette.accent
        }
    }

    /// The mark printed next to the collector number.
    static func pipGlyph(_ rarity: CreatureRarity) -> String {
        switch rarity {
        case .common: "\u{25CF}"
        case .uncommon: "\u{25C6}"
        case .rare: "\u{2605}"
        case .epic: "\u{2726}"
        case .legendary: "\u{2739}"
        case .mythic: "\u{2735}"
        }
    }

    private static let white = RGBA(1, 1, 1)

    // MARK: Mini

    /// The binder tile: name, life, illustration, unlock deed, rarity pip.
    static func drawMini(
        _ creature: Creature, caught: Bool, in rect: Rect, on canvas: Canvas
    ) {
        let lore = creature.lore
        let key = caught ? energyColor(lore.energy) : RGBA(0.5, 0.5, 0.5)
        drawStock(rect, radius: 9, key: key, caught: caught, on: canvas)

        let inner = rect.inset(by: 5)
        canvas.text(
            canvas.truncated(
                caught ? creature.name : "???", size: 9, weight: .bold,
                maxWidth: inner.width - 20),
            at: Point(inner.x, inner.y), size: 9, weight: .bold, color: white)
        canvas.text(
            caught ? "\(lore.life)" : "??", at: Point(inner.maxX, inner.y), size: 9,
            weight: .bold, color: caught ? white : white.opacity(0.4), align: .trailing)

        let art = Rect(inner.x, inner.y + 13, inner.width, inner.width / 1.45)
        canvas.clipped(to: art, radius: 5) {
            CreatureArtwork.draw(lore.art, in: art, on: canvas, key: key, caught: caught)
        }
        canvas.strokeRounded(art, radius: 5, width: 1.5, key.opacity(0.55))

        let footer = art.maxY + 4
        drawEnergyPip(
            lore.energy, center: Point(inner.x + 4.5, footer + 4), size: 9,
            caught: caught, on: canvas)
        canvas.text(
            canvas.truncated(
                caught ? creature.requirement.deed : "Locked", size: 7,
                maxWidth: inner.width - 26),
            at: Point(inner.x + 12, footer), size: 7, color: white.opacity(0.62))
        canvas.text(
            pipGlyph(creature.rarity), at: Point(inner.maxX, footer), size: 7,
            color: caught
                ? rarityColor(creature.rarity, palette: canvas.palette)
                : white.opacity(0.25),
            align: .trailing)
    }

    /// Height a mini card occupies for a given column width.
    static func miniHeight(width: Double) -> Double {
        let inner = width - 10
        return 5 + 13 + inner / 1.45 + 4 + 11 + 5
    }

    // MARK: Full

    /// Draws the full face and returns the height it used.
    @discardableResult
    static func drawFull(
        _ creature: Creature, caught: Bool, in rect: Rect, on canvas: Canvas
    ) -> Double {
        let lore = creature.lore
        let key = caught ? energyColor(lore.energy) : RGBA(0.5, 0.5, 0.5)
        let height = fullHeight(creature, caught: caught, width: rect.width, on: canvas)
        let card = Rect(rect.x, rect.y, rect.width, height)
        drawStock(card, radius: 13, key: key, caught: caught, on: canvas)

        let inner = card.inset(by: 9)
        var y = inner.y

        // Header: evolution line, name, HP, energy pip.
        canvas.text(
            stageLine(creature, caught: caught), at: Point(inner.x, y), size: 7,
            color: white.opacity(0.55))
        canvas.text(
            canvas.truncated(
                caught ? creature.name : "???", size: 19, weight: .bold,
                maxWidth: inner.width - 78),
            at: Point(inner.x, y + 9), size: 19, weight: .bold, color: white)

        drawEnergyPip(
            lore.energy, center: Point(inner.maxX - 10, y + 18), size: 20, caught: caught,
            on: canvas)
        let lifeText = caught ? "\(lore.life)" : "??"
        let lifeWidth = canvas.width(lifeText, size: 19, weight: .bold)
        canvas.text(
            lifeText, at: Point(inner.maxX - 24, y + 9), size: 19, weight: .bold, color: white,
            align: .trailing)
        canvas.text(
            "HP", at: Point(inner.maxX - 26 - lifeWidth, y + 17), size: 8, weight: .bold,
            color: white.opacity(0.55), align: .trailing)
        y += 34

        // Illustration.
        let art = Rect(inner.x, y, inner.width, inner.width / 1.95)
        canvas.clipped(to: art, radius: 6) {
            CreatureArtwork.draw(lore.art, in: art, on: canvas, key: key, caught: caught)
        }
        canvas.strokeRounded(art, radius: 6, width: 2, key.opacity(0.55))
        y = art.maxY + 4

        // Species and size.
        let strip = Rect(inner.x, y, inner.width, 15)
        canvas.fillRounded(strip, radius: 3, white.opacity(0.06))
        canvas.text(
            canvas.truncated(
                caught ? lore.species : "Unidentified", size: 8, maxWidth: strip.width - 100),
            at: Point(strip.x + 6, strip.y + 2), size: 8, color: white.opacity(0.68))
        canvas.text(
            caught ? lore.size : "— m · — kg", at: Point(strip.maxX - 6, strip.y + 2), size: 7,
            color: white.opacity(0.68), align: .trailing)
        y = strip.maxY + 6

        // Stat block.
        let stats: [(String, Int, Double)] = [
            ("ENERGY", lore.energyCost, Double(lore.energyCost) / 9),
            ("LIFE", lore.life, Double(lore.life) / 300),
            ("POWER", lore.power, Double(lore.power) / 240),
            ("SPEED", lore.speed, Double(lore.speed) / 100),
        ]
        let statWidth = (inner.width - 24) / 4
        for (index, stat) in stats.enumerated() {
            let x = inner.x + Double(index) * (statWidth + 8)
            canvas.text(stat.0, at: Point(x, y), size: 6, color: white.opacity(0.5))
            canvas.text(
                caught ? "\(stat.1)" : "—", at: Point(x, y + 8), size: 13, weight: .bold,
                color: white)
            let bar = Rect(x, y + 25, statWidth, 2.5)
            canvas.fillRounded(bar, radius: 1.25, white.opacity(0.12))
            if caught {
                canvas.fillRounded(
                    Rect(bar.x, bar.y, bar.width * max(0.04, min(1, stat.2)), bar.height),
                    radius: 1.25, key)
            }
        }
        y += 34

        // Ability, on the higher rarities.
        if caught, let ability = lore.ability {
            let text = canvas.wrapped(ability.text, size: 8, maxWidth: inner.width - 14)
            let block = Rect(
                inner.x, y, inner.width, 20 + Double(text.count) * 11)
            canvas.fillRounded(block, radius: 4, key.opacity(0.14))
            canvas.fill(Rect(block.x, block.y, 2, block.height), key)

            let badge = Rect(block.x + 6, block.y + 4, 34, 10)
            canvas.fillRounded(badge, radius: 2, key)
            canvas.text(
                "ABILITY", at: Point(badge.midX, badge.y + 0.5), size: 6, weight: .bold,
                color: RGBA(0, 0, 0, 0.85), align: .center)
            canvas.text(
                ability.name, at: Point(badge.maxX + 5, block.y + 2), size: 11, weight: .bold,
                color: white)
            var textY = block.y + 17
            for line in text {
                canvas.text(
                    line, at: Point(block.x + 6, textY), size: 8, color: white.opacity(0.66))
                textY += 11
            }
            y = block.maxY + 5
        }

        if caught {
            for attack in lore.attacks {
                let pips = max(1, attack.energyCost)
                for index in 0..<pips {
                    drawEnergyPip(
                        lore.energy, center: Point(inner.x + 5 + Double(index) * 11, y + 6),
                        size: 10, caught: true, on: canvas)
                }
                let nameX = inner.x + Double(pips) * 11 + 4
                let damage = "\(attack.damage)"
                let damageWidth = canvas.width(damage, size: 14, weight: .bold)
                canvas.text(
                    canvas.truncated(
                        attack.name, size: 12, weight: .bold,
                        maxWidth: inner.width - (nameX - inner.x) - damageWidth - 6),
                    at: Point(nameX, y), size: 12, weight: .bold, color: white)
                canvas.text(
                    damage, at: Point(inner.maxX, y - 1), size: 14, weight: .bold, color: white,
                    align: .trailing)
                y += 16
                if !attack.text.isEmpty {
                    y += canvas.paragraph(
                        attack.text, at: Point(inner.x, y), width: inner.width, size: 8,
                        color: white.opacity(0.6), lineSpacing: 1)
                    y += 2
                }
                canvas.fill(Rect(inner.x, y + 2, inner.width, 1), white.opacity(0.09))
                y += 7
            }
        } else {
            y += canvas.paragraph(
                creature.requirement.hint, at: Point(inner.x, y + 4), width: inner.width,
                size: 9, color: white.opacity(0.55))
            y += 10
        }

        // Unlock strip.
        let unlock = Rect(inner.x, y, inner.width, 15)
        canvas.fillRounded(unlock, radius: 4, white.opacity(0.05))
        canvas.circle(center: Point(unlock.x + 8, unlock.midY), radius: 2, key)
        canvas.text(
            canvas.truncated(
                "UNLOCK · \(creature.requirement.deed.uppercased())", size: 7,
                maxWidth: unlock.width - 20),
            at: Point(unlock.x + 14, unlock.y + 3), size: 7, color: white.opacity(0.72))
        y = unlock.maxY + 5

        if caught {
            y += canvas.paragraph(
                creature.flavor, at: Point(inner.x, y), width: inner.width, size: 8,
                color: white.opacity(0.55), lineSpacing: 1)
            y += 4
        }

        // Weakness / resistance / retreat.
        canvas.fill(Rect(inner.x, y, inner.width, 1), white.opacity(0.09))
        y += 5
        let cell = inner.width / 3
        canvas.text("WEAKNESS", at: Point(inner.x, y), size: 5.5, color: white.opacity(0.5))
        drawEnergyPip(
            lore.energy.weakness, center: Point(inner.x + 5, y + 13), size: 9, caught: caught,
            on: canvas)
        canvas.text("×2", at: Point(inner.x + 13, y + 9), size: 7, color: white.opacity(0.75))

        canvas.text(
            "RESISTANCE", at: Point(inner.x + cell, y), size: 5.5, color: white.opacity(0.5))
        drawEnergyPip(
            lore.energy.resistance, center: Point(inner.x + cell + 5, y + 13), size: 9,
            caught: caught, on: canvas)
        canvas.text(
            "−20", at: Point(inner.x + cell + 13, y + 9), size: 7, color: white.opacity(0.75))

        canvas.text(
            "RETREAT", at: Point(inner.x + cell * 2, y), size: 5.5, color: white.opacity(0.5))
        for index in 0..<CreatureLore.retreat(for: creature.rarity) {
            canvas.circle(
                center: Point(inner.x + cell * 2 + 5 + Double(index) * 10, y + 13), radius: 4,
                white.opacity(0.28))
        }
        y += 22

        canvas.text(
            creature.collectorNumber, at: Point(inner.x, y), size: 8, weight: .medium,
            color: white.opacity(0.55))
        canvas.text(
            creature.rarity.label.uppercased(),
            at: Point(inner.x + canvas.width(creature.collectorNumber, size: 8) + 6, y + 0.5),
            size: 7, weight: .bold, color: rarityColor(creature.rarity, palette: canvas.palette))
        canvas.text(
            "RATION", at: Point(inner.maxX, y), size: 8, weight: .bold,
            color: canvas.palette.accent, align: .trailing)

        return height
    }

    /// Measures the full face so the inspector can lay itself out first.
    static func fullHeight(
        _ creature: Creature, caught: Bool, width: Double, on canvas: Canvas
    ) -> Double {
        let lore = creature.lore
        let inner = width - 18
        var height = 9.0 + 34  // padding + header
        height += inner / 1.95 + 4  // art
        height += 15 + 6  // species strip
        height += 34  // stats

        if caught, let ability = lore.ability {
            let lines = canvas.wrapped(ability.text, size: 8, maxWidth: inner - 14)
            height += 20 + Double(lines.count) * 11 + 5
        }

        if caught {
            for attack in lore.attacks {
                height += 16
                if !attack.text.isEmpty {
                    let lines = canvas.wrapped(attack.text, size: 8, maxWidth: inner)
                    height += Double(lines.count) * (canvas.lineHeight(size: 8) + 1) + 2
                }
                height += 7
            }
        } else {
            let lines = canvas.wrapped(creature.requirement.hint, size: 9, maxWidth: inner)
            height += Double(lines.count) * (canvas.lineHeight(size: 9) + 2) + 14
        }

        height += 15 + 5  // unlock strip
        if caught {
            let lines = canvas.wrapped(creature.flavor, size: 8, maxWidth: inner)
            height += Double(lines.count) * (canvas.lineHeight(size: 8) + 1) + 4
        }
        height += 1 + 5 + 22 + 12  // footer rule, stats row, collector line
        return height + 9
    }

    // MARK: Pieces

    private static func stageLine(_ creature: Creature, caught: Bool) -> String {
        guard caught else { return "LOCKED · \(creature.collectorNumber)" }
        let lore = creature.lore
        switch lore.stage {
        case .basic:
            return "BASIC"
        default:
            let from = lore.evolvesFrom.map { " · EVOLVES FROM \($0.uppercased())" } ?? ""
            return lore.stage.label.uppercased() + from
        }
    }

    /// Dark card stock with a key-coloured wash across the top-left, and a
    /// rarity-coloured edge.
    private static func drawStock(
        _ rect: Rect, radius: Double, key: RGBA, caught: Bool, on canvas: Canvas
    ) {
        let cr = canvas.cr
        canvas.roundedPath(rect, radius: radius)
        if let stock = cairo_pattern_create_linear(0, rect.y, 0, rect.maxY) {
            cairo_pattern_add_color_stop_rgba(stock, 0, 0.13, 0.11, 0.10, 1)
            cairo_pattern_add_color_stop_rgba(stock, 1, 0.09, 0.08, 0.07, 1)
            cairo_set_source(cr, stock)
            cairo_fill_preserve(cr)
            cairo_pattern_destroy(stock)
        } else {
            canvas.setColor(RGBA(0.11, 0.10, 0.09))
            cairo_fill_preserve(cr)
        }
        if let wash = cairo_pattern_create_linear(rect.x, rect.y, rect.maxX, rect.maxY) {
            cairo_pattern_add_color_stop_rgba(
                wash, 0, key.r, key.g, key.b, caught ? 0.16 : 0.04)
            cairo_pattern_add_color_stop_rgba(wash, 1, key.r, key.g, key.b, 0)
            cairo_set_source(cr, wash)
            cairo_fill(cr)
            cairo_pattern_destroy(wash)
        } else {
            cairo_new_path(cr)
        }
    }

    /// An energy pip: the type's glyph on a coloured disc.
    static func drawEnergyPip(
        _ energy: CreatureEnergy, center: Point, size: Double, caught: Bool, on canvas: Canvas
    ) {
        let color = energyColor(energy).opacity(caught ? 1 : 0.4)
        let cr = canvas.cr
        if let fill = cairo_pattern_create_radial(
            center.x - size * 0.16, center.y - size * 0.22, 0, center.x, center.y, size / 2)
        {
            cairo_pattern_add_color_stop_rgba(fill, 0, 1, 1, 1, caught ? 0.6 : 0.25)
            cairo_pattern_add_color_stop_rgba(fill, 1, color.r, color.g, color.b, color.a)
            cairo_new_sub_path(cr)
            cairo_arc(cr, center.x, center.y, size / 2, 0, 2 * Double.pi)
            cairo_set_source(cr, fill)
            cairo_fill(cr)
            cairo_pattern_destroy(fill)
        } else {
            canvas.circle(center: center, radius: size / 2, color)
        }
        canvas.ring(center: center, radius: size / 2, width: 1, color)
        canvas.text(
            energy.glyph, at: Point(center.x, center.y - size * 0.36), size: size * 0.5,
            weight: .bold, color: RGBA(0, 0, 0, 0.8), align: .center)
    }
}
