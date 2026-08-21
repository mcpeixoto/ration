import RationKit
import SwiftUI

/// Every creature raised, newest first.
///
/// The binder is one cell per species; this is one row per animal, because two runs
/// down the same line are two different creatures and only this view can say so.
struct CatchLogView: View {

    let state: CompanionState
    let inspect: (Creature) -> Void

    var body: some View {
        if state.log.isEmpty {
            Text("Nothing filed yet. Burn tokens, rip the pack, and raise what comes out.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(state.log.reversed()) { entry in
                    row(entry)
                }
            }
        }
    }

    private func row(_ entry: CatchEntry) -> some View {
        Button {
            if let creature = Dex.creature(entry.finalID) { inspect(creature) }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(Dex.creature(entry.finalID)?.name ?? entry.finalID)
                        .font(.caption.weight(.semibold))
                    if entry.isShiny {
                        Image(systemName: "sparkle")
                            .font(.system(size: 8))
                            .foregroundStyle(Theme.accent)
                    }
                    Spacer(minLength: 0)
                    Text(entry.rarity.label.uppercased())
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(entry.rarity.color)
                }
                HStack(spacing: 5) {
                    Text(chain(entry))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(entry.filedAt, format: .dateTime.day().month(.abbreviated))
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color.primary.opacity(0.05),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func chain(_ entry: CatchEntry) -> String {
        let names = entry.chain.compactMap { Dex.creature($0)?.name }
        return (names.joined(separator: " › ")) + " · " + entry.trait.label
    }
}
