import RationKit
import SwiftUI

/// The forms this run has reached, then a question mark for every one still to come.
///
/// The number of forms is not a secret — which creatures they are is, so unreached
/// stages are drawn as marks rather than named. Scrolls because a line here branches
/// up to five ways and the panel is 340 points wide.
struct EvolutionStripView: View {

    let run: ActiveRun

    private var ahead: Int { max(0, run.forms - run.revealed.count) }

    var body: some View {
        if run.forms > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(run.revealed.enumerated()), id: \.offset) { index, species in
                        chip(
                            Dex.creature(species)?.name ?? species,
                            isCurrent: index == run.stageIndex)
                    }
                    ForEach(0..<ahead, id: \.self) { _ in
                        chip("?", isCurrent: false)
                    }
                }
                .padding(.horizontal, 1)
            }
            .frame(height: 28)
        }
    }

    private func chip(_ text: String, isCurrent: Bool) -> some View {
        Text(text)
            .font(.system(size: 9, weight: isCurrent ? .bold : .regular))
            .foregroundStyle(isCurrent ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(minWidth: 46)
            .background(
                isCurrent ? Theme.accent.opacity(0.18) : Color.primary.opacity(0.06),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}
