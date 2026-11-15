import SwiftUI

private struct WalletViewportHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

private struct WalletExpandedLayoutKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var walletUsesExpandedLayout: Bool {
        get { self[WalletExpandedLayoutKey.self] }
        set { self[WalletExpandedLayoutKey.self] = newValue }
    }
    var walletViewportHeight: CGFloat {
        get { self[WalletViewportHeightKey.self] }
        set { self[WalletViewportHeightKey.self] = newValue }
    }
}

// Measure the app window outside navigation/scroll containers so collapsing a
// large title or showing search does not resize the wallet as the user scrolls.
struct WalletViewport: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    func body(content: Content) -> some View {
        GeometryReader { proxy in
            let windowHeight = proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
            content
                .environment(\.walletViewportHeight, windowHeight)
                // Capture the system size class before navigation overrides it
                // to keep portrait layouts in a single column.
                .environment(\.walletUsesExpandedLayout, horizontalSizeClass == .regular)
        }
    }
}
