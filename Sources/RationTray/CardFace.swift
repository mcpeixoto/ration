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

    /// The colour a card is drawn in: its energy, spun around the wheel if it is shiny.
    ///
    /// The illustration is already keyed off one colour, so a shiny costs nothing extra
    /// to draw and is different everywhere at once — art, pips, stat bars, window.
    static func keyColor(_ energy: CreatureEnergy, shiny: Bool) -> RGBA {
        let base = energyColor(energy)
        return shiny ? base.hueRotated(by: CompanionBalance.shinyHueShift) : base
    }

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

    private static let white = RGBA(1, 1, 1)

    /// The colours a rarity's holofoil cycles through, as on the Mac.
    static func foilColors(_ rarity: CreatureRarity) -> [RGBA] {
        switch rarity {
        case .common: [RGBA(1, 1, 1, 0.2)]
        case .uncommon:
            [
                RGBA(0.20, 0.78, 0.35), RGBA(0.35, 0.90, 0.70), white, RGBA(0.20, 0.78, 0.35),
            ]
        case .rare:
            [
                RGBA(0.20, 0.45, 0.95), RGBA(0.30, 0.85, 0.95), white, RGBA(0.29, 0.22, 0.72),
                RGBA(0.20, 0.45, 0.95),
            ]
        case .epic:
            [
                RGBA(0.65, 0.30, 0.85), RGBA(0.95, 0.45, 0.75), white, RGBA(0.29, 0.22, 0.72),
                RGBA(0.65, 0.30, 0.85),
            ]
        case .legendary:
            [
                RGBA(0.98, 0.85, 0.20), RGBA(0.98, 0.60, 0.15), white, RGBA(0.35, 0.90, 0.70),
                RGBA(0.98, 0.85, 0.20),
            ]
        case .mythic:
            [
                RGBA(0.894, 0.545, 0.416), RGBA(0.98, 0.60, 0.15), RGBA(0.98, 0.85, 0.20),
                RGBA(0.35, 0.90, 0.70), RGBA(0.30, 0.85, 0.95), RGBA(0.65, 0.30, 0.85),
                RGBA(0.894, 0.545, 0.416),
            ]
        }
    }

    /// Whether the card carries a moving foil. Common is printed; the rest shine.
    static func hasFoil(_ rarity: CreatureRarity) -> Bool {
        rarity >= .uncommon
    }

    /// Draws the holographic layer over a card that has already been painted.
    ///
    /// Two passes, both in overlay so they tint what is underneath instead of
    /// covering it: a slowly turning wheel of the rarity's colours, and a white
    /// band that travels across the face. Cairo has no angular gradient, so the
    /// wheel is drawn as wedges — enough of them that the seams disappear.
    ///
    /// Weaker than the macOS values it is copied from. SwiftUI blends the foil
    /// inside the card's own compositing group; Cairo blends it against the
    /// finished pixels, which lands heavier for the same numbers, and a card
    /// you cannot see the illustration through is not shiny, it is fogged.
    static func drawFoil(
        _ rarity: CreatureRarity, in rect: Rect, radius: Double, phase: Double, on canvas: Canvas
    ) {
        guard hasFoil(rarity) else { return }
        let cr = canvas.cr
        let colors = foilColors(rarity)
        guard colors.count > 1 else { return }

        cairo_save(cr)
        canvas.roundedPath(rect, radius: radius)
        cairo_clip(cr)
        cairo_set_operator(cr, 16)  // CAIRO_OPERATOR_OVERLAY

        let spin = (phase * 0.12).truncatingRemainder(dividingBy: 1)
        let wedges = 48
        let centre = rect.center
        let reach = (rect.width + rect.height)
        for index in 0..<wedges {
            let start = Double(index) / Double(wedges)
            let end = Double(index + 1) / Double(wedges)
            let color = colorAround(colors, at: (start + spin).truncatingRemainder(dividingBy: 1))
            canvas.setColor(color.opacity(0.10))
            cairo_move_to(cr, centre.x, centre.y)
            cairo_arc(
                cr, centre.x, centre.y, reach, start * 2 * Double.pi - Double.pi / 2,
                end * 2 * Double.pi - Double.pi / 2)
            cairo_close_path(cr)
            cairo_fill(cr)
        }

        // The travelling highlight, diagonal like the Mac's.
        let travel = (sin(phase * 0.7) + 1) / 2
        let x0 = rect.x + rect.width * (travel - 0.22)
        let x1 = rect.x + rect.width * (travel + 0.22)
        if let band = cairo_pattern_create_linear(x0, rect.y, x1, rect.maxY) {
            cairo_pattern_add_color_stop_rgba(band, 0, 1, 1, 1, 0)
            cairo_pattern_add_color_stop_rgba(band, 0.5, 1, 1, 1, 0.22)
            cairo_pattern_add_color_stop_rgba(band, 1, 1, 1, 1, 0)
            cairo_set_source(cr, band)
            cairo_rectangle(cr, rect.x, rect.y, rect.width, rect.height)
            cairo_fill(cr)
            cairo_pattern_destroy(band)
        }

        cairo_set_operator(cr, 2)  // back to OVER
        cairo_restore(cr)
    }

    /// Samples a looping list of colours, blending between neighbours.
    private static func colorAround(_ colors: [RGBA], at position: Double) -> RGBA {
        let count = colors.count
        let scaled = position * Double(count)
        let index = Int(scaled) % count
        let next = (index + 1) % count
        return colors[index].mixed(with: colors[next], amount: scaled - scaled.rounded(.down))
    }

    // MARK: Mini

    /// The binder tile: name, life, illustration, unlock deed, rarity pip.
    static func drawMini(
        _ creature: Creature, caught: Bool, in rect: Rect, on canvas: Canvas,
        foilPhase: Double? = nil, shiny: Bool = false, archived: Bool = false
    ) {
        let lore = creature.lore
        let key = caught ? keyColor(lore.energy, shiny: shiny) : RGBA(0.5, 0.5, 0.5)
        drawStock(rect, radius: 9, key: key, caught: caught, on: canvas)

        let inner = rect.inset(by: 5)
        let title = canvas.truncated(
            caught ? creature.name : "???", size: 9, weight: .bold,
            maxWidth: inner.width - (shiny ? 30 : 20))
        canvas.text(title, at: Point(inner.x, inner.y), size: 9, weight: .bold, color: white)
        if caught, shiny {
            drawShinyMark(
                center: Point(
                    inner.x + canvas.width(title, size: 9, weight: .bold) + 5, inner.y + 5),
                size: 7, color: white, on: canvas)
        }
        canvas.text(
            caught ? "\(lore.life)" : "??", at: Point(inner.maxX, inner.y), size: 9,
            weight: .bold, color: caught ? white : white.opacity(0.4), align: .trailing)

        let art = Rect(inner.x, inner.y + 13, inner.width, inner.width / 1.45)
        canvas.clipped(to: art, radius: 5) {
            CreatureArtwork.draw(lore.art, in: art, on: canvas, key: key, caught: caught)
        }
        canvas.strokeRounded(art, radius: 5, width: 1.5, key.opacity(0.55))

        // Unlocked under the old threshold model. Marked rather than dimmed — dimming
        // would read as locked, and these are cards somebody already owns. It sits on
        // the illustration because the header row is spoken for by the name and the HP.
        if archived {
            let tag = Rect(art.x + 4, art.maxY - 15, 38, 11)
            canvas.fillRounded(tag, radius: 3, RGBA(0, 0, 0, 0.6))
            canvas.text(
                "SET 01", at: Point(tag.midX, tag.y + 2), size: 6.5, weight: .bold,
                color: RGBA(1, 1, 1, 0.8), align: .center)
        }

        let footer = art.maxY + 4
        drawEnergyPip(
            lore.energy, center: Point(inner.x + 4.5, footer + 4), size: 9,
            caught: caught, on: canvas)
        canvas.text(
            canvas.truncated(
                caught ? creature.requirement.deed : "Locked", size: 7,
                maxWidth: inner.width - 26),
            at: Point(inner.x + 12, footer), size: 7, color: white.opacity(0.62))
        drawRarityPip(
            creature.rarity, center: Point(inner.maxX - 3.5, footer + 4), size: 7,
            color: caught
                ? rarityColor(creature.rarity, palette: canvas.palette) : white.opacity(0.25),
            on: canvas)

        if caught, let foilPhase, shiny || hasFoil(creature.rarity) {
            drawFoil(
                shiny ? max(creature.rarity, .rare) : creature.rarity, in: rect, radius: 9,
                phase: foilPhase, on: canvas)
        }
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
        _ creature: Creature, caught: Bool, in rect: Rect, on canvas: Canvas,
        foilPhase: Double? = nil, shiny: Bool = false
    ) -> Double {
        let lore = creature.lore
        let key = caught ? keyColor(lore.energy, shiny: shiny) : RGBA(0.5, 0.5, 0.5)
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
        let rarityLabel =
            shiny
            ? "\(creature.rarity.label.uppercased()) · SHINY" : creature.rarity.label.uppercased()
        canvas.text(
            rarityLabel,
            at: Point(inner.x + canvas.width(creature.collectorNumber, size: 8) + 6, y + 0.5),
            size: 7, weight: .bold, color: rarityColor(creature.rarity, palette: canvas.palette))
        canvas.text(
            "RATION", at: Point(inner.maxX, y), size: 8, weight: .bold,
            color: canvas.palette.accent, align: .trailing)

        // A shiny always shimmers, whatever its rarity — that is most of what makes a
        // shiny common worth keeping.
        if caught, let foilPhase, shiny || hasFoil(creature.rarity) {
            drawFoil(
                shiny ? max(creature.rarity, .rare) : creature.rarity, in: card, radius: 13,
                phase: foilPhase, on: canvas)
        }

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

    /// The mark inside an energy pip, drawn rather than typed.
    ///
    /// `CreatureEnergy.glyph` names a geometric character — ▲ ◉ ▣ ⟳ ◆ ☽ ⬢ ✕ —
    /// and the desktop's UI font is under no obligation to have it. Ubuntu Sans
    /// does not, and every pip on the card came out as a tofu box. These are
    /// the same eight marks, as paths.
    private static func drawEnergyMark(
        _ energy: CreatureEnergy, center: Point, size: Double, on canvas: Canvas
    ) {
        let cr = canvas.cr
        let r = size * 0.3
        canvas.setColor(RGBA(0, 0, 0, 0.8))
        cairo_set_line_width(cr, max(size * 0.09, 0.8))
        cairo_set_line_cap(cr, 1)
        cairo_set_line_join(cr, 1)

        switch energy {
        case .ember:  // ▲
            cairo_move_to(cr, center.x, center.y - r)
            cairo_line_to(cr, center.x + r * 0.92, center.y + r * 0.75)
            cairo_line_to(cr, center.x - r * 0.92, center.y + r * 0.75)
            cairo_close_path(cr)
            cairo_fill(cr)
        case .signal:  // ◉
            cairo_new_sub_path(cr)
            cairo_arc(cr, center.x, center.y, r, 0, 2 * Double.pi)
            cairo_stroke(cr)
            cairo_new_sub_path(cr)
            cairo_arc(cr, center.x, center.y, r * 0.42, 0, 2 * Double.pi)
            cairo_fill(cr)
        case .cache:  // ▣
            cairo_rectangle(cr, center.x - r, center.y - r, r * 2, r * 2)
            cairo_stroke(cr)
            cairo_rectangle(cr, center.x - r * 0.44, center.y - r * 0.44, r * 0.88, r * 0.88)
            cairo_fill(cr)
        case .cycle:  // ⟳
            cairo_new_sub_path(cr)
            cairo_arc(cr, center.x, center.y, r * 0.85, -Double.pi * 0.7, Double.pi * 0.9)
            cairo_stroke(cr)
            cairo_move_to(cr, center.x + r * 0.2, center.y - r * 0.95)
            cairo_line_to(cr, center.x + r * 0.85, center.y - r * 0.6)
            cairo_line_to(cr, center.x + r * 0.25, center.y - r * 0.25)
            cairo_close_path(cr)
            cairo_fill(cr)
        case .depth:  // ◆
            cairo_move_to(cr, center.x, center.y - r)
            cairo_line_to(cr, center.x + r, center.y)
            cairo_line_to(cr, center.x, center.y + r)
            cairo_line_to(cr, center.x - r, center.y)
            cairo_close_path(cr)
            cairo_fill(cr)
        case .night:  // ☽
            cairo_new_sub_path(cr)
            cairo_arc(cr, center.x, center.y, r, 0, 2 * Double.pi)
            cairo_fill(cr)
            // Bite the crescent out of it.
            cairo_set_operator(cr, 0)
            cairo_new_sub_path(cr)
            cairo_arc(cr, center.x + r * 0.5, center.y - r * 0.28, r * 0.9, 0, 2 * Double.pi)
            cairo_fill(cr)
            cairo_set_operator(cr, 2)
        case .alloy:  // ⬢
            for index in 0..<6 {
                let angle = Double(index) / 6 * 2 * Double.pi - Double.pi / 2
                let x = center.x + cos(angle) * r
                let y = center.y + sin(angle) * r
                if index == 0 {
                    cairo_move_to(cr, x, y)
                } else {
                    cairo_line_to(cr, x, y)
                }
            }
            cairo_close_path(cr)
            cairo_fill(cr)
        case .void:  // ✕
            cairo_move_to(cr, center.x - r * 0.8, center.y - r * 0.8)
            cairo_line_to(cr, center.x + r * 0.8, center.y + r * 0.8)
            cairo_move_to(cr, center.x + r * 0.8, center.y - r * 0.8)
            cairo_line_to(cr, center.x - r * 0.8, center.y + r * 0.8)
            cairo_stroke(cr)
        }
    }

    /// The rarity mark printed beside the collector number, drawn for the same
    /// reason as the energy marks.
    static func drawRarityPip(
        _ rarity: CreatureRarity, center: Point, size: Double, color: RGBA, on canvas: Canvas
    ) {
        let cr = canvas.cr
        let r = size / 2
        canvas.setColor(color)
        cairo_set_line_width(cr, max(size * 0.14, 0.7))
        cairo_set_line_cap(cr, 1)

        func star(points: Int, inner: Double) {
            for index in 0..<(points * 2) {
                let radius = index % 2 == 0 ? r : r * inner
                let angle = Double(index) / Double(points * 2) * 2 * Double.pi - Double.pi / 2
                let x = center.x + cos(angle) * radius
                let y = center.y + sin(angle) * radius
                if index == 0 {
                    cairo_move_to(cr, x, y)
                } else {
                    cairo_line_to(cr, x, y)
                }
            }
            cairo_close_path(cr)
            cairo_fill(cr)
        }

        switch rarity {
        case .common:  // ●
            cairo_new_sub_path(cr)
            cairo_arc(cr, center.x, center.y, r * 0.8, 0, 2 * Double.pi)
            cairo_fill(cr)
        case .uncommon:  // ◆
            cairo_move_to(cr, center.x, center.y - r)
            cairo_line_to(cr, center.x + r * 0.8, center.y)
            cairo_line_to(cr, center.x, center.y + r)
            cairo_line_to(cr, center.x - r * 0.8, center.y)
            cairo_close_path(cr)
            cairo_fill(cr)
        case .rare: star(points: 5, inner: 0.42)  // ★
        case .epic: star(points: 4, inner: 0.34)  // ✦
        case .legendary: star(points: 6, inner: 0.36)  // ✹
        case .mythic: star(points: 8, inner: 0.4)  // ✵
        }
    }

    /// The shiny mark: a four-point sparkle, drawn rather than typed.
    ///
    /// Cairo's toy text API does no font fallback, so a glyph the desktop font happens
    /// to lack renders as a box — `✦` is one of those on a stock Ubuntu. Same reason the
    /// energy and rarity marks are paths.
    static func drawShinyMark(center: Point, size: Double, color: RGBA, on canvas: Canvas) {
        let cr = canvas.cr
        let r = size / 2
        canvas.setColor(color)
        for index in 0..<8 {
            let radius = index % 2 == 0 ? r : r * 0.3
            let angle = Double(index) / 8 * 2 * Double.pi - Double.pi / 2
            let x = center.x + cos(angle) * radius
            let y = center.y + sin(angle) * radius
            if index == 0 {
                cairo_move_to(cr, x, y)
            } else {
                cairo_line_to(cr, x, y)
            }
        }
        cairo_close_path(cr)
        cairo_fill(cr)
    }

    /// An energy pip: the type's mark on a coloured disc.
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
        drawEnergyMark(energy, center: center, size: size, on: canvas)
    }
}
