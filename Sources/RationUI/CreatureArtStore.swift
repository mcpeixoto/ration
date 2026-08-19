import AppKit
import Foundation
import Observation

/// Portraits drawn by Apple Intelligence, kept next to the rest of Ration's
/// local state. Nothing is uploaded by Ration — Image Playground is the
/// system sheet, and the PNG lands in Application Support.
@MainActor
@Observable
final class CreatureArtStore {

    static let shared = CreatureArtStore()

    /// Bumped when a portrait is saved so cards redraw.
    private(set) var generation = 0

    private var memory: [String: NSImage] = [:]
    private let folder: URL

    private init() {
        let support =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!.appending(path: "Ration/creatures")
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        folder = support
    }

    func image(for id: String) -> NSImage? {
        if let cached = memory[id] { return cached }
        let url = folder.appending(path: "\(id).png")
        guard let image = NSImage(contentsOf: url) else { return nil }
        memory[id] = image
        return image
    }

    func adopt(_ generated: URL, for id: String) {
        let dest = folder.appending(path: "\(id).png")
        try? FileManager.default.removeItem(at: dest)
        guard let image = NSImage(contentsOf: generated) else { return }
        if let tiff = image.tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiff),
            let png = rep.representation(using: .png, properties: [:])
        {
            try? png.write(to: dest)
        } else {
            try? FileManager.default.copyItem(at: generated, to: dest)
        }
        memory[id] = NSImage(contentsOf: dest) ?? image
        generation += 1
    }
}
