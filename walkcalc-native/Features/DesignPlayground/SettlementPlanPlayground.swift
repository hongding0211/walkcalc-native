#if DEBUG
import SwiftUI
import UIKit

struct SettlementPlanPlayground: View {
    @State private var selectedVariant = SettlementVariant.grouped

    private let transfers = SettlementTransferMock.samples

    var body: some View {
        NavigationStack {
            ZStack {
                SettlementPlaygroundTheme.canvas.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        Picker("Variant", selection: $selectedVariant) {
                            ForEach(SettlementVariant.allCases) { variant in
                                Text(variant.title).tag(variant)
                            }
                        }
                        .pickerStyle(.segmented)

                        selectedVariantView
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 34)
                }
            }
            .navigationTitle("Settlement")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }

    @ViewBuilder
    private var selectedVariantView: some View {
        switch selectedVariant {
        case .grouped:
            SettlementGroupedRecipientsCard(transfers: transfers)
        case .tasks:
            SettlementTaskCards(transfers: transfers)
        case .flow:
            SettlementFlowCard(transfers: transfers)
        case .compact:
            SettlementCompactCard(transfers: transfers)
        }
    }
}

private enum SettlementVariant: String, CaseIterable, Identifiable {
    case grouped
    case tasks
    case flow
    case compact

    var id: String { rawValue }

    var title: String {
        switch self {
        case .grouped:
            "Grouped"
        case .tasks:
            "Tasks"
        case .flow:
            "Flow"
        case .compact:
            "Compact"
        }
    }
}

private struct SettlementGroupedRecipientsCard: View {
    let transfers: [SettlementTransferMock]

    private var groupedTransfers: [(recipient: SettlementPersonMock, transfers: [SettlementTransferMock], total: String)] {
        Dictionary(grouping: transfers, by: \.receiver)
            .map { receiver, transfers in
                (
                    recipient: receiver,
                    transfers: transfers,
                    total: SettlementTransferMock.displayTotal(for: transfers)
                )
            }
            .sorted { $0.recipient.name < $1.recipient.name }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettlementSectionHeader(
                title: "Suggested settlement",
                subtitle: "\(transfers.count) transfers"
            )

            VStack(spacing: 0) {
                ForEach(groupedTransfers, id: \.recipient.id) { group in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            SettlementAvatar(person: group.recipient, size: 42)

                            VStack(alignment: .leading, spacing: 3) {
                                Text("Pay \(group.recipient.name)")
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(SettlementPlaygroundTheme.ink)

                                Text(group.transfers.map(\.payer.name).joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(SettlementPlaygroundTheme.secondaryInk)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 12)

                            Text(group.total)
                                .font(.title3.monospacedDigit().weight(.semibold))
                                .foregroundStyle(SettlementPlaygroundTheme.ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                        }

                        VStack(spacing: 8) {
                            ForEach(group.transfers) { transfer in
                                HStack(spacing: 10) {
                                    SettlementAvatar(person: transfer.payer, size: 28)

                                    Text(transfer.payer.name)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(SettlementPlaygroundTheme.ink)
                                        .lineLimit(1)

                                    Spacer(minLength: 10)

                                    Text(transfer.amount)
                                        .font(.subheadline.monospacedDigit().weight(.semibold))
                                        .foregroundStyle(SettlementPlaygroundTheme.secondaryInk)
                                }
                            }
                        }
                        .padding(12)
                        .background(SettlementPlaygroundTheme.canvas.opacity(0.62), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .padding(16)

                    if group.recipient.id != groupedTransfers.last?.recipient.id {
                        Divider()
                            .overlay(SettlementPlaygroundTheme.rule.opacity(0.56))
                    }
                }
            }
            .settlementSurface(cornerRadius: 20)
        }
    }
}

private struct SettlementTaskCards: View {
    @ScaledMetric(relativeTo: .subheadline) private var avatarSize = 30
    @ScaledMetric(relativeTo: .caption) private var receiverAvatarSize = 20
    @ScaledMetric(relativeTo: .caption) private var arrowBadgeSize = 18
    @ScaledMetric(relativeTo: .caption2) private var arrowBadgeFontSize = 9
    @ScaledMetric(relativeTo: .subheadline) private var rowSpacing = 12
    @ScaledMetric(relativeTo: .caption) private var textSpacing = 4
    @ScaledMetric(relativeTo: .caption) private var receiverSpacing = 6
    @ScaledMetric(relativeTo: .subheadline) private var cardHorizontalPadding = 14
    @ScaledMetric(relativeTo: .caption) private var cardVerticalPadding = 12

    let transfers: [SettlementTransferMock]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettlementSectionHeader(title: "Suggested settlement", subtitle: "Ready to record")

            LazyVStack(spacing: 12) {
                ForEach(transfers) { transfer in
                    HStack(spacing: rowSpacing) {
                        ZStack(alignment: .bottomTrailing) {
                            SettlementAvatar(person: transfer.payer, size: avatarSize)

                            Image(systemName: "arrow.right")
                                .font(.system(size: arrowBadgeFontSize, weight: .bold))
                                .foregroundStyle(SettlementPlaygroundTheme.paper)
                                .frame(width: arrowBadgeSize, height: arrowBadgeSize)
                                .background(SettlementPlaygroundTheme.accent, in: Circle())
                                .overlay {
                                    Circle()
                                        .stroke(SettlementPlaygroundTheme.paper, lineWidth: max(1, arrowBadgeSize / 9))
                                }
                                .offset(x: 2, y: 2)
                        }
                        .frame(width: avatarSize + 3, height: avatarSize + 3)

                        VStack(alignment: .leading, spacing: textSpacing) {
                            Text("\(transfer.payer.name) pays \(transfer.receiver.name)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(SettlementPlaygroundTheme.ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.86)

                            HStack(spacing: receiverSpacing) {
                                SettlementAvatar(person: transfer.receiver, size: receiverAvatarSize)

                                Text("Settle with \(transfer.receiver.name)")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(SettlementPlaygroundTheme.secondaryInk)
                                    .lineLimit(1)
                            }
                        }

                        Spacer(minLength: 12)

                        Text(transfer.amount)
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .foregroundStyle(SettlementPlaygroundTheme.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }
                    .padding(.horizontal, cardHorizontalPadding)
                    .padding(.vertical, cardVerticalPadding)
                    .settlementSurface(cornerRadius: 16)
                }
            }
        }
    }
}

private struct SettlementFlowCard: View {
    let transfers: [SettlementTransferMock]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettlementSectionHeader(title: "Suggested settlement", subtitle: "Money movement")

            VStack(alignment: .leading, spacing: 16) {
                ForEach(transfers) { transfer in
                    HStack(spacing: 12) {
                        SettlementEndpoint(person: transfer.payer, alignment: .leading)

                        VStack(spacing: 5) {
                            Image(systemName: "arrow.right")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(SettlementPlaygroundTheme.accent)

                            Text(transfer.amount)
                                .font(.subheadline.monospacedDigit().weight(.bold))
                                .foregroundStyle(SettlementPlaygroundTheme.ink)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(SettlementPlaygroundTheme.accent.opacity(0.14), in: Capsule())
                        }
                        .frame(width: 88)
                        .layoutPriority(2)

                        SettlementEndpoint(person: transfer.receiver, alignment: .trailing)
                    }
                    .frame(minHeight: 58)

                    if transfer.id != transfers.last?.id {
                        Divider()
                            .overlay(SettlementPlaygroundTheme.rule.opacity(0.48))
                    }
                }
            }
            .padding(16)
            .settlementSurface(cornerRadius: 20)
        }
    }
}

private struct SettlementCompactCard: View {
    let transfers: [SettlementTransferMock]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettlementSectionHeader(title: "Suggested settlement", subtitle: "Compact list")

            VStack(spacing: 0) {
                ForEach(transfers) { transfer in
                    HStack(spacing: 12) {
                        HStack(spacing: -8) {
                            SettlementAvatar(person: transfer.payer, size: 34)
                            SettlementAvatar(person: transfer.receiver, size: 34)
                        }
                        .frame(width: 60, alignment: .leading)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(transfer.payer.name) to \(transfer.receiver.name)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(SettlementPlaygroundTheme.ink)
                                .lineLimit(1)

                            Text("Recommended transfer")
                                .font(.caption)
                                .foregroundStyle(SettlementPlaygroundTheme.mutedInk)
                        }

                        Spacer(minLength: 10)

                        Text(transfer.amount)
                            .font(.headline.monospacedDigit().weight(.semibold))
                            .foregroundStyle(SettlementPlaygroundTheme.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(transfer.payer.name) pays \(transfer.receiver.name), \(transfer.amount)")

                    if transfer.id != transfers.last?.id {
                        Divider()
                            .overlay(SettlementPlaygroundTheme.rule.opacity(0.52))
                            .padding(.leading, 86)
                    }
                }
            }
            .settlementSurface(cornerRadius: 18)
        }
    }
}

private struct SettlementSectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(SettlementPlaygroundTheme.ink)

            Spacer(minLength: 12)

            Text(subtitle)
                .font(.caption.weight(.medium))
                .foregroundStyle(SettlementPlaygroundTheme.mutedInk)
        }
    }
}

private struct SettlementEndpoint: View {
    enum EndpointAlignment {
        case leading
        case trailing
    }

    let person: SettlementPersonMock
    let alignment: EndpointAlignment

    private var horizontalAlignment: HorizontalAlignment {
        switch alignment {
        case .leading:
            .leading
        case .trailing:
            .trailing
        }
    }

    var body: some View {
        VStack(alignment: horizontalAlignment, spacing: 7) {
            SettlementAvatar(person: person, size: 44)

            Text(person.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(SettlementPlaygroundTheme.ink)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
    }
}

private struct SettlementAvatar: View {
    let person: SettlementPersonMock
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(person.tint.opacity(0.20))
            .overlay {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                person.tint.opacity(0.92),
                                person.tint.mix(with: .black, by: 0.18).opacity(0.94)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .padding(size * 0.08)
            }
            .overlay {
                Text(person.initial)
                    .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
            .overlay {
                Circle()
                    .stroke(SettlementPlaygroundTheme.paper, lineWidth: max(1, size * 0.055))
            }
            .accessibilityHidden(true)
    }
}

private struct SettlementPersonMock: Hashable, Identifiable {
    let id: String
    let name: String
    let initial: String
    let tint: Color

    static let mehaa = SettlementPersonMock(id: "mehaa", name: "mehaa", initial: "M", tint: Color(red: 0.35, green: 0.49, blue: 0.33))
    static let hong = SettlementPersonMock(id: "hong", name: "Hong", initial: "H", tint: Color(red: 0.24, green: 0.48, blue: 0.69))
    static let temp = SettlementPersonMock(id: "temp-c", name: "Temp C.", initial: "T", tint: Color(red: 0.43, green: 0.39, blue: 0.55))
    static let yan = SettlementPersonMock(id: "yan", name: "Yan", initial: "Y", tint: Color(red: 0.68, green: 0.33, blue: 0.29))
}

private struct SettlementTransferMock: Identifiable {
    let id: String
    let payer: SettlementPersonMock
    let receiver: SettlementPersonMock
    let amount: String
    let amountMinor: Int

    static let samples: [SettlementTransferMock] = [
        .init(id: "mehaa-hong", payer: .mehaa, receiver: .hong, amount: "¥2.80", amountMinor: 280),
        .init(id: "mehaa-temp", payer: .mehaa, receiver: .temp, amount: "¥4.44", amountMinor: 444),
        .init(id: "yan-hong", payer: .yan, receiver: .hong, amount: "¥18.00", amountMinor: 1800)
    ]

    static func displayTotal(for transfers: [SettlementTransferMock]) -> String {
        let totalMinor = transfers.reduce(0) { $0 + $1.amountMinor }
        let yuan = Double(totalMinor) / 100
        return "¥\(String(format: "%.2f", yuan))"
    }
}

private enum SettlementPlaygroundTheme {
    static let canvas = settlementAdaptive(light: 0xF6F2EA, dark: 0x131416)
    static let paper = settlementAdaptive(light: 0xFEFCF6, dark: 0x1D1E20)
    static let ink = settlementAdaptive(light: 0x25221D, dark: 0xF1F0EC)
    static let secondaryInk = settlementAdaptive(light: 0x746C5D, dark: 0xC7C4BE)
    static let mutedInk = settlementAdaptive(light: 0x9D917E, dark: 0x92918C)
    static let rule = settlementAdaptive(light: 0xDAD2C0, dark: 0x34363A)
    static let accent = settlementAdaptive(light: 0xB15525, dark: 0xE49B63)
}

private func settlementAdaptive(light: UInt32, dark: UInt32) -> Color {
    Color(UIColor { traitCollection in
        UIColor(hex: traitCollection.userInterfaceStyle == .dark ? dark : light)
    })
}

private struct SettlementSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .background(.clear)
                .glassEffect(.regular.tint(SettlementPlaygroundTheme.paper.opacity(0.26)), in: .rect(cornerRadius: cornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(SettlementPlaygroundTheme.rule.opacity(0.62), lineWidth: 1)
                }
        } else {
            content
                .background(SettlementPlaygroundTheme.paper, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(SettlementPlaygroundTheme.rule.opacity(0.62), lineWidth: 1)
                }
        }
    }
}

private extension View {
    func settlementSurface(cornerRadius: CGFloat) -> some View {
        modifier(SettlementSurfaceModifier(cornerRadius: cornerRadius))
    }
}

#Preview("Settlement Playground") {
    SettlementPlanPlayground()
}

#Preview("Settlement Playground Dark") {
    SettlementPlanPlayground()
        .preferredColorScheme(.dark)
}
#endif
