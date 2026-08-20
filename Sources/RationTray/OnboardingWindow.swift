import CLinuxTray
import Foundation
import RationKit

/// Shown once, before Ration reads a stored session for the first time.
///
/// The macOS version exists because the first read triggers a keychain prompt.
/// Linux has no such dialog — Claude Code writes its session to a file the user
/// already owns — so this says what is actually read and where it goes, and
/// lets them start it deliberately rather than discovering it afterwards.
@MainActor
final class OnboardingWindow {

    private let app: TrayApp
    private var window: Widget?
    private var area: Widget?
    private var hitRegions: [(rect: Rect, action: () -> Void)] = []
    private var pointer = Point(-1, -1)
    /// Logical units per pixel; see `UIScale`.
    private var scale = 1.0

    private let width = 460.0
    private let height = 470.0

    nonisolated(unsafe) private static var current: OnboardingWindow?

    static func presentIfNeeded(app: TrayApp) {
        guard current == nil else { return }
        let window = OnboardingWindow(app: app)
        current = window
        window.open()
    }

    init(app: TrayApp) {
        self.app = app
    }

    private func open() {
        let window = gtk_window_new(0)
        gtk_window_set_title(window, "Welcome to Ration")
        scale = UIScale.factor(override: app.config.uiScale)
        gtk_window_set_default_size(
            window, Int32((width * scale).rounded()), Int32((height * scale).rounded()))
        gtk_window_set_resizable(window, 0)

        let area = gtk_drawing_area_new()
        gtk_widget_add_events(area, EventMask.panel)
        gtk_container_add(window, area)

        onDraw(area) { [weak self] cr in
            self?.draw(cr: cr)
        }
        onButtonPress(area) { [weak self] event in
            guard let self else { return false }
            let point = Point(event.x / self.scale, event.y / self.scale)
            for region in self.hitRegions.reversed() where region.rect.contains(point) {
                region.action()
                return true
            }
            return false
        }
        onMotion(area) { [weak self] event in
            guard let self else { return false }
            self.pointer = Point(event.x / self.scale, event.y / self.scale)
            if let area = self.area { gtk_widget_queue_draw(area) }
            return false
        }
        onSignal(window, "delete-event") { [weak self] in
            // Closing without continuing leaves Ration idle, reading nothing.
            self?.dismiss()
        }

        self.window = window
        self.area = area
        gtk_widget_show_all(window)
        gtk_window_present(window)
    }

    private func dismiss() {
        if let window { gtk_widget_destroy(window) }
        self.window = nil
        Self.current = nil
    }

    private func draw(cr: OpaquePointer) {
        hitRegions.removeAll(keepingCapacity: true)
        let palette = Palette.current()
        cairo_scale(cr, scale, scale)
        let canvas = Canvas(cr: cr, palette: palette)
        canvas.fill(Rect(0, 0, width, height), palette.background)

        var y = 26.0
        Glyph.draw(
            "gauge.with.dots.needle.67percent", in: Rect(width / 2 - 20, y, 40, 40), on: canvas,
            color: palette.accent)
        y += 50
        canvas.text("Ration", at: Point(width / 2, y), size: 17, weight: .bold, align: .center)
        y += 24
        canvas.text(
            "Your AI coding usage, in the tray.", at: Point(width / 2, y), size: 12,
            color: palette.secondaryText, align: .center)
        y += 28

        canvas.separator(y: y, from: 0, to: width)
        y += 18

        let rows = [
            (
                "key.fill", "It reads sessions you already have",
                "Claude Code keeps its login in ~/.claude, Cursor in its local database, and "
                    + "Codex stamps its limits into its own session logs. Ration reads those, "
                    + "read-only, and signs in to nothing."
            ),
            (
                "eye.slash", "Only the numbers, never the words",
                "From your transcripts it takes token counts, model, timestamp, project and "
                    + "session id. Your prompts, the replies, and file contents are never "
                    + "decoded and never leave this machine."
            ),
            (
                "wifi.slash", "Two hosts, and only with your own token",
                "api.anthropic.com and api2.cursor.sh — each asked only with the token that "
                    + "host issued. No analytics, no telemetry, nothing written to disk."
            ),
        ]
        for (symbol, title, detail) in rows {
            Glyph.draw(symbol, in: Rect(24, y + 1, 16, 16), on: canvas, color: palette.accent)
            canvas.text(
                title, at: Point(48, y), size: 12, weight: .medium,
                color: palette.primary)
            y += 18
            y += canvas.paragraph(
                detail, at: Point(48, y), width: width - 72, size: 11,
                color: palette.secondaryText)
            y += 12
        }

        y = height - 54
        canvas.separator(y: y, from: 0, to: width)
        y += 14

        let sourceWidth = canvas.width("View the source", size: 12)
        let sourceRect = Rect(24, y, sourceWidth, 20)
        canvas.text(
            "View the source", at: Point(24, y), size: 12,
            color: sourceRect.contains(pointer) ? palette.primary : palette.accent)
        addHit(sourceRect) { openInBrowser(Links.repository) }

        let buttonWidth = canvas.width("Continue", size: 12, weight: .medium) + 34
        let button = Rect(width - 24 - buttonWidth, y - 4, buttonWidth, 28)
        canvas.fillRounded(button, radius: 7, palette.accent)
        canvas.text(
            "Continue", at: Point(button.midX, button.y + 6), size: 12, weight: .medium,
            color: RGBA(1, 1, 1), align: .center)
        addHit(button) { [weak self] in
            self?.app.completeOnboarding()
            self?.dismiss()
        }
    }

    private func addHit(_ rect: Rect, _ action: @escaping () -> Void) {
        hitRegions.append((rect, action))
    }
}

/// Where Ration points people. Opening one is always a click.
enum Links {
    static let repository = "https://github.com/mcpeixoto/ration"
    static let privacy = "https://github.com/mcpeixoto/ration/blob/main/PRIVACY.md"
    static let coffee = "https://buymeacoffee.com/mcpeixoto"
}
