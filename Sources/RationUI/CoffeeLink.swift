import SwiftUI

/// A quiet way to say thanks.
///
/// Deliberately a small icon in the footer rather than a button or a banner:
/// the app's job is to show you a number, and an app that nags for money while
/// doing it is a worse app. It reveals its label on hover.
struct CoffeeLink: View {

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Link(destination: URL(string: Links.coffee)!) {
            HStack(spacing: 3) {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 9))
                if isHovering {
                    Text("Buy me a coffee")
                        .font(.caption)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .foregroundStyle(isHovering ? Theme.accent : .secondary)
        }
        .buttonStyle(.plain)
        .help("Support Ration — entirely optional")
        .accessibilityLabel("Buy me a coffee")
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                isHovering = hovering
            }
        }
        .padding(.trailing, 8)
    }
}
