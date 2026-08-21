import Foundation
import RationKit

/// A colour with straight alpha, in the 0…1 range Cairo wants.
struct RGBA: Equatable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double = 1

    init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    func opacity(_ alpha: Double) -> RGBA {
        RGBA(r, g, b, a * alpha)
    }

    /// The same colour, spun around the wheel. The maths lives in `ShinyPalette` so
    /// the Cairo card and the SwiftUI card cannot drift apart on it.
    func hueRotated(by degrees: Double) -> RGBA {
        let rotated = ShinyPalette.rotate(red: r, green: g, blue: b, degrees: degrees)
        return RGBA(rotated.red, rotated.green, rotated.blue, a)
    }

    /// Mixes toward another colour — used for hover states and heat maps.
    func mixed(with other: RGBA, amount: Double) -> RGBA {
        let t = min(max(amount, 0), 1)
        return RGBA(
            r + (other.r - r) * t,
            g + (other.g - g) * t,
            b + (other.b - b) * t,
            a + (other.a - a) * t)
    }
}

/// The panel's colours, resolved for the desktop's light or dark preference.
///
/// The values are the ones `RationUI/Theme.swift` declares for macOS, so the
/// two builds are recognisably the same app rather than a lookalike.
struct Palette {

    var isDark: Bool

    // MARK: Brand

    /// Claude's terracotta orange, lifted in dark mode where the daylight
    /// value goes muddy.
    var accent: RGBA {
        isDark ? RGBA(0.894, 0.545, 0.416) : RGBA(0.851, 0.467, 0.341)
    }

    var accentMuted: RGBA {
        isDark ? RGBA(0.702, 0.404, 0.294) : RGBA(0.902, 0.643, 0.545)
    }

    /// Amber, for a limit being approached. Yellower than the accent so it
    /// does not read as "normal, but bigger".
    var warning: RGBA {
        isDark ? RGBA(0.949, 0.706, 0.235) : RGBA(0.878, 0.616, 0.145)
    }

    /// Red, for a limit reached.
    var critical: RGBA {
        isDark ? RGBA(0.949, 0.365, 0.314) : RGBA(0.831, 0.239, 0.192)
    }

    // MARK: Surfaces

    /// The panel's background. macOS gets a vibrancy material behind the
    /// popover; X11 has no equivalent, so this is the solid colour the
    /// material resolves to.
    var background: RGBA {
        isDark ? RGBA(0.129, 0.129, 0.137) : RGBA(0.976, 0.976, 0.976)
    }

    var elevatedBackground: RGBA {
        isDark ? RGBA(0.169, 0.169, 0.180) : RGBA(1, 1, 1)
    }

    /// Text and marks that carry the message.
    var primary: RGBA {
        isDark ? RGBA(1, 1, 1) : RGBA(0, 0, 0)
    }

    var secondaryText: RGBA {
        primary.opacity(0.58)
    }

    var tertiaryText: RGBA {
        primary.opacity(0.38)
    }

    var separator: RGBA {
        primary.opacity(0.12)
    }

    /// The neutral fill behind gauges and bars.
    var track: RGBA {
        primary.opacity(0.09)
    }

    var controlBackground: RGBA {
        primary.opacity(0.05)
    }

    var selectedControl: RGBA {
        primary.opacity(0.09)
    }

    var hover: RGBA {
        primary.opacity(0.06)
    }

    // MARK: Charts

    var rollingAverage: RGBA {
        isDark ? RGBA(0.80, 0.80, 0.80) : RGBA(0.35, 0.35, 0.35)
    }

    var chartRule: RGBA {
        RGBA(0.55, 0.55, 0.55)
    }

    /// Calendar heat-map fill for a relative intensity of 0…1. Zero is the
    /// empty-cell colour rather than a very pale orange, so quiet days read as
    /// genuinely empty instead of faintly active.
    func heat(_ intensity: Double) -> RGBA {
        guard intensity > 0 else { return primary.opacity(0.07) }
        return accent.opacity(0.25 + 0.75 * min(intensity, 1))
    }

    /// Reads the desktop's colour-scheme preference.
    ///
    /// GNOME publishes it through GSettings; anything else falls back to dark,
    /// which is what the shell ships with on Ubuntu.
    static func current() -> Palette {
        Palette(isDark: DesktopAppearance.prefersDark())
    }
}

/// Reads GNOME's interface settings.
///
/// Cached: the panel asks on every draw and these change at human speed.
/// Spawning `gsettings` is the portable way to ask — the values live in dconf,
/// whose on-disk format is not something to parse by hand.
enum GSettings {

    nonisolated(unsafe) private static var cache: [String: (value: String?, at: Date)] = [:]
    private static let lifetime: TimeInterval = 5

    static func read(_ schema: String, _ key: String, now: Date = Date()) -> String? {
        let identifier = "\(schema) \(key)"
        if let cached = cache[identifier], now.timeIntervalSince(cached.at) < lifetime {
            return cached.value
        }
        let value = run("gsettings", ["get", schema, key])
        cache[identifier] = (value, now)
        return value
    }

    private static func run(_ tool: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [tool] + arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

enum DesktopAppearance {

    static func prefersDark() -> Bool {
        guard let scheme = GSettings.read("org.gnome.desktop.interface", "color-scheme") else {
            return true
        }
        if scheme.contains("prefer-dark") { return true }
        if scheme.contains("prefer-light") { return false }
        // "default" leaves the choice to the GTK theme name.
        guard let theme = GSettings.read("org.gnome.desktop.interface", "gtk-theme") else {
            return true
        }
        return theme.lowercased().contains("dark")
    }
}
