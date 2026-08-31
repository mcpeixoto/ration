# The Linux tray

`ration-tray` is the Linux counterpart of the macOS menu bar app. Same gauge,
same panel, same five tabs — drawn with Cairo and published to the desktop as a
StatusNotifierItem instead of SwiftUI's `MenuBarExtra`.

Everything that decides *what* to show is shared with macOS. `RationKit` owns
the polling, the history, the projections, the companion loop, and
`MenuBarPresentation`,
which turns a poll result into "this glyph, this percentage, this tint". The
tray only decides *how* to draw it.

## Layout

```
Sources/CLinuxTray/     C declarations for GTK 3, GDK, Cairo, GLib, GDBus,
                        libdbusmenu and libayatana-appindicator3 — the entry
                        points Ration calls, and nothing else.
Sources/RationTray/     The app.
  main.swift            Argument handling and the main loop.
  TrayApp.swift         Owns the registry, the icon, the menu, the windows.
  TrayIcon.swift        Draws MenuBarStrip into a PNG and publishes it.
  StatusNotifierItem.swift The tray item itself, over D-Bus.
  Panel.swift           The panel window: chrome, hit testing, scrolling.
  UsageTab.swift        Ring gauge, limit rows, the projection card.
  ActivityTab.swift     Calendar heat map, streaks, rhythm.
  TrendsTab.swift       Totals, the daily chart, the segmented controls.
  DetailTab.swift       Tokens by model and by project.
  CollectionTab.swift   Companion, binder, catch log, shop, and the overlays.
  CardFace.swift        A full trading-card face.
  CreatureArtwork.swift One illustration per CreatureArt.
  SettingsWindow.swift  General, Accounts, About.
  OnboardingWindow.swift The welcome screen.
  Canvas.swift          Cairo drawing: shapes, text, measurement.
  Glyphs.swift          Line drawings standing in for SF Symbols.
  Palette.swift         Theme.swift's colours, resolved light or dark.
  Motion.swift          When to animate, and at what rate.
  UIScale.swift         Reads the display's density and the user's preference.
  AppIcon.swift         Draws the application icon.
```

## Why it is drawn rather than assembled

The macOS panel is one SwiftUI hierarchy with custom gauges, charts and cards.
Rebuilding that out of stock GTK widgets would produce a program that behaves
like Ration and looks like something else. So the panel is a single
`GtkDrawingArea`, redrawn from scratch each frame, and the rectangles that
respond to a click are recorded as the frame is drawn — layout and hit testing
stay in one place instead of two that drift apart.

Text is drawn with Cairo's font API at greyscale antialiasing. The subpixel
default assumes it knows the physical order of the display's stripes; in an
ARGB surface composited by the shell, it does not, and grey body copy comes out
faintly orange.

## SF Symbols

`MenuBarPresentation` names its glyph as an SF Symbol, which is the right
currency on macOS and means nothing here. Rather than fork that logic,
`Glyphs.swift` keeps the same names and draws each one, so a symbol added on
the Mac side shows up as a recognisable mark rather than a blank.

## The main loop

`RationKit` polls on the main actor, whose executor on Linux is the dispatch
main queue. Blocking the main thread in `gtk_main()` would starve it and no
refresh would ever land, so `MainLoop` pumps the GLib loop from a repeating
main-queue block and `dispatchMain()` owns the thread.

## The icon

The StatusNotifierItem protocol takes an icon by name from a theme directory,
so each refresh draws a PNG into `~/.cache/ration/tray` and points the item at
it, then emits `NewIcon`. The name alternates between two slots: a host ignores
a re-set of the name it already has, even when the file behind it changed.

The application icon is drawn too — `ration-tray --write-icon <path>` renders
the same terracotta squircle `Scripts/make-icon.swift` draws for macOS, so no
binary blob has to be checked in.

## The click

The item is Ration's own D-Bus object — `StatusNotifierItem.swift` — rather
than one built by libayatana-appindicator, for one reason: the protocol has an
`Activate` method that a host calls when the icon is clicked, and libayatana
never published one. Unity always showed the menu, so every host fell back to
it and reaching the panel cost a second click on "Open Ration".

What the item publishes at `/StatusNotifierItem`:

| | |
|---|---|
| `Activate` | opens the panel, or closes it |
| `SecondaryActivate`, `XAyatanaSecondaryActivate` | the same, for a middle click |
| `ContextMenu` | pops the GtkMenu up itself, for a host that asks rather than reading the exported one |
| `Menu` | `/StatusNotifierItem/Menu`, the same GtkMenu exported by libdbusmenu |
| `ItemIsMenu` | false, so a host offers the icon's own click |

Only the item is ours. The menu behind it is still a `GtkMenu`, handed to
`dbusmenu_gtk_parse_menu_structure`, which keeps watching the widgets — the
limit summary is rewritten on every poll and travels on its own.

The bus name is `org.kde.StatusNotifierItem-<pid>-1`, and hosts are *watched*
rather than told once: a shell restart drops every item it knew about and
expects them to register again.

What a host does with the click is still the host's business. KDE, XFCE, waybar
and swaybar call `Activate` on a plain click. GNOME's appindicator extension
hardwires a single click to the menu and calls `Activate` on a double click, so
there the panel is two quick clicks away — one better than before, and as close
as that shell allows.

libayatana-appindicator is kept as the fallback for a desktop with no
StatusNotifier host on the bus — a bare window manager with an XEmbed tray —
because it can still put an icon in one. `StatusNotifierItem.isSupported()`
asks the bus who owns `org.kde.StatusNotifierWatcher` and decides.

## Building without -dev packages

Ubuntu splits these libraries into runtime and `-dev` packages, and not every
machine can install the second half. `Sources/CLinuxTray` declares the C
entry points itself, so only the runtime `.so` files are needed at build time.
On a machine without the headers:

```sh
# sqlite3.h, from the amalgamation
curl -sLO https://www.sqlite.org/2025/sqlite-amalgamation-3490100.zip
unzip -j sqlite-amalgamation-3490100.zip '*/sqlite3.h' -d ~/.local/include

# .so symlinks the linker looks for
for lib in gtk-3.so.0 gdk-3.so.0 gobject-2.0.so.0 glib-2.0.so.0 \
           gio-2.0.so.0 cairo.so.2 dbusmenu-glib.so.4 dbusmenu-gtk3.so.4 \
           ayatana-appindicator3.so.1 sqlite3.so.0; do
  ln -sf "/usr/lib/x86_64-linux-gnu/lib$lib" \
     "$HOME/.local/lib/lib${lib%%.so*}.so"
done

swift build -c release --product ration-tray \
  -Xcc -I"$HOME/.local/include" -Xlinker -L"$HOME/.local/lib"
```

`Scripts/bundle-linux.sh` finds a `~/.local` prefix on its own; set
`RATION_PREFIX` to point it somewhere else, or `RATION_BUILD_FLAGS` to add
flags of your own.

## Scale

The panel's geometry is written in the macOS popover's units — 340 across, 11pt
type. On a Mac a point is a physical size the system keeps constant; on X11 it
is whatever the screen makes of it, and on a 27" 4K display 340 device pixels
is about four centimetres of glass.

So the tray works out a factor of its own and multiplies everything by it at
draw time. Vectors, so nothing softens. Three inputs:

1. **Display density.** `UIScalePolicy.scale(forDPI:)` maps the monitor's real
   DPI onto steps — 1×, 1.25×, 1.5×, 2×. Steps rather than a ratio: a panel
   1.37× the width of the last one looks like a mistake, and fractional strokes
   shimmer. A monitor that does not report a believable physical size is left
   at 1× rather than guessed at.
2. **GNOME's text-scaling factor**, multiplied on top.
3. **The `uiScale` setting** — Settings → Size, or `ration config set uiScale`
   — which replaces the two above when it is not `auto`.

GTK applies whole-number `scale-factor` to the surface itself, so only the
remainder belongs to us; `UIScalePolicy.remainder` divides it out. Pointer
events arrive in pixels and are divided back into logical units before hit
testing, so the two never drift.

The panel's own maximum height is bounded by the monitor it opens on as well as
by the 700-unit ceiling: 700 units at 1.875× is 1312 pixels, taller than a
1200-pixel laptop display, and a panel that does not fit is worse than one that
scrolls.

The policy lives in `RationKit` and is unit-tested; only the reading of the
monitor and GSettings is in the tray.

## Animation

A Cairo frame is a still, so anything that moves is the panel redrawing itself.
`Motion` decides when that is worth doing:

- **Holographic foil** on every caught card above common — a wheel of the
  rarity's colours turning under a travelling highlight, both in overlay, as on
  the Mac. Cairo has no angular gradient, so the wheel is 48 wedges.
- **The catch overlay's spring**: a newly unlocked card arrives at 92% and
  settles, faded in over the same 0.45s.
- **Entrances**: the ring sweeps up to its value and counts with it, limit bars
  and share bars fill. Restarted when the panel opens and when the tab or the
  account changes — the equivalent of a SwiftUI view re-running `onAppear`.

Frames are asked for at 24fps, the rate the macOS `TimelineView` uses, and only
while something is moving: the binder animates for as long as it is open
because foil never settles, every other tab stops after its entrance, and a
closed panel does no work at all.

`org.gnome.desktop.interface enable-animations` turns the lot off, the way the
Mac honours Reduce Motion. The curves live in `RationKit` as `MotionCurve`,
where they are tested.

The foil is deliberately weaker than the macOS values it is copied from.
SwiftUI blends it inside the card's own compositing group; Cairo blends against
the finished pixels, which lands heavier for the same numbers, and a card you
cannot see the illustration through is not shiny — it is fogged.

## Type and marks

The panel draws with the desktop's own UI font, read from
`org.gnome.desktop.interface font-name`. Only the family is taken: the panel's
type scale is its own, and adopting the desktop's point size would resize every
label independently of the layout around it.

Which is why the cards' energy and rarity marks are drawn as paths rather than
typed. `CreatureEnergy.glyph` names characters like ▲ ◉ ▣ ⟳ ☽ ⬢, and a UI font
is under no obligation to have them — Ubuntu Sans does not, and every pip on
every card came out as a tofu box.

The trap is worse than a missing family, because Cairo's *toy* text API does no
font fallback at all: a glyph the selected family lacks draws as a box even when
another font on the machine has it. `fc-match` will happily tell you U+2192 is
available and the panel will still show a box. The shiny mark went the same way
(`CardFace.drawShinyMark` is a path for that reason), and the catch log separates
an evolution chain with `›` rather than `→`.

`SourceTreeTests.trayTextAvoidsTofu` now holds the line: it scans every string
literal under `Sources/RationTray` and fails on anything outside Latin-1 plus a
short list checked against Ubuntu Sans one codepoint at a time. Anything else
needs a drawn path.

## Looking at what it draws

```sh
ration-tray --screenshot ./shots
```

Renders every tab, all four collection segments, the card inspector, the
pack-rip overlay and the tray mark in both appearances, straight to PNGs at the
configured scale and exits. The collection is posed from `CompanionState.posed()`
rather than read from a profile, because three of its four screens are months of
play away from having anything in them. No display needed — the same
two-pass measure-then-draw the live panel uses, into an image surface instead
of a window. This is the Linux counterpart of `swift run RationPreview
docs/images`, and it is how the panel's states get checked.

## The Cursor database

`state.vscdb` holds the session token Ration reads, and it is a working
database Cursor grows without bound — 11 GB on the machine this was written on.
The original code copied it to the temp directory before reading two rows, on
every poll: minutes of I/O, gigabytes of disk, and a copy left behind whenever
the process was killed mid-read. Ninety of those had accumulated to 42 GB.

It is now opened read-only in place. The copy remains as a fallback for when
SQLite refuses the live file, and every copy sweeps abandoned ones first, so a
killed run cleans up after the next one rather than never.

## Settings

The tray and the CLI share one settings file — `~/.config/ration/config.json`,
modelled by `AppConfig` in `RationKit`. Both re-read it before writing, so the
one that saves last does not undo what the other recorded in between.

macOS keeps the same values in `UserDefaults`, which its app and Settings
window both read; Linux has two front ends over the same data, so a setting
changed in `ration config set` shows up in the tray, and one changed in the
tray's Settings window shows up in `ration config show`. There is no setting
reachable from only one of them.

Launch at login is an XDG autostart entry at
`~/.config/autostart/ration-tray.desktop`. The CLI's `ration service install`
writes a systemd user unit for `ration watch` instead; they are independent, and
running both would meter twice.

## Updates

macOS installs updates itself through Sparkle, which fetches
`appcast.xml` and verifies the download against a signing key compiled into the
app. A Linux tarball has no equivalent installer, so `UpdateFeedClient` reads
the same feed, reports the newest version in Settings, and leaves installing it
to you. It sends no credential and downloads nothing.

Deliberately the same feed rather than the GitHub API: a second update host in
a program whose promise is "three hosts, all listed" would be a poor trade for
a version string. A test pins the URL on both sides.

## What differs from macOS

| | macOS | Linux |
|---|---|---|
| Gauge | `MenuBarExtra` | StatusNotifierItem, PNG per refresh |
| Panel | SwiftUI popover | GTK window, drawn with Cairo |
| Opens on | click on the item | click on the item, where the host offers it — double click on GNOME; middle click, or "Open Ration" in the menu, anywhere |
| Card art | Image Playground can redraw a card | drawn art only |
| Companion in the gauge | not shown — the menu bar item is a template image, and a coloured creature would cost the system tinting | drawn beside the number |
| Size | points, resolved by AppKit | display density, or Settings → Size |
| Updates | installed by Sparkle | reported, installed by you |
| Launch at login | `SMAppService` | XDG autostart entry |

The tray opens the panel under the pointer, which is where the click on the
item happened. The coordinates a host passes to `Activate` are documented as
"an hint" and are empty on GNOME, so the pointer is the closest available
anchor.
