import RationKit
import SwiftUI

/// Picks which tool the panel is showing.
///
/// Sits above the tab bar because it scopes everything below it: the gauge, the
/// calendar, the trends and the breakdown all change together. Hidden entirely
/// when only one provider is installed — most people run one tool, and a
/// switcher with one position is furniture.
struct ProviderSwitcher: View {

    let providers: [Provider]
    @Binding var selection: Provider

    @Namespace private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            ForEach(providers) { provider in
                let isSelected = provider == selection

                Button {
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
                        selection = provider
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: provider.symbolName)
                            .font(.system(size: 9, weight: .medium))
                        Text(provider.displayName)
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(isSelected ? Color.primary : .secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(.quaternary)
                                .matchedGeometryEffect(id: "provider", in: namespace)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(provider.displayName)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
    }
}

// MARK: - Not-metered state

/// Shown in place of the gauge for a provider Ration can see but not meter.
///
/// It says which tool, why there is no number, and stops. Anything more
/// apologetic would imply Ration is going to fix it, and it is not: reading
/// these would mean a network host and, in one case, a credential of Ration's
/// own.
struct ProviderUnavailableView: View {

    let provider: Provider
    let reason: String

    var body: some View {
        StatusMessageView(
            symbol: "lock.circle",
            title: "No gauge for \(provider.displayName)",
            message: reason
        )
    }
}
