import CLinuxTray
import Dispatch
import Foundation

/// Swift-side plumbing over the C entry points in `CLinuxTray`.
///
/// GTK hands callbacks a `void *` for context and nothing else, so every
/// closure Ration connects is boxed, retained for the lifetime of the widget,
/// and unboxed inside a `@convention(c)` trampoline.

typealias Widget = OpaquePointer

/// GTK widgets arrive as `OpaquePointer` and GLib's functions want `gpointer`.
func raw(_ pointer: OpaquePointer?) -> UnsafeMutableRawPointer? {
    pointer.map(UnsafeMutableRawPointer.init)
}

/// Holds a Swift closure alive for as long as the widget that calls it.
private final class CallbackBox {
    let action: (UnsafeMutableRawPointer?) -> Bool
    init(_ action: @escaping (UnsafeMutableRawPointer?) -> Bool) {
        self.action = action
    }
}

/// Boxes retained for the process lifetime. The tray builds its widgets once,
/// so freeing them individually would buy nothing and risk a use-after-free
/// inside a GTK callback.
nonisolated(unsafe) private var retainedBoxes: [CallbackBox] = []

private func box(_ action: @escaping (UnsafeMutableRawPointer?) -> Bool)
    -> UnsafeMutableRawPointer
{
    let box = CallbackBox(action)
    retainedBoxes.append(box)
    return Unmanaged.passUnretained(box).toOpaque()
}

private func unbox(_ pointer: UnsafeMutableRawPointer?) -> CallbackBox? {
    pointer.map { Unmanaged<CallbackBox>.fromOpaque($0).takeUnretainedValue() }
}

// MARK: - Signals

/// Connects a signal whose handler takes no arguments beyond the instance —
/// `activate`, `clicked`, `destroy`.
func onSignal(_ widget: Widget?, _ signal: String, _ handler: @escaping () -> Void) {
    let trampoline: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void = {
        _, data in
        _ = unbox(data)?.action(nil)
    }
    _ = g_signal_connect_data(
        raw(widget), signal, unsafeBitCast(trampoline, to: GCallback.self),
        box { _ in
            handler()
            return true
        }, nil, 0)
}

/// Connects `draw`, handing the closure the Cairo context for the widget.
func onDraw(_ widget: Widget?, _ handler: @escaping (OpaquePointer) -> Void) {
    let trampoline:
        @convention(c) (UnsafeMutableRawPointer?, OpaquePointer?, UnsafeMutableRawPointer?) ->
            Int32 = { _, cr, data in
                guard let cr else { return 0 }
                _ = unbox(data)?.action(UnsafeMutableRawPointer(cr))
                return 0
            }
    _ = g_signal_connect_data(
        raw(widget), "draw", unsafeBitCast(trampoline, to: GCallback.self),
        box { pointer in
            guard let pointer else { return false }
            handler(OpaquePointer(pointer))
            return true
        }, nil, 0)
}

/// A pointer or key event reduced to what the panel actually reacts to.
struct InputEvent {
    enum Kind {
        case press
        case release
        case motion
        case scroll
        case key
    }

    var kind: Kind
    var x: Double = 0
    var y: Double = 0
    var button: Int = 1
    /// Positive scrolls down the content.
    var scrollDelta: Double = 0
    var keyval: UInt32 = 0
}

private func connectEvent(
    _ widget: Widget?, _ signal: String,
    _ decode: @escaping (UnsafeMutableRawPointer) -> InputEvent?,
    _ handler: @escaping (InputEvent) -> Bool
) {
    let trampoline:
        @convention(c) (
            UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?
        ) -> Int32 = { _, event, data in
            guard let event, let box = unbox(data) else { return 0 }
            return box.action(event) ? 1 : 0
        }
    _ = g_signal_connect_data(
        raw(widget), signal, unsafeBitCast(trampoline, to: GCallback.self),
        box { pointer in
            guard let pointer, let event = decode(pointer) else { return false }
            return handler(event)
        }, nil, 0)
}

func onButtonPress(_ widget: Widget?, _ handler: @escaping (InputEvent) -> Bool) {
    connectEvent(
        widget, "button-press-event",
        { pointer in
            let event = pointer.assumingMemoryBound(to: GdkEventButton.self).pointee
            return InputEvent(kind: .press, x: event.x, y: event.y, button: Int(event.button))
        }, handler)
}

func onButtonRelease(_ widget: Widget?, _ handler: @escaping (InputEvent) -> Bool) {
    connectEvent(
        widget, "button-release-event",
        { pointer in
            let event = pointer.assumingMemoryBound(to: GdkEventButton.self).pointee
            return InputEvent(kind: .release, x: event.x, y: event.y, button: Int(event.button))
        }, handler)
}

func onMotion(_ widget: Widget?, _ handler: @escaping (InputEvent) -> Bool) {
    connectEvent(
        widget, "motion-notify-event",
        { pointer in
            let event = pointer.assumingMemoryBound(to: GdkEventMotion.self).pointee
            return InputEvent(kind: .motion, x: event.x, y: event.y)
        }, handler)
}

func onScroll(_ widget: Widget?, _ handler: @escaping (InputEvent) -> Bool) {
    connectEvent(
        widget, "scroll-event",
        { pointer in
            let event = pointer.assumingMemoryBound(to: GdkEventScroll.self).pointee
            // GDK_SCROLL_UP = 0, DOWN = 1, LEFT = 2, RIGHT = 3, SMOOTH = 4.
            let delta: Double
            switch event.direction {
            case 0: delta = -1
            case 1: delta = 1
            case 4: delta = event.delta_y
            default: delta = 0
            }
            guard delta != 0 else { return nil }
            return InputEvent(kind: .scroll, x: event.x, y: event.y, scrollDelta: delta)
        }, handler)
}

func onKeyPress(_ widget: Widget?, _ handler: @escaping (InputEvent) -> Bool) {
    connectEvent(
        widget, "key-press-event",
        { pointer in
            let event = pointer.assumingMemoryBound(to: GdkEventKey.self).pointee
            return InputEvent(kind: .key, keyval: UInt32(event.keyval))
        }, handler)
}

/// Fires when the panel loses focus, which is how a menu-bar panel is
/// dismissed — clicking anywhere else closes it.
func onFocusOut(_ widget: Widget?, _ handler: @escaping () -> Void) {
    connectEvent(
        widget, "focus-out-event", { _ in InputEvent(kind: .release) },
        { _ in
            handler()
            return false
        })
}

// MARK: - GTK event masks

enum EventMask {
    static let buttonPress: Int32 = 1 << 8
    static let buttonRelease: Int32 = 1 << 9
    static let pointerMotion: Int32 = 1 << 2
    static let keyPress: Int32 = 1 << 10
    static let scroll: Int32 = 1 << 21
    static let smoothScroll: Int32 = 1 << 23
    static let leaveNotify: Int32 = 1 << 5

    static let panel: Int32 =
        buttonPress | buttonRelease | pointerMotion | keyPress | scroll | smoothScroll
        | leaveNotify
}

// MARK: - Main loop

/// Drives GTK from the dispatch main queue rather than calling `gtk_main`.
///
/// `RationKit` polls on the main actor, whose executor on Linux is the dispatch
/// main queue. Blocking the main thread in `gtk_main()` would starve it and no
/// refresh would ever land, so the GLib loop is pumped from a repeating main
/// queue block and `dispatchMain()` owns the thread.
enum MainLoop {

    private static let pumpInterval = DispatchTimeInterval.milliseconds(8)

    static func run() -> Never {
        pump()
        dispatchMain()
    }

    private static func pump() {
        while gtk_events_pending() != 0 {
            gtk_main_iteration()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + pumpInterval) {
            pump()
        }
    }
}

// MARK: - Screen geometry

/// Where the pointer is, and the work area of the monitor holding it.
///
/// The panel opens under the tray icon, and the only position the tray
/// protocol gives us is where the click happened.
struct PointerPlacement {
    var pointerX: Int
    var pointerY: Int
    var workArea: GdkRectangle
}

func currentPointerPlacement() -> PointerPlacement? {
    guard let display = gdk_display_get_default() else { return nil }
    guard let seat = gdk_display_get_default_seat(display) else { return nil }
    guard let pointer = gdk_seat_get_pointer(seat) else { return nil }

    var x: Int32 = 0
    var y: Int32 = 0
    gdk_device_get_position(pointer, nil, &x, &y)

    var area = GdkRectangle(x: 0, y: 0, width: 1920, height: 1080)
    if let monitor = gdk_display_get_monitor_at_point(display, x, y) {
        gdk_monitor_get_workarea(monitor, &area)
    }
    return PointerPlacement(pointerX: Int(x), pointerY: Int(y), workArea: area)
}
