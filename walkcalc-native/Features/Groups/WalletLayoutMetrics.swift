import Foundation

enum WalletHeightLimit {
    // The old setting capped every device. Start the scoped policy at its new
    // default without carrying over a globally tuned, often much smaller cap.
    static let storageKey = "debug.currencyWallet.maximumHeightFraction.v2"
    static let defaultFraction = 0.30
    static let fractionRange = 0.20...0.50
    static func maximumHeight(viewportHeight: CGFloat, fraction: Double, regularWidth: Bool) -> CGFloat? {
        guard regularWidth, viewportHeight.isFinite, viewportHeight > 0 else { return nil }
        let fraction = fraction.isFinite ? min(fractionRange.upperBound, max(fractionRange.lowerBound, fraction)) : defaultFraction
        return viewportHeight * fraction
    }
}

// Cap the whole resting wallet, including the exposed currency headers.
// Resize the actual cards as well, so opening the mask cannot reveal long tails.
// Readable text and accessible currency headers take priority over the cap.
struct WalletLayoutMetrics {
    static let cardAspectRatio: CGFloat = 85.60 / 53.98
    static let topInset: CGFloat = 22
    static let bottomInset: CGFloat = 12

    let cardHeight: CGFloat
    let glassHeight: CGFloat
    let height: CGFloat

    init(width: CGFloat, cardInset: CGFloat, glassHeightRatio: Double,
         exposedHeight: CGFloat, stackHeight: CGFloat, contentHeight: CGFloat,
         maximumHeight: CGFloat?) {
        let naturalCardHeight = max(1, width - 2 * cardInset) / Self.cardAspectRatio
        let desiredGlassHeight = max(naturalCardHeight * glassHeightRatio, contentHeight)
        let headerHeight = Self.topInset + stackHeight
        let minimumHeight = headerHeight + exposedHeight + contentHeight + Self.bottomInset
        let naturalHeight = headerHeight + max(naturalCardHeight + 14,
            exposedHeight + desiredGlassHeight + Self.bottomInset)
        height = max(minimumHeight, min(naturalHeight, maximumHeight ?? naturalHeight))
        glassHeight = max(contentHeight, min(desiredGlassHeight,
            height - headerHeight - exposedHeight - Self.bottomInset))
        cardHeight = Self.fittedCardHeight(width: width, cardInset: cardInset,
            walletHeight: height, stackHeight: stackHeight)
    }

    static func fittedCardHeight(width: CGFloat, cardInset: CGFloat,
                                 walletHeight: CGFloat, stackHeight: CGFloat) -> CGFloat {
        min(max(1, width - 2 * cardInset) / cardAspectRatio,
            max(1, walletHeight - topInset - stackHeight - 14))
    }
}
