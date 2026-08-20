import CLinuxTray
import Foundation
import RationKit

/// The binder: every creature in the set, quiet until unlocked.
extension Panel {

    func drawCollectionTab(_ canvas: Canvas, width: Double, top: Double, now: Date) -> Double {
        let state = Dex.evaluate(app.dexInput())

        // A newly unlocked creature is announced before the binder, once.
        if revealQueue.isEmpty {
            let pending = Dex.pendingReveals(
                caught: state.caught, alreadyRevealed: app.config.revealed)
            if !pending.isEmpty, inspectedCreatureID == nil {
                revealQueue = pending
            }
        }

        if let creature = revealQueue.first {
            return drawCatchOverlay(
                canvas, width: width, top: top, creature: creature,
                remaining: revealQueue.count)
        }

        if let id = inspectedCreatureID,
            let creature = Dex.roster.first(where: { $0.id == id })
        {
            let caught = state.caught.contains { $0.id == creature.id }
            return drawInspector(canvas, width: width, top: top, creature: creature, caught: caught)
        }

        return drawBinder(canvas, width: width, top: top, state: state)
    }

    // MARK: Binder

    private func drawBinder(
        _ canvas: Canvas, width: Double, top: Double, state: DexState
    ) -> Double {
        let palette = canvas.palette
        var y = top + 12

        canvas.text("Pokémon", at: Point(12, y), size: 12, weight: .bold)
        canvas.text(
            "\(state.caught.count) of \(Dex.roster.count) unlocked", at: Point(12, y + 16),
            size: 10.5, color: palette.secondaryText)

        canvas.text(
            PowerFormat.compact(state.stats.power), at: Point(width - 12, y - 1), size: 16,
            weight: .bold, align: .trailing)
        canvas.text(
            "Score", at: Point(width - 12, y + 18), size: 9, color: palette.secondaryText,
            align: .trailing)
        y += 34

        if app.isDexScanning {
            canvas.text(
                "Reading history…", at: Point(12, y), size: 10.5, color: palette.secondaryText)
            y += 18
        }

        if state.caught.isEmpty, !app.isDexScanning {
            y += canvas.paragraph(
                "Use Claude, Codex, or Cursor — the first tokens unlock Ember.",
                at: Point(12, y), width: width - 24, size: 10.5, color: palette.secondaryText)
            y += 6
        }

        if let hunt = state.nextPowerCatch {
            canvas.text("Next unlock", at: Point(12, y), size: 9.5, weight: .medium)
            canvas.text(
                "\(Int(hunt.progress * 100))%", at: Point(width - 12, y), size: 9.5,
                color: palette.secondaryText, align: .trailing)
            y += 15
            let bar = Rect(12, y, width - 24, 6)
            canvas.fillRounded(bar, radius: 3, palette.track)
            canvas.fillRounded(
                Rect(bar.x, bar.y, max(6, bar.width * hunt.progress), bar.height), radius: 3,
                palette.accent)
            y += 14
        } else if state.uncaught.isEmpty {
            canvas.text("The set is complete.", at: Point(12, y), size: 10.5, color: palette.accent)
            y += 18
        }

        // Three columns, as on the Mac.
        let columns = 3.0
        let gap = 8.0
        let cardWidth = (width - 24 - gap * (columns - 1)) / columns
        let cardHeight = CardFace.miniHeight(width: cardWidth)

        for (index, creature) in Dex.roster.enumerated() {
            let column = Double(index % Int(columns))
            let row = Double(index / Int(columns))
            let rect = Rect(
                12 + column * (cardWidth + gap), y + row * (cardHeight + gap), cardWidth,
                cardHeight)
            let caught = state.caught.contains { $0.id == creature.id }
            CardFace.drawMini(creature, caught: caught, in: rect, on: canvas)
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

    // MARK: Inspector

    private func drawInspector(
        _ canvas: Canvas, width: Double, top: Double, creature: Creature, caught: Bool
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
            creature, caught: caught, in: Rect(16, y, cardWidth, 0), on: canvas)
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

    /// The pack-rip: one card at a time, revealed as it is unlocked.
    private func drawCatchOverlay(
        _ canvas: Canvas, width: Double, top: Double, creature: Creature, remaining: Int
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
            "Unlocked", at: Point(width / 2, y), size: 11, weight: .bold,
            color: canvas.palette.accent, align: .center)
        y += 20

        let cardWidth = width - 44
        let cardHeight = CardFace.drawFull(
            creature, caught: true, in: Rect(22, y, cardWidth, 0), on: canvas)
        addHit(Rect(22, y, cardWidth, cardHeight)) {}
        y += cardHeight + 14

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
        guard let current = revealQueue.first else { return }
        app.update { config in
            config.revealedCreatureIDs = Array(config.revealed.union([current.id]))
        }
        revealQueue.removeFirst()
        resetOverlayScroll()
    }

    private func skipAllReveals() {
        let ids = revealQueue.map(\.id)
        app.update { config in
            config.revealedCreatureIDs = Array(config.revealed.union(ids))
        }
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
        let state = Dex.evaluate(app.dexInput())
        let caption = CreatureShare.caption(for: creature, caughtCount: state.caught.count)
        let encoded =
            caption.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xdg-open")
        process.arguments = ["https://x.com/intent/post?text=\(encoded)"]
        try? process.run()
    }
}
