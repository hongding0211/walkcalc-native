import Foundation

// Compress the entire deck by its total card count, regardless of slot.
struct WalletStackSpacing {
    let offsets: [Double]
    let exposure: Double

    init(count: Int, exposure: Double, compression: Double) {
        self.exposure = max(0, exposure)
        var positions: [Double] = []
        var position = 0.0
        let gap = self.exposure * Self.spacingFactor(count: count, compression: compression)
        for _ in 0..<max(0, count) {
            positions.append(position)
            position += gap
        }
        offsets = positions
    }

    // Slow reciprocal spacing decay; zero keeps the original gap.
    static func spacingFactor(count: Int, compression: Double) -> Double {
        let additionalCards = max(0, count - 1)
        return 1 / (1 + max(0, compression) * Double(additionalCards))
    }

    // Tilt drops quickly as the entire deck gains cards, independent of spacing.
    static func tiltFactor(count: Int, decay: Double) -> Double {
        exp(-max(0, decay) * Double(max(0, count - 1)))
    }

    var stackHeight: Double { offsets.last ?? 0 }

    func offset(at index: Int) -> Double {
        guard !offsets.isEmpty else { return 0 }
        return offsets[min(max(0, index), offsets.count - 1)]
    }

}
