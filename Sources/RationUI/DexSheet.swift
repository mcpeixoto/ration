import RationKit
import SwiftUI

/// The whole set as a contact sheet, for documentation and for looking at
/// fifty card faces at once without clicking through the binder.
public struct DexSheet: View {
    var columns: Int
    var cardWidth: CGFloat
    var caught: Bool

    public init(columns: Int = 5, cardWidth: CGFloat = 240, caught: Bool = true) {
        self.columns = columns
        self.cardWidth = cardWidth
        self.caught = caught
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Ration Dex")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                Text("SET 01 · \(Dex.roster.count) CARDS")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: grid, spacing: 16) {
                ForEach(Dex.roster) { creature in
                    CreatureCard(creature: creature, caught: caught, style: .full)
                        .frame(width: cardWidth)
                }
            }
        }
        .padding(24)
    }

    private var grid: [GridItem] {
        Array(repeating: GridItem(.fixed(cardWidth), spacing: 16), count: columns)
    }
}
