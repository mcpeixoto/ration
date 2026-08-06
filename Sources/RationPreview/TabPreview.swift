import RationKit
import RationUI
import SwiftUI

/// Frames a single tab at panel width, so the screenshots match what the tab
/// looks like inside the real popover.
struct TabPreview<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Ration").font(.headline)
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)

            Divider()
            content
        }
        .frame(width: 340)
    }
}
