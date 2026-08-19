import RationKit
import SwiftUI

#if canImport(ImagePlayground)
import ImagePlayground
#endif

/// Opens the system Image Playground sheet so the trainer can redraw a
/// creature with Apple Intelligence. Ration only stores the PNG it returns.
struct IntelligenceArtButton: View {
    let creature: Creature

    var body: some View {
        #if canImport(ImagePlayground)
        if #available(macOS 15.2, *) {
            PlaygroundButton(creature: creature)
        }
        #endif
    }
}

#if canImport(ImagePlayground)
@available(macOS 15.2, *)
private struct PlaygroundButton: View {
    let creature: Creature

    @State private var show = false
    @Environment(\.supportsImagePlayground) private var supportsImagePlayground

    var body: some View {
        if supportsImagePlayground {
            Button("Apple Intelligence…") { show = true }
                .help(
                    "Redraw this creature with Image Playground. The picture stays on this Mac."
                )
                .imagePlaygroundSheet(
                    isPresented: $show,
                    concepts: creature.artConcepts.map { .text($0) },
                    sourceImage: seedImage
                ) { url in
                    CreatureArtStore.shared.adopt(url, for: creature.id)
                }
        }
    }

    /// Seed the sheet with the current portrait so Apple Intelligence
    /// starts from our drawing instead of a blank prompt.
    private var seedImage: Image? {
        if let custom = CreatureArtStore.shared.image(for: creature.id) {
            return Image(nsImage: custom)
        }
        let view = CreaturePortrait(creature: creature, caught: true)
            .frame(width: 256, height: 256)
            .environment(\.rationAnimatesEntrance, false)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let ns = renderer.nsImage else { return nil }
        return Image(nsImage: ns)
    }
}
#endif
