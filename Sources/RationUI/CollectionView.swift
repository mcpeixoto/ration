import AppKit
import RationKit
import SwiftUI
import UniformTypeIdentifiers

/// Which part of the collection is showing.
enum CollectionSegment: String, CaseIterable, Identifiable {
    case companion, binder, log, shop

    var id: String { rawValue }

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
struct CompanionReveal: Identifiable {
    enum Kind { case ripped, filed }

    let id = UUID()
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
public struct CollectionView: View {

    @Bindable var model: CompanionModel
    var isScanning: Bool = false

    @State private var segment: CollectionSegment = .companion
    @State private var selected: Creature?
    @State private var revealQueue: [CompanionReveal] = []
    @State private var celebration = 0
    @State private var copied = false
    @State private var shareAnchor = NSView()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(model: CompanionModel, isScanning: Bool = false) {
        self.model = model
        self.isScanning = isScanning
    }

    private var state: CompanionState { model.state }

    public var body: some View {
        ZStack {
            content(for: segment)
            if let reveal = revealQueue.first {
                CatchOverlay(
                    reveal: reveal,
                    remaining: revealQueue.count,
                    onContinue: advanceReveal,
                    onSkipAll: { revealQueue = [] },
                    share: { shareRow(reveal.creature) })
            } else if let selected {
                inspect(selected)
            }
        }
        .frame(minHeight: 420)
        .background(ShareAnchor(view: $shareAnchor))
        .onAppear(perform: drainEvents)
        .onChange(of: model.events.count) { drainEvents() }
    }

    @ViewBuilder
    private func content(for segment: CollectionSegment) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            picker
            if isScanning { scanning }
            switch segment {
            case .companion: companion
            case .binder: binder
            case .log:
                ScrollView { CatchLogView(state: state) { selected = $0 }.padding(.bottom, 4) }
            case .shop:
                ScrollView {
                    ShopView(state: state, buy: model.buy, use: model.use).padding(.bottom, 4)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var picker: some View {
        Picker("", selection: $segment) {
            ForEach(CollectionSegment.allCases) { segment in
                Text(segment.title).tag(segment)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var scanning: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Reading history…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Companion

    private var companion: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                CompanionHeaderView(state: state, celebration: celebration)
                Divider()
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(state.filedSpecies.count) of \(Dex.roster.count) filed")
                            .font(.caption.weight(.medium))
                        let archived = state.archive.subtracting(state.filedSpecies).count
                        if archived > 0 {
                            Text("\(archived) from Set 01")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(PowerFormat.compact(state.wallet))
                            .font(.title3.weight(.bold).monospacedDigit())
                        Text("Wallet")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                let held = state.heldItems.map { "\($0.kind.label) ×\($0.count)" }
                if !held.isEmpty {
                    Text(held.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 4)
        }
    }

    // MARK: Binder

    private var binder: some View {
        VStack(alignment: .leading, spacing: 8) {
            let filed = state.filedSpecies
            let archived = state.archive.subtracting(filed)
            HStack(alignment: .firstTextBaseline) {
                Text("\(filed.count) of \(Dex.roster.count) filed")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if !archived.isEmpty {
                    Text("Set 01 archive — \(archived.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if filed.isEmpty, !isScanning {
                Text("Nothing filed yet. Burn tokens, rip the pack, and raise what comes out.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            grid(filed: filed, archived: archived)
        }
    }

    private func grid(filed: Set<String>, archived: Set<String>) -> some View {
        let shinySpecies = Set(state.log.filter(\.isShiny).flatMap(\.chain))
        return ScrollView {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Dex.roster) { creature in
                    let isFiled = filed.contains(creature.id)
                    let isArchived = archived.contains(creature.id)
                    Button {
                        selected = creature
                    } label: {
                        CreatureCard(
                            creature: creature, caught: isFiled || isArchived, style: .mini,
                            foilPlaying: isFiled || isArchived,
                            shiny: shinySpecies.contains(creature.id),
                            archived: isArchived)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 4)
        }
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
    }

    // MARK: Inspect

    private func inspect(_ creature: Creature) -> some View {
        let caught =
            state.filedSpecies.contains(creature.id) || state.archive.contains(creature.id)
        let shiny = state.log.contains { $0.isShiny && $0.chain.contains(creature.id) }
        return ZStack {
            Color.black.opacity(0.82)
                .ignoresSafeArea()
                .onTapGesture { selected = nil }

            ScrollView {
                VStack(spacing: 12) {
                    CreatureCard(
                        creature: creature, caught: caught, style: .full,
                        foilPlaying: caught, shiny: shiny,
                        archived: state.archive.contains(creature.id)
                            && !state.filedSpecies.contains(creature.id)
                    )
                    .frame(width: Theme.popoverWidth - 32)
                    // Deliberately not a dismiss target. You opened this to
                    // look at it, and a card that closes wherever you click is
                    // one you cannot read, tilt, or reach the buttons under
                    // without losing. The scrim, Close, and Escape all exit.
                    .compositingGroup()
                    .shadow(color: .black.opacity(0.45), radius: 18, y: 8)

                    if caught {
                        shareRow(creature)
                        IntelligenceArtButton(creature: creature)
                        pinButton(creature)
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

    /// Only offered for cards they hold — the menu bar should never show a creature
    /// they have not seen.
    private func pinButton(_ creature: Creature) -> some View {
        let pinned = state.pinnedID == creature.id
        return Button(pinned ? "Unpin" : "Pin to the menu bar") {
            model.mutate { state in
                state.pinnedID = pinned ? nil : creature.id
                return []
            }
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .font(.caption)
        .tint(Theme.accent)
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

    /// Turn what the engine reported into things to show. Rips and filings stop the
    /// tab for a card; an evolution only flashes the header, because interrupting for
    /// every step of a three-form line would be four interruptions per creature.
    private func drainEvents() {
        guard !model.events.isEmpty, selected == nil else { return }
        var queued: [CompanionReveal] = []
        var sawCelebration = false
        for event in model.takeEvents() {
            switch event {
            case .ripped(let id, let shiny):
                if let creature = Dex.creature(id) {
                    queued.append(CompanionReveal(creature: creature, kind: .ripped, shiny: shiny))
                }
                sawCelebration = true
            case .filed(let id, let shiny, _):
                if let creature = Dex.creature(id) {
                    queued.append(CompanionReveal(creature: creature, kind: .filed, shiny: shiny))
                }
                sawCelebration = true
            case .evolved:
                sawCelebration = true
            case .granted, .bought, .boosted, .traitRolled:
                break
            }
        }
        revealQueue += queued
        if sawCelebration { celebration += 1 }
    }

    private func advanceReveal() {
        guard !revealQueue.isEmpty else { return }
        if reduceMotion {
            revealQueue.removeFirst()
        } else {
            withAnimation(.spring(duration: 0.45)) {
                revealQueue = Array(revealQueue.dropFirst())
            }
        }
    }

    // MARK: Share

    private func rendered(_ creature: Creature) -> NSImage? {
        let shiny = state.log.contains { $0.isShiny && $0.chain.contains(creature.id) }
        let view = CreatureCard(
            creature: creature, caught: true, style: .full, foilPlaying: false, shiny: shiny
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
        let text = CreatureShare.caption(
            for: creature, caughtCount: state.filedSpecies.count)
        let picker = NSSharingServicePicker(items: [image, text])
        picker.show(relativeTo: shareAnchor.bounds, of: shareAnchor, preferredEdge: .minY)
    }

    private func postOnX(_ creature: Creature) {
        copy(creature)
        let text = CreatureShare.caption(
            for: creature, caughtCount: state.filedSpecies.count)
        var comps = URLComponents(string: Links.xCompose)!
        comps.queryItems = [URLQueryItem(name: "text", value: text)]
        if let url = comps.url {
            NSWorkspace.shared.open(url)
        }
    }
}

/// The pack-rip: one card at a time, as it happens. Always has a way out.
struct CatchOverlay<Share: View>: View {
    let reveal: CompanionReveal
    let remaining: Int
    let onContinue: () -> Void
    let onSkipAll: () -> Void
    let share: Share

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    init(
        reveal: CompanionReveal,
        remaining: Int,
        onContinue: @escaping () -> Void,
        onSkipAll: @escaping () -> Void,
        @ViewBuilder share: () -> Share
    ) {
        self.reveal = reveal
        self.remaining = remaining
        self.onContinue = onContinue
        self.onSkipAll = onSkipAll
        self.share = share()
    }

    var body: some View {
        ZStack {
            // Advance rather than skip: tapping past one card is a small
            // action, throwing away every card still queued is not, and the
            // two should not share a gesture.
            Color.black.opacity(0.82).ignoresSafeArea()
                .onTapGesture(perform: onContinue)

            VStack(spacing: 14) {
                Text(reveal.headline)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)

                CreatureCard(
                    creature: reveal.creature, caught: true, style: .full, foilPlaying: true,
                    shiny: reveal.shiny
                )
                .frame(width: Theme.popoverWidth - 48)
                .compositingGroup()
                .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
                .scaleEffect(appeared ? 1 : 0.92)
                .opacity(appeared ? 1 : 0)

                HStack(spacing: 5) {
                    if reveal.shiny {
                        Image(systemName: "sparkle").font(.system(size: 11))
                    }
                    Text(reveal.creature.name)
                        .font(.headline)
                }
                .foregroundStyle(
                    reveal.shiny ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.primary))

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
        .onChange(of: reveal.id) {
            appeared = false
            withAnimation(reduceMotion ? nil : .spring(duration: 0.4)) {
                appeared = true
            }
        }
    }
}

/// Hosts an AppKit view so `NSSharingServicePicker` has something to point at.
///
/// The binding is written once, on creation. Writing it from `updateNSView`
/// invalidates the view that owns the state, which runs `updateNSView` again —
/// a loop that re-laid the Collection tab out on every turn of the main queue
/// for as long as it was open.
private struct ShareAnchor: NSViewRepresentable {
    @Binding var view: NSView

    func makeNSView(context: Context) -> NSView {
        let host = NSView(frame: .zero)
        DispatchQueue.main.async { view = host }
        return host
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
