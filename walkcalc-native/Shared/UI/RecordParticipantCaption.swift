import SwiftUI
import UIKit

/// Fit the explanation by abbreviating names, never by dropping the participant count.
struct RecordParticipantCaption: View {
    @ScaledMetric(relativeTo: .caption) private var fontSize = 12
    @State private var availableWidth: CGFloat = 0

    let summary: (Int?) -> String

    private var displayText: String {
        guard availableWidth > 0 else { return summary(nil) }
        let font = UIFont.systemFont(ofSize: fontSize, weight: .medium)
        let nameLimits: [Int?] = [nil, 24, 18, 12, 8, 5, 3]
        for limit in nameLimits {
            let text = summary(limit)
            let bounds = (text as NSString).boundingRect(
                with: CGSize(width: max(1, availableWidth - 2), height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font], context: nil
            )
            if ceil(bounds.height) <= ceil(font.lineHeight * 2) {
                return text
            }
        }
        return summary(3)
    }

    var body: some View {
        Text(displayText)
            .font(.system(size: fontSize, weight: .medium))
            .foregroundStyle(SoftLedgerTheme.secondaryInk)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
    }
}
