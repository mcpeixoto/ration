import CLinuxTray
import Foundation
import RationKit

/// Which part of the collection is showing.
enum CollectionSegment: String, CaseIterable {
    case companion, binder, log, shop

    var title: String {
        switch self {
        case .companion: "Companion"
        case .binder: "Binder"
        case .log: "Log"
        case .shop: "Shop"
        }
    }
}

/// A moment worth stopping the tab for: a pack opening, or a creature being filed.
struct CompanionReveal {
    enum Kind { case ripped, filed }

    let creature: Creature
    let kind: Kind
    let shiny: Bool

    var headline: String {
        switch kind {
        case .ripped: "The pack rips open"
        case .filed: "Filed in the binder"
        }
    }
}

/// The collection: what you are raising, what you have filed, and what tokens buy.
extension Panel {

    func drawCollectionTab(_ canvas: Canvas, width: Double, top: Double, now: Date) -> Double {
        drainCompanionEvents()

        if let reveal = revealQueue.first {
            return drawCatchOverlay(
                canvas, width: width, top: top, reveal: reveal, remaining: revealQueue.count)
        }

        if let id = inspectedCreatureID, let creature = Dex.creature(id) {
            let state = app.companion
            return drawInspector(
                canvas, width: width, top: top, creature: creature,
                caught: state.filedSpecies.contains(id) || state.archive.contains(id),
                shiny: state.log.contains { $0.isShiny && $0.chain.contains(id) })
        }

        var y = top + 12
        y += drawSegments(canvas, width: width, top: y)
        let state = app.companion
        switch collectionSegment {
        case .companion: y += drawCompanion(canvas, width: width, top: y, state: state)
        case .binder: y += drawBinder(canvas, width: width, top: y, state: state)
        case .log: y += drawLog(canvas, width: width, top: y, state: state)
        case .shop: y += drawShop(canvas, width: width, top: y, state: state)
        }
        return y - top + 4
    }

    /// Turn what the engine reported into things to show. Rips and filings stop the tab
    /// for a card; an evolution only flashes the header, because interrupting for every
    /// step of a three-form line would be four interruptions per creature.
    private func drainCompanionEvents() {
        guard !app.companionEvents.isEmpty else { return }
        var sawCelebration = false
        for event in app.companionEvents {
            switch event {
            case .ripped(let id, let shiny):
                if let creature = Dex.creature(id) {
                    revealQueue.append(
                        CompanionReveal(creature: creature, kind: .ripped, shiny: shiny))
                }
                sawCelebration = true
            case .filed(let id, let shiny, _):
                if let creature = Dex.creature(id) {
                    revealQueue.append(
                        CompanionReveal(creature: creature, kind: .filed, shiny: shiny))
                }
                sawCelebration = true
            case .evolved:
                sawCelebration = true
            case .granted, .bought, .boosted, .traitRolled:
                break
            }
        }
        app.companionEvents = []
        if sawCelebration {
            restartCelebration()
            restartReveal()
        }
    }

    // MARK: Segments

    private func drawSegments(_ canvas: Canvas, width: Double, top: Double) -> Double {
        let palette = canvas.palette
        let all = CollectionSegment.allCases
        let gap = 6.0
        let slot = (width - 24 - gap * Double(all.count - 1)) / Double(all.count)
        for (index, segment) in all.enumerated() {
            let rect = Rect(12 + Double(index) * (slot + gap), top, slot, 24)
            let selected = segment == collectionSegment
            canvas.fillRounded(
                rect, radius: 7,
                selected
                    ? palette.accent.opacity(0.24)
                    : (isHovered(rect) ? palette.track.opacity(0.9) : palette.track.opacity(0.5)))
            canvas.text(
                segment.title, at: Point(rect.midX, rect.y + 5), size: 10.5,
                weight: selected ? .bold : .medium,
                color: selected ? palette.accent : palette.secondaryText, align: .center)
            addHit(rect) { [weak self] in
                self?.collectionSegment = segment
            }
        }
        return 34
    }

    // MARK: Companion

    private func drawCompanion(
        _ canvas: Canvas, width: Double, top: Double, state: CompanionState
    ) -> Double {
        let palette = canvas.palette
        var y = top

        let portrait = Rect(12, y, 76, 76)
        if let run = state.active {
            drawRunHeader(canvas, width: width, portrait: portrait, run: run)
        } else {
            drawPackHeader(canvas, width: width, portrait: portrait, state: state)
        }
        y += 84

        if let run = state.active {
            y += drawEvolutionStrip(canvas, width: width, top: y, run: run)
        }

        // Wallet and bag, so the shop is not the only place they are visible.
        canvas.text("Wallet", at: Point(12, y), size: 9.5, color: palette.secondaryText)
        canvas.text(
            PowerFormat.compact(state.wallet), at: Point(width - 12, y - 2), size: 12,
            weight: .bold, align: .trailing)
        y += 18
        let held = state.heldItems.map { "\($0.kind.label) ×\($0.count)" }.joined(separator: " · ")
        if !held.isEmpty {
            canvas.text(held, at: Point(12, y), size: 9.5, color: palette.secondaryText)
            y += 16
        }
        y += 6

        let filed = state.filedSpecies
        canvas.text(
            "\(filed.count) of \(Dex.roster.count) filed", at: Point(12, y), size: 10.5,
            weight: .medium)
        let archived = state.archive.subtracting(filed).count
        if archived > 0 {
            canvas.text(
                "\(archived) from Set 01", at: Point(width - 12, y), size: 9.5,
                color: palette.secondaryText, align: .trailing)
        }
        y += 20

        return y - top
    }

    private func drawRunHeader(_ canvas: Canvas, width: Double, portrait: Rect, run: ActiveRun) {
        let palette = canvas.palette
        guard let creature = Dex.creature(run.currentID) else { return }
        let lore = creature.lore
        let key = CardFace.keyColor(lore.energy, shiny: run.isShiny)

        canvas.fillRounded(portrait, radius: 12, palette.track.opacity(0.6))
        canvas.clipped(to: portrait, radius: 12) {
            CreatureArtwork.draw(lore.art, in: portrait, on: canvas, key: key, caught: true)
        }
        canvas.strokeRounded(portrait, radius: 12, width: 1.5, key.opacity(0.55))
        // A rip or an evolution swaps the illustration underneath a white flash, so the
        // change lands as a moment rather than a glitch.
        let flash = celebrationFlash
        if flash > 0 {
            canvas.fillRounded(portrait, radius: 12, RGBA(1, 1, 1, flash))
        }

        var x = portrait.maxX + 12
        var y = portrait.y + 2
        canvas.text(
            canvas.truncated(creature.name, size: 13, weight: .bold, maxWidth: width - x - 74),
            at: Point(x, y), size: 13, weight: .bold)
        x += canvas.width(creature.name, size: 13, weight: .bold) + 8
        if run.isShiny {
            CardFace.drawShinyMark(
                center: Point(x, y + 8), size: 9, color: palette.accent, on: canvas)
        }
        canvas.text(
            creature.rarity.label.uppercased(), at: Point(width - 12, y + 2), size: 8,
            weight: .bold, color: CardFace.rarityColor(creature.rarity, palette: palette),
            align: .trailing)
        y += 19

        let stage = Dex.lore[run.currentID]?.stage.label ?? "Basic"
        canvas.text(
            "\(stage) · \(run.trait.label)", at: Point(portrait.maxX + 12, y), size: 9.5,
            color: palette.secondaryText)
        y += 16

        let bar = Rect(portrait.maxX + 12, y, width - portrait.maxX - 24, 6)
        canvas.fillRounded(bar, radius: 3, palette.track)
        canvas.fillRounded(
            Rect(bar.x, bar.y, max(4, bar.width * run.progress), bar.height), radius: 3,
            palette.accent)
        y += 12
        // Never name the next form — the destination is the surprise the run is for.
        canvas.text(
            "\(PowerFormat.compact(run.remaining)) \(run.isFinalForm ? "to file" : "to evolve")",
            at: Point(portrait.maxX + 12, y), size: 9, color: palette.secondaryText)
    }

    private func drawPackHeader(
        _ canvas: Canvas, width: Double, portrait: Rect, state: CompanionState
    ) {
        let palette = canvas.palette
        canvas.fillRounded(portrait, radius: 12, palette.track.opacity(0.6))
        drawSealedPack(canvas, in: portrait.inset(by: 12), state: state)
        canvas.strokeRounded(portrait, radius: 12, width: 1.5, palette.accent.opacity(0.4))

        var y = portrait.y + 2
        canvas.text("Sealed pack", at: Point(portrait.maxX + 12, y), size: 13, weight: .bold)
        y += 19
        let promise =
            state.packGuarantee.map { "\(CompanionPack.label($0)) · \($0.label) or better" }
            ?? "Burn tokens and it opens."
        canvas.text(
            canvas.truncated(promise, size: 9.5, maxWidth: width - portrait.maxX - 24),
            at: Point(portrait.maxX + 12, y), size: 9.5, color: palette.secondaryText)
        y += 16

        let bar = Rect(portrait.maxX + 12, y, width - portrait.maxX - 24, 6)
        canvas.fillRounded(bar, radius: 3, palette.track)
        canvas.fillRounded(
            Rect(bar.x, bar.y, max(4, bar.width * state.packProgress), bar.height), radius: 3,
            palette.accent)
        y += 12
        canvas.text(
            "\(PowerFormat.compact(state.packRemaining)) to rip", at: Point(portrait.maxX + 12, y),
            size: 9, color: palette.secondaryText)
    }

    /// A wrapped pack: a foil rectangle with a band across it. It leans as the pack
    /// fills, so a nearly-full pack reads as about to go without needing a number.
    private func drawSealedPack(_ canvas: Canvas, in rect: Rect, state: CompanionState) {
        let palette = canvas.palette
        let tilt =
            (state.packProgress >= 0.9 && Motion.isEnabled)
            ? sin(Motion.clock() * 9) * 0.09 : 0
        cairo_save(canvas.cr)
        cairo_translate(canvas.cr, rect.midX, rect.midY)
        cairo_rotate(canvas.cr, tilt)
        cairo_translate(canvas.cr, -rect.midX, -rect.midY)
        let body = Rect(rect.x + rect.width * 0.16, rect.y, rect.width * 0.68, rect.height)
        canvas.fillRounded(body, radius: 4, palette.accent.opacity(0.55))
        canvas.fillRounded(
            Rect(body.x, body.midY - 3, body.width, 6), radius: 1, palette.accent)
        canvas.strokeRounded(body, radius: 4, width: 1, palette.accent)
        cairo_restore(canvas.cr)
    }

    /// Forms reached, then a question mark for every one still to come.
    private func drawEvolutionStrip(
        _ canvas: Canvas, width: Double, top: Double, run: ActiveRun
    ) -> Double {
        let palette = canvas.palette
        let reached = run.revealed
        let ahead = max(0, run.forms - reached.count)
        let count = reached.count + ahead
        guard count > 1 else { return 0 }

        let gap = 6.0
        let slot = min(56.0, (width - 24 - gap * Double(count - 1)) / Double(count))
        var x = 12.0
        for index in 0..<count {
            let rect = Rect(x, top, slot, 30)
            let isCurrent = index == run.stageIndex
            canvas.fillRounded(
                rect, radius: 7,
                isCurrent ? palette.accent.opacity(0.2) : palette.track.opacity(0.6))
            if index < reached.count, let creature = Dex.creature(reached[index]) {
                canvas.text(
                    canvas.truncated(creature.name, size: 9, maxWidth: slot - 8),
                    at: Point(rect.midX, rect.y + 9), size: 9,
                    weight: isCurrent ? .bold : .regular,
                    color: isCurrent ? palette.accent : palette.secondaryText, align: .center)
            } else {
                canvas.text(
                    "?", at: Point(rect.midX, rect.y + 9), size: 11, weight: .bold,
                    color: palette.secondaryText.opacity(0.6), align: .center)
            }
            x += slot + gap
        }
        return 40
    }

    // MARK: Binder

    private func drawBinder(
        _ canvas: Canvas, width: Double, top: Double, state: CompanionState
    ) -> Double {
        let palette = canvas.palette
        var y = top
        let filed = state.filedSpecies
        let archived = state.archive.subtracting(filed)

        canvas.text(
            "\(filed.count) of \(Dex.roster.count) filed", at: Point(12, y), size: 12,
            weight: .bold)
        if !archived.isEmpty {
            canvas.text(
                "Set 01 archive — \(archived.count)", at: Point(width - 12, y + 1), size: 9.5,
                color: palette.secondaryText, align: .trailing)
        }
        y += 22

        if app.isDexScanning {
            canvas.text(
                "Reading history…", at: Point(12, y), size: 10.5, color: palette.secondaryText)
            y += 18
        } else if filed.isEmpty {
            y += canvas.paragraph(
                "Nothing filed yet. Burn tokens, rip the pack, and raise what comes out.",
                at: Point(12, y), width: width - 24, size: 10.5, color: palette.secondaryText)
            y += 6
        }

        // Three columns, as on the Mac.
        let columns = 3.0
        let gap = 8.0
        let cardWidth = (width - 24 - gap * (columns - 1)) / columns
        let cardHeight = CardFace.miniHeight(width: cardWidth)
        let shinySpecies = Set(state.log.filter(\.isShiny).flatMap(\.chain))

        for (index, creature) in Dex.roster.enumerated() {
            let column = Double(index % Int(columns))
            let row = Double(index / Int(columns))
            let rect = Rect(
                12 + column * (cardWidth + gap), y + row * (cardHeight + gap), cardWidth,
                cardHeight)
            let isFiled = filed.contains(creature.id)
            let isArchived = archived.contains(creature.id)
            CardFace.drawMini(
                creature, caught: isFiled || isArchived, in: rect, on: canvas,
                foilPhase: foilPhase, shiny: shinySpecies.contains(creature.id),
                archived: isArchived)
            if isHovered(rect) {
                canvas.strokeRounded(
                    rect, radius: 9, width: 1.5,
                    CardFace.rarityColor(creature.rarity, palette: palette))
            }
            addHit(rect) { [weak self] in
                self?.inspectedCreatureID = creature.id
                self?.resetOverlayScroll()
            }
        }

        let rows = ceil(Double(Dex.roster.count) / columns)
        y += rows * (cardHeight + gap)
        return y - top + 4
    }

    // MARK: Catch log

    private func drawLog(
        _ canvas: Canvas, width: Double, top: Double, state: CompanionState
    ) -> Double {
        let palette = canvas.palette
        var y = top

        guard !state.log.isEmpty else {
            canvas.text(
                "Nothing filed yet.", at: Point(12, y), size: 10.5, color: palette.secondaryText)
            return 24
        }

        canvas.text("\(state.log.count) raised", at: Point(12, y), size: 12, weight: .bold)
        y += 24

        for entry in state.log.reversed() {
            let row = Rect(12, y, width - 24, 40)
            canvas.fillRounded(row, radius: 8, palette.track.opacity(0.45))
            // A guillemet, not an arrow: Cairo's toy text API does no font fallback and
            // the stock desktop font has no U+2192, so an arrow draws as a box.
            let chain = entry.chain.compactMap { Dex.creature($0)?.name }.joined(separator: " › ")
            let name = Dex.creature(entry.finalID)?.name ?? entry.finalID
            canvas.text(name, at: Point(row.x + 10, row.y + 6), size: 11, weight: .bold)
            if entry.isShiny {
                CardFace.drawShinyMark(
                    center: Point(
                        row.x + 16 + canvas.width(name, size: 11, weight: .bold), row.y + 12),
                    size: 8, color: palette.accent, on: canvas)
            }
            canvas.text(
                entry.rarity.label.uppercased(), at: Point(row.maxX - 10, row.y + 7), size: 8,
                weight: .bold, color: CardFace.rarityColor(entry.rarity, palette: palette),
                align: .trailing)
            canvas.text(
                canvas.truncated(
                    "\(chain) · \(entry.trait.label)", size: 9, maxWidth: row.width - 90),
                at: Point(row.x + 10, row.y + 23), size: 9, color: palette.secondaryText)
            canvas.text(
                Self.logDate.string(from: entry.filedAt), at: Point(row.maxX - 10, row.y + 24),
                size: 8.5, color: palette.secondaryText, align: .trailing)
            addHit(row) { [weak self] in
                self?.inspectedCreatureID = entry.finalID
                self?.resetOverlayScroll()
            }
            y += 46
        }
        return y - top
    }

    static let logDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return formatter
    }()

    // MARK: Shop

    private func drawShop(
        _ canvas: Canvas, width: Double, top: Double, state: CompanionState
    ) -> Double {
        let palette = canvas.palette
        var y = top

        let wallet = Rect(12, y, width - 24, 52)
        canvas.fillRounded(wallet, radius: 10, palette.track.opacity(0.5))
        canvas.text(
            "Spendable", at: Point(wallet.x + 10, wallet.y + 8), size: 9.5,
            color: palette.secondaryText)
        canvas.text(
            PowerFormat.compact(state.wallet), at: Point(wallet.x + 10, wallet.y + 22), size: 18,
            weight: .bold)
        canvas.text(
            "Tokens you have already burned.", at: Point(wallet.maxX - 10, wallet.y + 30),
            size: 8.5, color: palette.secondaryText, align: .trailing)
        y += 60

        for entry in CompanionEngine.shopEntries(state) {
            y += drawShopRow(canvas, width: width, top: y, entry: entry, state: state)
        }

        let usable = state.heldItems.filter { !$0.kind.isPassive && state.active != nil }
        if !usable.isEmpty {
            y += 6
            canvas.text("Bag", at: Point(12, y), size: 11, weight: .bold)
            y += 20
            for (kind, count) in usable {
                y += drawBagRow(canvas, width: width, top: y, kind: kind, count: count)
            }
        }
        return y - top + 4
    }

    private func drawShopRow(
        _ canvas: Canvas, width: Double, top: Double, entry: ShopEntry, state: CompanionState
    ) -> Double {
        let palette = canvas.palette
        let row = Rect(12, top, width - 24, 56)
        canvas.fillRounded(row, radius: 10, palette.track.opacity(0.45))

        let name: String
        let detail: String
        switch entry {
        case .item(let kind):
            name = kind.label
            detail = kind.detail
        case .pack(let floor):
            name = CompanionPack.label(floor)
            detail =
                floor.map { "A new pack, guaranteed to reach \($0.label) or better." }
                ?? "Discards what you are raising and seals a new pack."
        }

        canvas.text(name, at: Point(row.x + 10, row.y + 8), size: 11, weight: .bold)
        canvas.text(
            canvas.truncated(detail, size: 9, maxWidth: row.width - 100),
            at: Point(row.x + 10, row.y + 24), size: 9, color: palette.secondaryText)
        canvas.text(
            PowerFormat.compact(entry.price), at: Point(row.maxX - 10, row.y + 8), size: 10,
            weight: .medium, color: palette.secondaryText, align: .trailing)

        let held: Bool
        if case .item(let kind) = entry, kind.isPassive, state.itemCount(kind) > 0 {
            held = true
        } else {
            held = false
        }
        let button = Rect(row.maxX - 74, row.y + 26, 64, 22)
        if held {
            canvas.text(
                "Held", at: Point(button.midX, button.y + 4), size: 10, weight: .medium,
                color: palette.accent, align: .center)
        } else if CompanionEngine.canBuy(entry, state) {
            canvas.fillRounded(
                button, radius: 6,
                isHovered(button) ? palette.accent.opacity(0.34) : palette.accent.opacity(0.18))
            canvas.text(
                "Buy", at: Point(button.midX, button.y + 4), size: 10, weight: .medium,
                color: palette.accent, align: .center)
            addHit(button) { [weak self] in
                self?.app.mutateCompanion { state in
                    var rng = SystemRandomNumberGenerator()
                    return CompanionEngine.buy(entry, &state, now: Date(), using: &rng)
                }
            }
        } else {
            canvas.text(
                "\(PowerFormat.compact(entry.price - state.wallet)) short",
                at: Point(button.maxX, button.y + 5), size: 9,
                color: palette.secondaryText.opacity(0.8), align: .trailing)
        }
        return 62
    }

    private func drawBagRow(
        _ canvas: Canvas, width: Double, top: Double, kind: ItemKind, count: Int
    ) -> Double {
        let palette = canvas.palette
        let row = Rect(12, top, width - 24, 30)
        canvas.fillRounded(row, radius: 8, palette.track.opacity(0.35))
        canvas.text(
            "\(kind.label) ×\(count)", at: Point(row.x + 10, row.y + 8), size: 10, weight: .medium)
        let button = Rect(row.maxX - 66, row.y + 4, 56, 22)
        canvas.fillRounded(
            button, radius: 6,
            isHovered(button) ? palette.accent.opacity(0.34) : palette.accent.opacity(0.18))
        canvas.text(
            "Use", at: Point(button.midX, button.y + 4), size: 10, weight: .medium,
            color: palette.accent, align: .center)
        addHit(button) { [weak self] in
            self?.app.mutateCompanion { state in
                var rng = SystemRandomNumberGenerator()
                return CompanionEngine.use(kind, &state, now: Date(), using: &rng)
            }
        }
        return 36
    }

    // MARK: Inspector

    private func drawInspector(
        _ canvas: Canvas, width: Double, top: Double, creature: Creature, caught: Bool,
        shiny: Bool
    ) -> Double {
        // The card sits on a dimmed ground, the way the Mac presents it.
        // Clicking the ground dismisses; the card itself does not, so reaching
        // for Copy and missing does not throw the card away.
        canvas.fill(Rect(0, top, width, 2000), RGBA(0, 0, 0, 0.82))
        addHit(Rect(0, top, width, 2000)) { [weak self] in
            self?.dismissInspector()
        }

        var y = top + 16
        let cardWidth = width - 32
        let cardHeight = CardFace.drawFull(
            creature, caught: caught, in: Rect(16, y, cardWidth, 0), on: canvas,
            foilPhase: foilPhase, shiny: shiny)
        // Swallows the click so it does not fall through to the scrim.
        addHit(Rect(16, y, cardWidth, cardHeight)) {}
        y += cardHeight + 12

        if caught {
            // Copying and saving a card is the point of the binder, so the
            // Linux build keeps both — the image goes to a PNG, and the
            // clipboard copy goes through whichever helper the desktop has.
            let buttons: [(String, () -> Void)] = [
                (
                    copiedCreatureID == creature.id ? "Copied" : "Copy",
                    { [weak self] in
                        self?.copyCard(creature)
                    }
                ),
                ("Save…", { [weak self] in self?.saveCard(creature) }),
                ("Post on X", { [weak self] in self?.postOnX(creature) }),
            ]
            let slot = (width - 32 - 12) / Double(buttons.count)
            for (index, button) in buttons.enumerated() {
                let rect = Rect(16 + Double(index) * (slot + 6), y, slot, 26)
                canvas.fillRounded(
                    rect, radius: 7,
                    isHovered(rect)
                        ? canvas.palette.accent.opacity(0.3) : canvas.palette.accent.opacity(0.18))
                canvas.text(
                    button.0, at: Point(rect.midX, rect.y + 6), size: 11, weight: .medium,
                    color: canvas.palette.accent, align: .center)
                addHit(rect) { button.1() }
            }
            y += 34
        }

        // Pinning is only offered for cards they hold — the tray mark should never be a
        // creature they have not seen.
        if caught {
            let pinned = app.companion.pinnedID == creature.id
            let pin = Rect(16, y, width - 32, 24)
            canvas.text(
                pinned ? "Unpin from the tray" : "Pin to the tray",
                at: Point(pin.midX, pin.y + 5), size: 10.5,
                color: isHovered(pin) ? canvas.palette.accent : RGBA(1, 1, 1, 0.65),
                align: .center)
            addHit(pin) { [weak self] in
                self?.app.mutateCompanion { state in
                    state.pinnedID = pinned ? nil : creature.id
                    return []
                }
            }
            y += 30
        }

        let close = Rect(width / 2 - 34, y, 68, 24)
        canvas.text(
            "Close", at: Point(close.midX, close.y + 5), size: 11,
            color: isHovered(close) ? RGBA(1, 1, 1) : RGBA(1, 1, 1, 0.7), align: .center)
        addHit(close) { [weak self] in
            self?.dismissInspector()
        }
        y += 32

        if let path = lastSavedCardPath {
            canvas.text(
                canvas.truncated("Saved to \(path)", size: 9, maxWidth: width - 32),
                at: Point(16, y), size: 9, color: RGBA(1, 1, 1, 0.55))
            y += 16
        }

        return y - top + 8
    }

    // MARK: Catch overlay

    /// The pack-rip: one card at a time, as it happens.
    private func drawCatchOverlay(
        _ canvas: Canvas, width: Double, top: Double, reveal: CompanionReveal, remaining: Int
    ) -> Double {
        canvas.fill(Rect(0, top, width, 2000), RGBA(0, 0, 0, 0.88))
        // Advance, never skip: tapping past one card is a small action and
        // throwing away every card still queued is not, so they do not share
        // a target.
        addHit(Rect(0, top, width, 2000)) { [weak self] in
            self?.advanceReveal()
        }
        var y = top + 14

        canvas.text(
            reveal.headline, at: Point(width / 2, y), size: 11, weight: .bold,
            color: canvas.palette.accent, align: .center)
        y += 20

        let cardWidth = width - 44
        // Measured first, then drawn scaled about its own centre: the card
        // arrives at 92% and settles, which is the moment the pack-rip is for.
        let cardHeight = CardFace.fullHeight(
            reveal.creature, caught: true, width: cardWidth, on: canvas)
        let progress = revealProgress
        let cardScale = 0.92 + 0.08 * progress
        let cardRect = Rect(22, y, cardWidth, cardHeight)

        cairo_save(canvas.cr)
        cairo_translate(canvas.cr, cardRect.midX, cardRect.midY)
        cairo_scale(canvas.cr, cardScale, cardScale)
        cairo_translate(canvas.cr, -cardRect.midX, -cardRect.midY)
        cairo_push_group(canvas.cr)
        CardFace.drawFull(
            reveal.creature, caught: true, in: cardRect, on: canvas, foilPhase: foilPhase,
            shiny: reveal.shiny)
        cairo_pop_group_to_source(canvas.cr)
        cairo_paint_with_alpha(canvas.cr, min(1, progress * 1.4))
        cairo_restore(canvas.cr)

        addHit(cardRect) {}
        y += cardHeight + 14

        if reveal.shiny {
            CardFace.drawShinyMark(
                center: Point(width / 2 - 26, y + 6), size: 11, color: canvas.palette.accent,
                on: canvas)
            canvas.text(
                "Shiny", at: Point(width / 2 - 16, y), size: 11, weight: .bold,
                color: canvas.palette.accent)
            y += 20
        }

        let continueRect = Rect(width / 2 - 70, y, 140, 28)
        canvas.fillRounded(
            continueRect, radius: 8,
            isHovered(continueRect)
                ? canvas.palette.accent.opacity(0.34) : canvas.palette.accent.opacity(0.2))
        canvas.text(
            remaining > 1 ? "Next (\(remaining - 1) more)" : "Continue",
            at: Point(continueRect.midX, continueRect.y + 7), size: 11, weight: .medium,
            color: canvas.palette.accent, align: .center)
        addHit(continueRect) { [weak self] in
            self?.advanceReveal()
        }
        y += 34

        if remaining > 1 {
            let skip = Rect(width / 2 - 40, y, 80, 20)
            canvas.text(
                "Skip all", at: Point(skip.midX, skip.y + 3), size: 10,
                color: RGBA(1, 1, 1, 0.6), align: .center)
            addHit(skip) { [weak self] in
                self?.skipAllReveals()
            }
            y += 26
        }

        return y - top + 10
    }

    func dismissInspector() {
        inspectedCreatureID = nil
        copiedCreatureID = nil
        resetOverlayScroll()
    }

    func advanceReveal() {
        guard !revealQueue.isEmpty else { return }
        revealQueue.removeFirst()
        restartReveal()
        resetOverlayScroll()
    }

    private func skipAllReveals() {
        revealQueue = []
        resetOverlayScroll()
    }

    // MARK: Sharing

    /// Renders the full face to a PNG at print size.
    private func renderCard(_ creature: Creature, to path: String) -> Bool {
        let width = 320.0
        let scale = 3.0
        guard let measuringSurface = cairo_image_surface_create(0, 1, 1),
            let measuringContext = cairo_create(measuringSurface)
        else { return false }
        let measuring = Canvas(cr: measuringContext, palette: Palette(isDark: true))
        let height = CardFace.fullHeight(
            creature, caught: true, width: width, on: measuring)
        cairo_destroy(measuringContext)
        cairo_surface_destroy(measuringSurface)

        guard
            let surface = cairo_image_surface_create(
                0, Int32(width * scale), Int32((height + 20) * scale)),
            let cr = cairo_create(surface)
        else { return false }
        cairo_scale(cr, scale, scale)
        let canvas = Canvas(cr: cr, palette: Palette(isDark: true))
        canvas.fill(Rect(0, 0, width, height + 20), RGBA(0.05, 0.05, 0.05))
        CardFace.drawFull(creature, caught: true, in: Rect(0, 10, width, 0), on: canvas)
        cairo_surface_flush(surface)
        let status = cairo_surface_write_to_png(surface, path)
        cairo_destroy(cr)
        cairo_surface_destroy(surface)
        return status == 0
    }

    private func cardPath(_ creature: Creature) -> String {
        let directory = PlatformPaths.home.appending(path: ".cache/ration/cards")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "\(creature.name).png").path
    }

    private func copyCard(_ creature: Creature) {
        let path = cardPath(creature)
        guard renderCard(creature, to: path) else { return }
        // wl-copy on Wayland, xclip on X11 — whichever the session has.
        let candidates: [(String, [String])] = [
            ("/usr/bin/wl-copy", ["--type", "image/png"]),
            ("/usr/bin/xclip", ["-selection", "clipboard", "-t", "image/png", "-i", path]),
        ]
        for (tool, arguments) in candidates where FileManager.default.isExecutableFile(atPath: tool)
        {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = arguments
            if tool.hasSuffix("wl-copy"), let data = FileManager.default.contents(atPath: path) {
                let pipe = Pipe()
                process.standardInput = pipe
                try? process.run()
                pipe.fileHandleForWriting.write(data)
                try? pipe.fileHandleForWriting.close()
            } else {
                try? process.run()
            }
            copiedCreatureID = creature.id
            lastSavedCardPath = path
            return
        }
        // No clipboard helper installed: the file is still on disk, so say where.
        copiedCreatureID = nil
        lastSavedCardPath = path
    }

    private func saveCard(_ creature: Creature) {
        let directory = PlatformPaths.home.appending(path: "Pictures")
        let target =
            FileManager.default.fileExists(atPath: directory.path)
            ? directory.appending(path: "\(creature.name).png").path
            : cardPath(creature)
        if renderCard(creature, to: target) {
            lastSavedCardPath = target
        }
    }

    /// Copies the card, then opens a new post with the caption — the same two
    /// steps the Mac takes.
    private func postOnX(_ creature: Creature) {
        copyCard(creature)
        let caption = CreatureShare.caption(
            for: creature, caughtCount: app.companion.filedSpecies.count)
        let encoded =
            caption.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xdg-open")
        process.arguments = ["https://x.com/intent/post?text=\(encoded)"]
        try? process.run()
    }
}
