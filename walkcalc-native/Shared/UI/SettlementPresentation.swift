import SwiftUI

enum SettlementCopy {
    static func title(_ debt: ResolvedDebt, participantID: String?) -> String {
        if debt.from.uuid == participantID {
            return String(format: L("You need to pay %@"), debt.to.name)
        }
        if debt.to.uuid == participantID {
            return String(format: L("%@ needs to pay you"), debt.from.name)
        }
        return String(format: L("%@ needs to pay %@"), debt.from.name, debt.to.name)
    }

    static func confirmation(_ debt: ResolvedDebt, participantID: String?) -> String {
        let amount = CurrencyCatalog.formatted(debt.amountMinor, currencyCode: debt.currencyCode, style: .exact)
        if debt.from.uuid == participantID {
            return String(format: L("You need to pay %@ %@"), debt.to.name, amount)
        }
        if debt.to.uuid == participantID {
            return String(format: L("%@ needs to pay you %@"), debt.from.name, amount)
        }
        return String(format: L("%@ needs to pay %@ %@"), debt.from.name, debt.to.name, amount)
    }
}

struct SettlementRelationshipTitle: View {
    let debt: ResolvedDebt
    let currentParticipantID: String?

    private var isPayer: Bool { debt.from.uuid == currentParticipantID }
    private var payer: String { isPayer ? L("You") : debt.from.name }
    private var recipient: String {
        debt.to.uuid == currentParticipantID ? L("Settlement.you") : debt.to.name
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            Text(SettlementCopy.title(debt, participantID: currentParticipantID))
                .fixedSize(horizontal: true, vertical: false)

            VStack(alignment: .leading, spacing: 2) {
                Text(payer)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 4) {
                    Text(L(isPayer ? "Settlement.pay" : "Settlement.pays"))
                        .fixedSize()
                    Text(recipient)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(SoftLedgerTheme.ink)
        .accessibilityLabel(SettlementCopy.title(debt, participantID: currentParticipantID))
    }
}

/// The surrounding row owns the action, including the arrow's hit area.
struct SettlementAvatarPair: View {
    @Environment(\.softLedgerAppTheme) private var appTheme
    @ScaledMetric(relativeTo: .subheadline) private var avatarSize = 32
    @ScaledMetric(relativeTo: .caption) private var arrowSize = 18
    @ScaledMetric(relativeTo: .caption2) private var arrowFontSize = 9
    @ScaledMetric(relativeTo: .caption) private var arrowBottomInset = 3

    let from: Member
    let to: Member

    var body: some View {
        ZStack(alignment: .bottom) {
            HStack(spacing: -avatarSize * 0.22) {
                SoftLedgerAvatar(member: from, size: avatarSize)
                    .overlay { Circle().stroke(SoftLedgerTheme.paper, lineWidth: 2) }
                    .zIndex(1)
                SoftLedgerAvatar(member: to, size: avatarSize)
            }

            Image(systemName: "arrow.right")
                .font(.system(size: arrowFontSize, weight: .bold))
                .foregroundStyle(SoftLedgerTheme.paper)
                .frame(width: arrowSize, height: arrowSize)
                .background(appTheme.accent, in: Circle())
                .overlay { Circle().stroke(SoftLedgerTheme.paper, lineWidth: 2) }
                .padding(.bottom, arrowBottomInset)
        }
        .fixedSize()
        .accessibilityHidden(true)
    }
}
