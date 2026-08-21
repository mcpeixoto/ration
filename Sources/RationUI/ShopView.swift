import RationKit
import SwiftUI

/// Tokens already burned on real work, spent on packs and items.
///
/// Confirmation is inline on the button rather than a sheet or an alert. A menu bar
/// panel is transient: it closes on the next click outside, and a sheet it was
/// presenting is orphaned when it does, swallowing every click after that.
struct ShopView: View {

    let state: CompanionState
    let buy: (ShopEntry) -> Void
    let use: (ItemKind) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            wallet
            ForEach(CompanionEngine.shopEntries(state), id: \.self) { entry in
                ShopRow(entry: entry, state: state, buy: buy)
            }
            let usable = state.heldItems.filter { !$0.kind.isPassive }.map(\.kind)
            if !usable.isEmpty, state.active != nil {
                Text("Bag")
                    .font(.caption.weight(.semibold))
                    .padding(.top, 2)
                ForEach(usable, id: \.self) { kind in
                    bagRow(kind, state.itemCount(kind))
                }
            }
        }
    }

    private var wallet: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Spendable")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(PowerFormat.compact(state.wallet))
                .font(.system(size: 24, weight: .bold).monospacedDigit())
            Text("Tokens you have already burned. Spending them does not undo any growth.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func bagRow(_ kind: ItemKind, _ count: Int) -> some View {
        HStack(spacing: 8) {
            Text("\(kind.label) ×\(count)")
                .font(.caption.weight(.medium))
            Spacer(minLength: 0)
            Button("Use") { use(kind) }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!CompanionEngine.canUse(kind, state))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ShopRow: View {

    let entry: ShopEntry
    let state: CompanionState
    let buy: (ShopEntry) -> Void

    @State private var confirming = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            controls
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private var controls: some View {
        if isHeld {
            HStack(spacing: 5) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.caption2)
                    .foregroundStyle(Theme.accent)
                Text("Held")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                Spacer(minLength: 0)
            }
        } else if confirming {
            HStack(spacing: 8) {
                Text("Buy \(name)?")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button("Buy") {
                    confirming = false
                    buy(entry)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                Button("Cancel") { confirming = false }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
            }
        } else {
            HStack {
                Text(PowerFormat.compact(entry.price))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
                if CompanionEngine.canBuy(entry, state) {
                    Button("Buy") { confirming = true }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                } else {
                    Text("\(PowerFormat.compact(entry.price - state.wallet)) short")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var isHeld: Bool {
        if case .item(let kind) = entry, kind.isPassive, state.itemCount(kind) > 0 { return true }
        return false
    }

    private var name: String {
        switch entry {
        case .item(let kind): kind.label
        case .pack(let floor): CompanionPack.label(floor)
        }
    }

    private var detail: String {
        switch entry {
        case .item(let kind): kind.detail
        case .pack(nil): "Discards what you are raising and seals a new pack."
        case .pack(.some(let floor)): "A new pack, guaranteed to reach \(floor.label) or better."
        }
    }
}
