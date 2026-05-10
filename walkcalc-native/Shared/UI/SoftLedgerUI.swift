import SwiftUI
import UIKit

enum SoftLedgerTheme {
    static let canvas = adaptive(light: 0xF6F2EA, dark: 0x131416)
    static let paper = adaptive(light: 0xFEFCF6, dark: 0x1D1E20)
    static let formPaper = adaptive(light: 0xFFFDF8, dark: 0x222326)
    static let ink = adaptive(light: 0x25221D, dark: 0xF1F0EC)
    static let secondaryInk = adaptive(light: 0x746C5D, dark: 0xC7C4BE)
    static let mutedInk = adaptive(light: 0x9D917E, dark: 0x92918C)
    static let rule = adaptive(light: 0xDAD2C0, dark: 0x34363A)
    static let positive = adaptive(light: 0x167454, dark: 0x77C99E)
    static let negative = adaptive(light: 0xAC2F24, dark: 0xF07C6C)
    static let accent = adaptive(light: 0xB15525, dark: 0xE49B63)
    static let accentSoft = adaptive(light: 0xEDCBA4, dark: 0x38322F)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traitCollection in
            UIColor(hex: traitCollection.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

struct SoftLedgerBackground: View {
    var body: some View {
        SoftLedgerTheme.canvas.ignoresSafeArea()
    }
}

struct SoftLedgerCard<Content: View>: View {
    var cornerRadius: CGFloat = 16
    var usesGlass = false
    @ViewBuilder var content: Content

    var body: some View {
        if usesGlass {
            content
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .softLedgerGlass(cornerRadius: cornerRadius)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(SoftLedgerTheme.rule.opacity(0.70), lineWidth: 1)
                }
                .shadow(color: SoftLedgerTheme.ink.opacity(0.04), radius: 10, y: 5)
        } else {
            content
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(SoftLedgerTheme.paper, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(SoftLedgerTheme.rule.opacity(0.68), lineWidth: 1)
                }
                .shadow(color: SoftLedgerTheme.ink.opacity(0.04), radius: 10, y: 5)
        }
    }
}

private struct SoftLedgerGlassModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .glassEffect(.regular.tint(SoftLedgerTheme.paper.opacity(0.26)), in: .rect(cornerRadius: cornerRadius))
    }
}

struct SoftLedgerAvatar: View {
    var user: UserProfile?
    var member: Member?
    var initial: String?
    var size: CGFloat = 40
    var borderColor: Color = SoftLedgerTheme.paper

    private var displayName: String {
        user?.name ?? member?.name ?? initial ?? "?"
    }

    private var avatarURL: String {
        user?.avatar ?? member?.avatar ?? ""
    }

    var body: some View {
        Group {
            if let url = URL(string: avatarURL), !avatarURL.isEmpty {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    fallback
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var fallback: some View {
        Circle()
            .fill(SoftLedgerTheme.canvas)
            .overlay {
                Text(String(displayName.prefix(1)).uppercased())
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(SoftLedgerTheme.secondaryInk)
            }
    }
}

struct SoftLedgerAvatarStack: View {
    let members: [Member]
    var visibleCount = 4
    var size: CGFloat = 28
    var borderColor: Color = SoftLedgerTheme.paper
    var showsTotal = false

    private var visibleMembers: [Member] {
        Array(members.prefix(visibleCount))
    }

    private var hiddenCount: Int {
        max(members.count - visibleMembers.count, 0)
    }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: -8) {
                ForEach(visibleMembers) { member in
                    SoftLedgerAvatar(member: member, size: size)
                        .overlay {
                            Circle().stroke(borderColor, lineWidth: 2)
                        }
                        .accessibilityHidden(true)
                }

                if hiddenCount > 0 {
                    Circle()
                        .fill(SoftLedgerTheme.canvas)
                        .frame(width: size, height: size)
                        .overlay {
                            Text("+\(hiddenCount)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(SoftLedgerTheme.secondaryInk)
                        }
                        .overlay {
                            Circle().stroke(borderColor, lineWidth: 2)
                        }
                        .accessibilityHidden(true)
                }
            }

            if showsTotal {
                Text(L("%@ total").replacingOccurrences(of: "%@", with: "\(members.count)"))
                    .font(.subheadline)
                    .foregroundStyle(SoftLedgerTheme.secondaryInk)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("%@ members").replacingOccurrences(of: "%@", with: "\(members.count)"))
    }
}

struct SoftLedgerInlineStat: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(SoftLedgerTheme.mutedInk)
            Text(value)
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SoftLedgerToast: View {
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Text(message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SoftLedgerTheme.ink)
                .lineLimit(1)
            Button(actionTitle, action: action)
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule().stroke(SoftLedgerTheme.rule.opacity(0.62), lineWidth: 1)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
    }
}

struct ExpenseCategory: Identifiable, Hashable {
    let id: String
    let titleKey: String
    let symbol: String
    let color: Color
}

let expenseCategories: [ExpenseCategory] = [
    .init(id: "food", titleKey: "Meal", symbol: "fork.knife", color: Color(red: 0.188, green: 0.424, blue: 0.537)),
    .init(id: "beverage", titleKey: "Drink", symbol: "cup.and.saucer.fill", color: Color(red: 0.522, green: 0.384, blue: 0.250)),
    .init(id: "accommodation", titleKey: "Hotel", symbol: "bed.double.fill", color: SoftLedgerTheme.accent),
    .init(id: "shopping", titleKey: "Shopping", symbol: "cart.fill", color: Color(red: 0.314, green: 0.470, blue: 0.760)),
    .init(id: "traffic", titleKey: "Transport", symbol: "tram.fill", color: SoftLedgerTheme.positive),
    .init(id: "stay", titleKey: "Stay", symbol: "house.fill", color: Color(red: 0.376, green: 0.570, blue: 0.494)),
    .init(id: "vacation", titleKey: "Vacation", symbol: "beach.umbrella.fill", color: Color(red: 0.290, green: 0.565, blue: 0.690)),
    .init(id: "transfer", titleKey: "Transfer", symbol: "banknote.fill", color: Color(red: 0.620, green: 0.514, blue: 0.218)),
    .init(id: "ticket", titleKey: "Ticket", symbol: "ticket.fill", color: Color(red: 0.612, green: 0.424, blue: 0.729)),
    .init(id: "game", titleKey: "Game", symbol: "dice.fill", color: Color(red: 0.553, green: 0.455, blue: 0.742)),
    .init(id: "other", titleKey: "Other", symbol: "ellipsis", color: SoftLedgerTheme.mutedInk)
]

func expenseCategory(for id: String) -> ExpenseCategory {
    expenseCategories.first(where: { $0.id == id }) ?? expenseCategories.last!
}

func signedMoney(_ value: MoneyMinor?) -> String {
    if Money.isZero(value) {
        return "¥\(Money.display(value))"
    }
    if Money.isNegative(value) {
        return "-¥\(Money.display(Money.negate(value ?? "0")))"
    }
    return "+¥\(Money.display(value))"
}

func moneyColor(_ value: MoneyMinor?) -> Color {
    if Money.isZero(value) { return SoftLedgerTheme.mutedInk }
    return Money.isNegative(value) ? SoftLedgerTheme.negative : SoftLedgerTheme.positive
}

func recordTitle(_ record: WalkRecord) -> String {
    if !record.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return record.text
    }
    return L(expenseCategory(for: record.type).titleKey)
}

extension Array {
    func chunks(of size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

private extension View {
    func softLedgerGlass(cornerRadius: CGFloat) -> some View {
        modifier(SoftLedgerGlassModifier(cornerRadius: cornerRadius))
    }
}
