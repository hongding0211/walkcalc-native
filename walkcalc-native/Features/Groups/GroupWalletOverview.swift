import SwiftUI

struct GroupWalletOverview: View {
    @EnvironmentObject private var store: WalkcalcStore
    let group: WalkGroup
    #if DEBUG
    @WalletAppearanceSettings private var appearance: WalletAppearance
    #else
    @Environment(\.colorScheme) private var colorScheme
    private var appearance: WalletAppearance { WalletAppearance(isDark: colorScheme == .dark) }
    #endif

    var body: some View {
        let participantID = store.currentParticipantID(for: group)
        let cards = GroupWalletData.cards(group: group, participantID: participantID,
            debts: store.resolvedDebts(for: group),
            suggestionReady: store.isSettlementSuggestionReady(for: group.id),
            paletteCount: appearance.paletteCount,
            currencyCodes: store.recordFilters(for: group.id).currencyCodes)
        if cards.isEmpty {
            SoftLedgerCard {
                Text(L("Wallet.spendingUnavailable"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        } else {
            CurrencyWallet(groupID: group.id, participantID: participantID, samples: cards, appearance: appearance)
        }
    }
}

#if DEBUG
// One mode-aware source for the live page, tuning sheet, and Canvas.
@propertyWrapper
struct WalletAppearanceSettings: DynamicProperty {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(WalletAppearance.lightStorageKey) private var lightData = Data()
    @AppStorage(WalletAppearance.darkStorageKey) private var darkData = Data()
    @WalletPaletteSettings private var palette: WalletPalette

    var wrappedValue: WalletAppearance {
        get {
            var value = WalletAppearance.decode(colorScheme == .dark ? darkData : lightData,
                                                isDark: colorScheme == .dark)
            value.palette = palette.entries.map(\.colors)
            return value
        }
        nonmutating set {
            if newValue.palette != palette.entries.map(\.colors) {
                var updated = palette
                updated.replaceColors(newValue.palette)
                palette = updated
            }
            if colorScheme == .dark { darkData = newValue.encoded }
            else { lightData = newValue.encoded }
        }
    }

    var projectedValue: Binding<WalletAppearance> {
        Binding(get: { wrappedValue }, set: { wrappedValue = $0 })
    }
}

struct GroupWalletTuningView: View {
    @EnvironmentObject private var store: WalkcalcStore
    @WalletAppearanceSettings private var appearance: WalletAppearance
    let groupId: String

    var body: some View {
        ScrollView {
            if let group = store.group(id: groupId) {
                GroupWalletOverview(group: group)
                    .padding(20)
            }
        }
        .background { SoftLedgerBackground() }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            WalletTuningPanel(appearance: $appearance)
        }
        .modifier(WalletPreviewAppearance())
        .navigationTitle("卡包调节")
        .navigationBarTitleDisplayMode(.inline)
    }
}
#endif
