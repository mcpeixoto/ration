import CLinuxTray
import Foundation

/// Ration's own tray item, published over D-Bus as an
/// `org.kde.StatusNotifierItem`.
///
/// The protocol has an `Activate` method that a host calls when the icon is
/// clicked, which is how a tray item behaves like the macOS menu bar extra:
/// click, panel. libayatana-appindicator never published one — Unity always
/// showed the menu — so every host fell back to the menu and reaching the
/// panel cost a second click on "Open Ration". Publishing the item here is a
/// D-Bus object and a name, and it buys that click back.
///
/// The menu stays behind libdbusmenu, which already knows how to export a
/// `GtkMenu`; only the item itself is ours.
///
/// What a host does with the click is still the host's business. KDE, XFCE,
/// waybar and swaybar call `Activate` on a plain click. GNOME's appindicator
/// extension hardwires a single click to the menu and `Activate` only on a
/// double click — so for GNOME, `about-to-show` on the menu root opens the
/// panel and briefly hides the menu items, which is as close to a Mac click
/// as that shell allows without a custom extension.
final class StatusNotifierItem {

    /// What a host can ask the item to do.
    struct Actions {
        /// A plain click on the icon (x, y may be zero when the host sends none).
        var activate: (_ x: Int, _ y: Int) -> Void
        /// A middle click.
        var secondaryActivate: (_ x: Int, _ y: Int) -> Void
        /// A right click, on a host that leaves the menu to the application
        /// instead of reading the exported one.
        var contextMenu: () -> Void
        /// Wayland / startup-notification token from `ProvideXdgActivationToken`.
        var activationToken: (_ token: String) -> Void
    }

    /// The path a host looks at when it is handed a bus name and nothing else.
    private static let objectPath = "/StatusNotifierItem"
    private static let menuPath = "/StatusNotifierItem/Menu"
    private static let interfaceName = "org.kde.StatusNotifierItem"
    private static let watcherName = "org.kde.StatusNotifierWatcher"
    private static let watcherPath = "/StatusNotifierWatcher"

    /// The one item this process publishes.
    ///
    /// GDBus hands its callbacks a `void *` for context, but a tray has
    /// exactly one item for the life of the process, and a global is easier to
    /// be sure about than a pointer round trip through C.
    nonisolated(unsafe) fileprivate static var live: StatusNotifierItem?

    private let connection: OpaquePointer
    private let id: String
    private let actions: Actions
    private let iconThemePath: String

    /// The name the watcher is told to look up. The well-known one while it is
    /// ours; the connection's unique name if something else already holds it.
    private var serviceName: String
    private let wellKnownName: String

    private var iconName: String
    private var title: String
    private var menuServer: OpaquePointer?
    private var menuRoot: OpaquePointer?
    private var isPublished = false
    private var isWatching = false
    /// When true, the next `about-to-show` leaves the menu alone (ContextMenu).
    private var allowMenuShow = false

    // MARK: Availability

    /// Whether a host is on the bus to show the item.
    ///
    /// A desktop with no watcher — GNOME without the appindicator extension, a
    /// bare window manager with an XEmbed tray — is better served by
    /// libayatana-appindicator, which falls back to a legacy tray icon.
    static func isSupported() -> Bool {
        guard let connection = sessionBus() else { return false }
        guard
            let reply = call(
                connection, bus: "org.freedesktop.DBus", path: "/org/freedesktop/DBus",
                interface: "org.freedesktop.DBus", method: "NameHasOwner",
                argument: g_variant_new_string(watcherName))
        else { return false }
        defer { g_variant_unref(reply) }
        guard let first = g_variant_get_child_value(reply, 0) else { return false }
        defer { g_variant_unref(first) }
        return g_variant_get_boolean(first) != 0
    }

    private static func sessionBus() -> OpaquePointer? {
        var error: UnsafeMutablePointer<GError>?
        // G_BUS_TYPE_SESSION
        let connection = g_bus_get_sync(2, nil, &error)
        if let error {
            g_error_free(error)
            return nil
        }
        return connection
    }

    /// One blocking call with one argument, for the two questions asked before
    /// the item is on the bus.
    private static func call(
        _ connection: OpaquePointer, bus: String, path: String, interface: String,
        method: String, argument: OpaquePointer?
    ) -> OpaquePointer? {
        var error: UnsafeMutablePointer<GError>?
        let reply = withTuple(argument) { parameters in
            g_dbus_connection_call_sync(
                connection, bus, path, interface, method, parameters, nil, 0, 2000, nil, &error)
        }
        if let error {
            g_error_free(error)
            return nil
        }
        return reply
    }

    /// Wraps one value in the single-element tuple a D-Bus call takes.
    private static func withTuple<T>(
        _ value: OpaquePointer?, _ body: (OpaquePointer?) -> T
    ) -> T {
        let children: [OpaquePointer?] = [value]
        return children.withUnsafeBufferPointer { buffer in
            body(g_variant_new_tuple(buffer.baseAddress, 1))
        }
    }

    // MARK: Lifecycle

    init?(id: String, title: String, iconName: String, iconThemePath: String, actions: Actions) {
        guard let connection = Self.sessionBus() else { return nil }
        self.connection = connection
        self.id = id
        self.title = title
        self.iconName = iconName
        self.iconThemePath = iconThemePath
        self.actions = actions
        let pid = ProcessInfo.processInfo.processIdentifier
        wellKnownName = "org.kde.StatusNotifierItem-\(pid)-1"
        serviceName = wellKnownName

        var error: UnsafeMutablePointer<GError>?
        guard let node = g_dbus_node_info_new_for_xml(Self.introspection, &error),
            let interface = g_dbus_node_info_lookup_interface(node, Self.interfaceName)
        else {
            if let error { g_error_free(error) }
            return nil
        }

        // Read for as long as the object is registered, which is the life of
        // the process, so the table is deliberately never freed.
        let vtable = UnsafeMutablePointer<GDBusInterfaceVTable>.allocate(capacity: 1)
        vtable.initialize(to: GDBusInterfaceVTable())
        vtable.pointee.method_call = { _, _, _, _, method, parameters, invocation, _ in
            guard let method else { return }
            StatusNotifierItem.live?.handle(
                method: String(cString: method), parameters: parameters, invocation: invocation)
        }
        vtable.pointee.get_property = { _, _, _, _, property, _, _ in
            guard let property else { return nil }
            return StatusNotifierItem.live?.property(String(cString: property))
        }

        guard
            g_dbus_connection_register_object(
                connection, Self.objectPath, interface, vtable, nil, nil, &error) != 0
        else {
            if let error { g_error_free(error) }
            vtable.deallocate()
            return nil
        }

        Self.live = self
    }

    /// Exports the menu a host shows on a right click — and, on GNOME, also
    /// the menu a single left click opens. `about-to-show` turns that left
    /// click into a panel toggle.
    ///
    /// Called before `publish()`: a host reads `Id` and `Menu` first and gives
    /// up on an item whose menu is not answering yet.
    func attach(menu: Widget?) {
        guard let menu else { return }
        if menuServer == nil { menuServer = dbusmenu_server_new(Self.menuPath) }
        // The parser keeps watching the GtkMenu, so later label changes — the
        // limit summary is rewritten on every poll — travel on their own.
        let root = dbusmenu_gtk_parse_menu_structure(menu)
        menuRoot = root
        dbusmenu_server_set_root(menuServer, root)
        onAboutToShow(root) { [weak self] in
            self?.handleAboutToShow() ?? false
        }
    }

    /// Lets `ContextMenu` show the real menu instead of opening the panel.
    func beginContextMenu() {
        allowMenuShow = true
        setMenuChildrenVisible(true)
    }

    func endContextMenu() {
        allowMenuShow = false
    }

    /// Takes the item's bus name, then tells every host that appears about it.
    ///
    /// Hosts are watched rather than called once: a shell restart drops every
    /// item it knew about and expects them to come back on their own.
    func publish() {
        guard !isPublished else { return }
        isPublished = true
        _ = g_bus_own_name_on_connection(
            connection, wellKnownName, 0,
            { _, _, _ in StatusNotifierItem.live?.watchForHosts() },
            { _, _, _ in
                // Something else holds the name; the unique one works too.
                StatusNotifierItem.live?.fallBackToUniqueName()
            }, nil, nil)
    }

    private func watchForHosts() {
        guard !isWatching else { return }
        isWatching = true
        _ = g_bus_watch_name_on_connection(
            connection, Self.watcherName, 0,
            { _, _, _, _ in StatusNotifierItem.live?.register() }, nil, nil, nil)
    }

    private func fallBackToUniqueName() {
        if let unique = g_dbus_connection_get_unique_name(connection) {
            serviceName = String(cString: unique)
        }
        watchForHosts()
    }

    private func register() {
        g_dbus_connection_call(
            connection, Self.watcherName, Self.watcherPath, Self.watcherName,
            "RegisterStatusNotifierItem",
            Self.withTuple(g_variant_new_string(serviceName)) { $0 },
            nil, 0, -1, nil, nil, nil)
    }

    // MARK: Contents

    /// Points the item at a freshly drawn icon.
    ///
    /// The name has to change for a host to look again — several cache by name
    /// — which is why the drawing side alternates between two of them.
    func set(iconName: String, title: String) {
        if iconName != self.iconName {
            self.iconName = iconName
            emit("NewIcon")
        }
        if title != self.title {
            self.title = title
            emit("NewTitle")
        }
    }

    private func emit(_ signal: String) {
        var error: UnsafeMutablePointer<GError>?
        _ = g_dbus_connection_emit_signal(
            connection, nil, Self.objectPath, Self.interfaceName, signal, nil, &error)
        if let error { g_error_free(error) }
    }

    // MARK: The interface

    fileprivate func property(_ name: String) -> OpaquePointer? {
        switch name {
        case "Category": return g_variant_new_string("ApplicationStatus")
        case "Id": return g_variant_new_string(id)
        case "Title": return g_variant_new_string(title)
        case "Status": return g_variant_new_string("Active")
        case "WindowId": return g_variant_new_int32(0)
        case "IconName": return g_variant_new_string(iconName)
        case "IconThemePath": return g_variant_new_string(iconThemePath)
        case "IconAccessibleDesc": return g_variant_new_string(title)
        case "AttentionIconName": return g_variant_new_string("")
        case "OverlayIconName": return g_variant_new_string("")
        // False, so a host offers the icon's own click rather than treating
        // the whole item as a menu button.
        case "ItemIsMenu": return g_variant_new_boolean(0)
        case "Menu": return g_variant_new_object_path(Self.menuPath)
        default: return nil
        }
    }

    fileprivate func handle(
        method: String, parameters: OpaquePointer?, invocation: OpaquePointer?
    ) {
        switch method {
        case "Activate":
            let point = Self.pointArgs(parameters)
            actions.activate(point.x, point.y)
        case "SecondaryActivate":
            let point = Self.pointArgs(parameters)
            actions.secondaryActivate(point.x, point.y)
        case "XAyatanaSecondaryActivate":
            actions.secondaryActivate(0, 0)
        case "ContextMenu":
            beginContextMenu()
            actions.contextMenu()
            // The GtkMenu is modal for the click; restore the GNOME path after.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                StatusNotifierItem.live?.endContextMenu()
            }
        case "ProvideXdgActivationToken":
            if let token = Self.stringArg(parameters) {
                actions.activationToken(token)
            }
        case "Scroll":
            break
        default:
            break
        }
        // Every method the interface declares returns nothing.
        g_dbus_method_invocation_return_value(invocation, nil)
    }

    /// GNOME left-click opens the dbusmenu after a double-click wait. Turn that
    /// into a panel toggle and hide the items so the popup is empty.
    private func handleAboutToShow() -> Bool {
        if allowMenuShow {
            setMenuChildrenVisible(true)
            return false
        }
        actions.activate(0, 0)
        setMenuChildrenVisible(false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            StatusNotifierItem.live?.setMenuChildrenVisible(true)
        }
        return true
    }

    private func setMenuChildrenVisible(_ visible: Bool) {
        guard let root = menuRoot else { return }
        var node = dbusmenu_menuitem_get_children(root)
        while let current = node {
            if let data = current.pointee.data {
                _ = dbusmenu_menuitem_property_set_bool(
                    OpaquePointer(data), "visible", visible ? 1 : 0)
            }
            node = current.pointee.next
        }
    }

    private static func pointArgs(_ parameters: OpaquePointer?) -> (x: Int, y: Int) {
        guard let parameters else { return (0, 0) }
        let x = g_variant_get_child_value(parameters, 0).map { value -> Int in
            defer { g_variant_unref(value) }
            return Int(g_variant_get_int32(value))
        } ?? 0
        let y = g_variant_get_child_value(parameters, 1).map { value -> Int in
            defer { g_variant_unref(value) }
            return Int(g_variant_get_int32(value))
        } ?? 0
        return (x, y)
    }

    private static func stringArg(_ parameters: OpaquePointer?) -> String? {
        guard let parameters,
            let first = g_variant_get_child_value(parameters, 0)
        else { return nil }
        defer { g_variant_unref(first) }
        guard let cString = g_variant_get_string(first, nil) else { return nil }
        return String(cString: cString)
    }

    /// The interface as the host reads it. `Activate` being present is what
    /// tells a host the icon's own click is worth offering, so the shape of
    /// this document is the whole point of the class.
    private static let introspection = """
        <node>
          <interface name="org.kde.StatusNotifierItem">
            <property name="Category" type="s" access="read"/>
            <property name="Id" type="s" access="read"/>
            <property name="Title" type="s" access="read"/>
            <property name="Status" type="s" access="read"/>
            <property name="WindowId" type="i" access="read"/>
            <property name="IconName" type="s" access="read"/>
            <property name="IconThemePath" type="s" access="read"/>
            <property name="IconAccessibleDesc" type="s" access="read"/>
            <property name="AttentionIconName" type="s" access="read"/>
            <property name="OverlayIconName" type="s" access="read"/>
            <property name="ItemIsMenu" type="b" access="read"/>
            <property name="Menu" type="o" access="read"/>
            <method name="Activate">
              <arg name="x" type="i" direction="in"/>
              <arg name="y" type="i" direction="in"/>
            </method>
            <method name="SecondaryActivate">
              <arg name="x" type="i" direction="in"/>
              <arg name="y" type="i" direction="in"/>
            </method>
            <method name="XAyatanaSecondaryActivate">
              <arg name="timestamp" type="u" direction="in"/>
            </method>
            <method name="ContextMenu">
              <arg name="x" type="i" direction="in"/>
              <arg name="y" type="i" direction="in"/>
            </method>
            <method name="Scroll">
              <arg name="delta" type="i" direction="in"/>
              <arg name="orientation" type="s" direction="in"/>
            </method>
            <method name="ProvideXdgActivationToken">
              <arg name="token" type="s" direction="in"/>
            </method>
            <signal name="NewIcon"/>
            <signal name="NewTitle"/>
          </interface>
        </node>
        """
}
