import AppKit
import RationKit
import SwiftUI
import UniformTypeIdentifiers

/// The collection: every creature in the set, quiet until unlocked.
public struct CollectionView: View {

    let state: DexState
    @Binding var revealedIDs: Set<String>
    var isScanning: Bool = false

    @State private var selected: Creature?
    @State private var revealQueue: [Creature] = []
    @State private var copied = false
    @State private var shareAnchor = NSView()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        state: DexState,
        revealedIDs: Binding<Set<String>>,
        isScanning: Bool = false
    ) {
        self.state = state
        self._revealedIDs = revealedIDs
        self.isScanning = isScanning
    }

    public var body: some View {
        ZStack {
            binder
            if let creature = revealQueue.first {
                CatchOverlay(
                    creature: creature,
                    remaining: revealQueue.count,
                    onContinue: advanceReveal,
                    onSkipAll: skipAllReveals,
                    share: { shareRow(creature) })
            } else if let selected {
                inspect(selected)
            }
        }
        .frame(minHeight: 420)
        .background(ShareAnchor(view: $shareAnchor))
        .onAppear(perform: queuePending)
        .onChange(of: state.caught.map(\.id)) { queuePending() }
    }

    // MARK: Binder

    private var binder: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if isScanning {
                scanning
            }
            if state.caught.isEmpty, !isScanning {
                Text("Use Claude, Codex, or Cursor — the first tokens unlock Ember.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            progress
            grid
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Pokémon")
                    .font(.subheadline.weight(.semibold))
                Text("\(state.caught.count) of \(Dex.roster.count) unlocked")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(PowerFormat.compact(state.stats.power))
                    .font(.title3.weight(.bold).monospacedDigit())
                Text("Score")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .help(
            "Score is billable tokens from every tool Ration can read, added up as a game score. "
                + "It is not a usage total — a Claude token is not a Codex token.")
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let hunt = state.nextPowerCatch {
                HStack {
                    Text("Next unlock")
                        .font(.caption2.weight(.medium))
                    Spacer()
                    Text("\(Int(hunt.progress * 100))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.track)
                        Capsule()
                            .fill(Theme.accent)
                            .frame(width: max(6, geo.size.width * hunt.progress))
                    }
                }
                .frame(height: 6)
                .accessibilityLabel("Progress to next unlock")
                .accessibilityValue("\(Int(hunt.progress * 100)) percent")
            } else if state.uncaught.isEmpty {
                Text("The set is complete.")
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
            }
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Dex.roster) { creature in
                    let caught = state.caught.contains { $0.id == creature.id }
                    Button {
                        selected = creature
                    } label: {
                        CreatureCard(
                            creature: creature, caught: caught, style: .mini,
                            foilPlaying: caught)
                    }
                    .buttonStyle(.plain)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(0.001), lineWidth: 1)
                    }
                    .accessibilityLabel(
                        caught
                            ? "\(creature.name), \(creature.rarity.label)"
                            : "Locked, \(creature.requirement.hint)")
                }
            }
            .padding(.bottom, 4)
        }
        .frame(maxHeight: .infinity)
    }

    private var columns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
        ]
    }

    private var scanning: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Reading history…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Inspect

    private func inspect(_ creature: Creature) -> some View {
        let caught = state.caught.contains { $0.id == creature.id }
        return ZStack {
            Color.black.opacity(0.82)
                .ignoresSafeArea()
                .onTapGesture { selected = nil }

            ScrollView {
                VStack(spacing: 12) {
                    CreatureCard(
                        creature: creature, caught: caught, style: .full,
                        foilPlaying: caught
                    )
                    .frame(width: 268)
                    .contentShape(Rectangle())
                    .onTapGesture { selected = nil }
                    .compositingGroup()
                    .shadow(color: .black.opacity(0.45), radius: 18, y: 8)

                    if caught {
                        shareRow(creature)
                        IntelligenceArtButton(creature: creature)
                    }

                    Button("Close") { selected = nil }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .keyboardShortcut(.cancelAction)
                }
                .padding(16)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func shareRow(_ creature: Creature) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Button(copied ? "Copied" : "Copy") { copy(creature) }
                Button("Save…") { save(creature) }
            }
            HStack(spacing: 8) {
                Button("Share…") { presentSharePicker(creature) }
                    .help("Messages, Mail, and the rest of the system share sheet")
                Button("Post on X") { postOnX(creature) }
                    .help("Copies the card image, then opens a new post with the caption")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .font(.caption)
        .tint(Theme.accent)
    }

    // MARK: Reveals

    private func queuePending() {
        guard revealQueue.isEmpty, selected == nil else { return }
        let pending = Dex.pendingReveals(
            caught: state.caught, alreadyRevealed: revealedIDs)
        if !pending.isEmpty { revealQueue = pending }
    }

    private func advanceReveal() {
        guard let current = revealQueue.first else { return }
        revealedIDs.insert(current.id)
        if reduceMotion {
            revealQueue.removeFirst()
        } else {
            withAnimation(.spring(duration: 0.45)) {
                revealQueue = Array(revealQueue.dropFirst())
            }
        }
    }

    private func skipAllReveals() {
        revealedIDs.formUnion(revealQueue.map(\.id))
        revealQueue = []
    }

    // MARK: Share

    private func rendered(_ creature: Creature) -> NSImage? {
        let view = CreatureCard(
            creature: creature, caught: true, style: .full, foilPlaying: false
        )
        .frame(width: 320, height: 440)
        .environment(\.colorScheme, .dark)
        .environment(\.rationAnimatesEntrance, false)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        return renderer.nsImage
    }

    private func copy(_ creature: Creature) {
        guard let image = rendered(creature) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { copied = false }
    }

    private func save(_ creature: Creature) {
        guard let image = rendered(creature),
            let tiff = image.tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiff),
            let png = rep.representation(using: .png, properties: [:])
        else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "\(creature.name).png"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? png.write(to: url)
        }
    }

    private func presentSharePicker(_ creature: Creature) {
        guard let image = rendered(creature) else { return }
        let text = CreatureShare.caption(for: creature, caughtCount: state.caught.count)
        let picker = NSSharingServicePicker(items: [image, text])
        picker.show(relativeTo: shareAnchor.bounds, of: shareAnchor, preferredEdge: .minY)
    }

    private func postOnX(_ creature: Creature) {
        copy(creature)
        let text = CreatureShare.caption(for: creature, caughtCount: state.caught.count)
        var comps = URLComponents(string: Links.xCompose)!
        comps.queryItems = [URLQueryItem(name: "text", value: text)]
        if let url = comps.url {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Pack-rip for newly unlocked creatures. Always has a way out.
struct CatchOverlay<Share: View>: View {
    let creature: Creature
    let remaining: Int
    let onContinue: () -> Void
    let onSkipAll: () -> Void
    let share: Share

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    init(
        creature: Creature,
        remaining: Int,
        onContinue: @escaping () -> Void,
        onSkipAll: @escaping () -> Void,
        @ViewBuilder share: () -> Share
    ) {
        self.creature = creature
        self.remaining = remaining
        self.onContinue = onContinue
        self.onSkipAll = onSkipAll
        self.share = share()
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.82).ignoresSafeArea()
                .onTapGesture(perform: onSkipAll)

            VStack(spacing: 14) {
                Text(creature.rarity.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(creature.rarity.color)

                CreatureCard(
                    creature: creature, caught: true, style: .full, foilPlaying: true
                )
                .frame(width: 252)
                .compositingGroup()
                .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
                .scaleEffect(appeared ? 1 : 0.92)
                .opacity(appeared ? 1 : 0)

                Text("Unlocked \(creature.name)")
                    .font(.headline)

                if remaining > 1 {
                    Text("\(remaining - 1) more waiting")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                share

                HStack(spacing: 12) {
                    Button(remaining > 1 ? "Next" : "Done") { onContinue() }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                        .keyboardShortcut(.defaultAction)

                    Button(remaining > 1 ? "Skip remaining" : "Skip") { onSkipAll() }
                        .buttonStyle(.borderless)
                        .keyboardShortcut(.cancelAction)
                }
                .font(.caption)
            }
            .padding(16)
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(duration: 0.45)) {
                appeared = true
            }
        }
        .onChange(of: creature.id) {
            appeared = false
            withAnimation(reduceMotion ? nil : .spring(duration: 0.4)) {
                appeared = true
            }
        }
    }
}

/// Hosts an AppKit view so `NSSharingServicePicker` has something to point at.
private struct ShareAnchor: NSViewRepresentable {
    @Binding var view: NSView

    func makeNSView(context: Context) -> NSView {
        let host = NSView(frame: .zero)
        DispatchQueue.main.async { view = host }
        return host
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { view = nsView }
    }
}
