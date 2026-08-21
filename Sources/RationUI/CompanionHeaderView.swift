import RationKit
import SwiftUI

/// What is being raised right now, or the pack that has not opened yet.
struct CompanionHeaderView: View {

    let state: CompanionState
    /// Bumped by a rip or an evolution, so the flash plays once per moment.
    let celebration: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flash: Double = 0
    @State private var pop: CGFloat = 1
    @State private var seen = -1
    @State private var wiggle = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                portrait
                if let run = state.active {
                    details(run)
                } else {
                    packDetails
                }
            }
            if let run = state.active {
                EvolutionStripView(run: run)
            }
        }
        .onAppear(perform: playIfNeeded)
        .onChange(of: celebration) { playIfNeeded() }
        .onChange(of: packImminent) { syncWiggle() }
    }

    // MARK: Portrait

    @ViewBuilder
    private var portrait: some View {
        Group {
            if let run = state.active, let creature = Dex.creature(run.currentID) {
                CreaturePortrait(creature: creature, shiny: run.isShiny)
            } else {
                SealedPack()
            }
        }
        .frame(width: 76, height: 76)
        .background(Color.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(key.opacity(0.5), lineWidth: 1.5)
        }
        // A rip or an evolution swaps the illustration underneath a white flash, so
        // the change lands as a moment rather than a glitch.
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white)
                .opacity(flash)
        }
        .scaleEffect(pop)
        .rotationEffect(.degrees(packImminent ? (wiggle ? 5 : -5) : 0))
        .animation(
            packImminent && !reduceMotion
                ? .easeInOut(duration: 0.16).repeatForever(autoreverses: true) : .default,
            value: wiggle)
    }

    private var key: Color {
        guard let run = state.active, let creature = Dex.creature(run.currentID) else {
            return Theme.accent
        }
        return creature.lore.energy.keyColor(shiny: run.isShiny)
    }

    /// A pack past ninety percent shakes. It is the only cue that does not need a
    /// number to be read.
    private var packImminent: Bool { state.active == nil && state.packProgress >= 0.9 }

    // MARK: Details

    @ViewBuilder
    private func details(_ run: ActiveRun) -> some View {
        let creature = Dex.creature(run.currentID)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(creature?.name ?? run.currentID)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                if run.isShiny {
                    Image(systemName: "sparkle")
                        .font(.system(size: 9))
                        .foregroundStyle(key)
                }
                Spacer(minLength: 0)
                if let rarity = creature?.rarity {
                    Text(rarity.label.uppercased())
                        .font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(rarity.color, in: Capsule())
                        .foregroundStyle(.white)
                }
            }
            Text("\(Dex.lore[run.currentID]?.stage.label ?? "Basic") · \(run.trait.label)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            ProgressView(value: run.progress)
                .controlSize(.small)
                .tint(Theme.accent)
            // Never name the next form — the destination is the surprise.
            Text(
                "\(PowerFormat.compact(run.remaining)) \(run.isFinalForm ? "to file" : "to evolve")"
            )
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
    }

    private var packDetails: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("Sealed pack").font(.callout.weight(.semibold))
                Spacer(minLength: 0)
                if let promise = state.packGuarantee {
                    Text(promise.label.uppercased())
                        .font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(promise.color, in: Capsule())
                        .foregroundStyle(.white)
                }
            }
            Text(
                state.packGuarantee.map { "\(CompanionPack.label($0)) · \($0.label) or better" }
                    ?? "Burn tokens and it opens."
            )
            .font(.caption2)
            .foregroundStyle(packImminent ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
            ProgressView(value: state.packProgress)
                .controlSize(.small)
                .tint(Theme.accent)
            Text("\(PowerFormat.compact(state.packRemaining)) to rip")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: Motion

    private func playIfNeeded() {
        syncWiggle()
        guard celebration != seen else { return }
        seen = celebration
        guard !reduceMotion else { return }
        flash = 0.85
        pop = 0.6
        withAnimation(.easeOut(duration: 0.8)) { flash = 0 }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) { pop = 1 }
    }

    private func syncWiggle() {
        wiggle = packImminent && !reduceMotion
    }
}

/// A wrapped pack: a foil rectangle with a band across it.
private struct SealedPack: View {
    var body: some View {
        GeometryReader { geo in
            let inset = geo.size.width * 0.16
            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Theme.accent.opacity(0.55))
                Rectangle()
                    .fill(Theme.accent)
                    .frame(height: 6)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Theme.accent, lineWidth: 1)
            }
            .padding(.horizontal, inset)
            .padding(.vertical, geo.size.height * 0.12)
        }
        .accessibilityHidden(true)
    }
}
