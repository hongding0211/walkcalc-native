import SwiftUI

enum SoftLedgerCornerRadius {
    // Surface geometry stays consistent as Dynamic Type scales the contents.
    static let card: CGFloat = 24
    static let compact: CGFloat = 16
}

private struct SoftLedgerSurface: ViewModifier {
    let cornerRadius: CGFloat
    let borderOpacity: Double

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(SoftLedgerTheme.paper, in: shape)
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(SoftLedgerTheme.rule.opacity(borderOpacity), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .contentShape(shape)
    }
}

extension View {
    func softLedgerSurface(cornerRadius: CGFloat = SoftLedgerCornerRadius.card,
                           borderOpacity: Double = 0.62) -> some View {
        modifier(SoftLedgerSurface(cornerRadius: cornerRadius, borderOpacity: borderOpacity))
    }
}
