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
    static let accentUIColor = adaptiveUIColor(light: 0xB15525, dark: 0xE49B63)
    static let accentSoft = adaptive(light: 0xEDCBA4, dark: 0x38322F)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traitCollection in
            UIColor(hex: traitCollection.userInterfaceStyle == .dark ? dark : light)
        })
    }

    private static func adaptiveUIColor(light: UInt32, dark: UInt32) -> UIColor {
        UIColor { traitCollection in
            UIColor(hex: traitCollection.userInterfaceStyle == .dark ? dark : light)
        }
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
    @Environment(\.displayScale) private var displayScale

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

    private var optimizedURL: URL? {
        SoftLedgerAvatarURL.url(from: avatarURL, displaySize: size, displayScale: displayScale)
    }

    var body: some View {
        Group {
            if let optimizedURL {
                SoftLedgerCachedAvatarImage(url: optimizedURL) {
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

private enum SoftLedgerAvatarURL {
    static func url(from rawValue: String, displaySize: CGFloat, displayScale: CGFloat) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard let url = URL(string: trimmed) ?? percentEncodedURL(from: trimmed) else {
            return nil
        }

        return urlWithAvatarSize(url, displaySize: displaySize, displayScale: displayScale)
    }

    private static func percentEncodedURL(from value: String) -> URL? {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.insert(charactersIn: "#")
        return value
            .addingPercentEncoding(withAllowedCharacters: allowed)
            .flatMap(URL.init(string:))
    }

    private static func urlWithAvatarSize(_ url: URL, displaySize: CGFloat, displayScale: CGFloat) -> URL {
        guard url.host?.contains("aliyuncs.com") == true,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        let queryItems = components.queryItems ?? []
        guard !queryItems.contains(where: { $0.name == "x-oss-process" }) else {
            return url
        }

        let scale = max(displayScale, 2)
        let pixelWidth = max(64, Int((displaySize * scale).rounded(.up)))
        components.queryItems = queryItems + [
            URLQueryItem(name: "x-oss-process", value: "image/resize,w_\(pixelWidth)")
        ]
        return components.url ?? url
    }
}

private struct SoftLedgerCachedAvatarImage<Placeholder: View>: View {
    let url: URL
    @ViewBuilder var placeholder: Placeholder

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        .task(id: url) {
            await loadImage()
        }
    }

    @MainActor
    private func loadImage() async {
        if let cachedImage = SoftLedgerAvatarImageCache.shared.image(for: url) {
            image = cachedImage
            return
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad

        if let cachedImage = SoftLedgerAvatarImageCache.shared.diskImage(for: request) {
            SoftLedgerAvatarImageCache.shared.insert(cachedImage, for: url)
            image = cachedImage
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard !Task.isCancelled,
                  let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  let downloadedImage = UIImage(data: data) else {
                return
            }
            SoftLedgerAvatarImageCache.shared.store(data: data, response: response, for: request)
            SoftLedgerAvatarImageCache.shared.insert(downloadedImage, for: url)
            image = downloadedImage
        } catch {
            return
        }
    }
}

private final class SoftLedgerAvatarImageCache {
    static let shared = SoftLedgerAvatarImageCache()

    private let cache = NSCache<NSURL, UIImage>()
    private let diskCache = URLCache(
        memoryCapacity: 32 * 1024 * 1024,
        diskCapacity: 128 * 1024 * 1024,
        diskPath: "walkcalc-avatar-cache"
    )

    private init() {
        cache.countLimit = 240
        cache.totalCostLimit = 24 * 1024 * 1024
    }

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func insert(_ image: UIImage, for url: URL) {
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        cache.setObject(image, forKey: url as NSURL, cost: cost)
    }

    func diskImage(for request: URLRequest) -> UIImage? {
        guard let response = diskCache.cachedResponse(for: request) else {
            return nil
        }
        return UIImage(data: response.data)
    }

    func store(data: Data, response: URLResponse, for request: URLRequest) {
        diskCache.storeCachedResponse(CachedURLResponse(response: response, data: data), for: request)
    }
}

struct SoftLedgerAvatarStack: View {
    @ScaledMetric(relativeTo: .caption) private var defaultSize = 28

    let members: [Member]
    var visibleCount = 4
    var size: CGFloat?
    var borderColor: Color = SoftLedgerTheme.paper
    var showsTotal = false

    private var avatarSize: CGFloat {
        size ?? defaultSize
    }

    private var visibleMembers: [Member] {
        Array(members.prefix(visibleCount))
    }

    private var hiddenCount: Int {
        max(members.count - visibleMembers.count, 0)
    }

    private var overlapSpacing: CGFloat {
        -(avatarSize / 3)
    }

    private var borderWidth: CGFloat {
        max(1, avatarSize / 12)
    }

    private var labelSpacing: CGFloat {
        max(4, avatarSize / 3)
    }

    var body: some View {
        HStack(spacing: labelSpacing) {
            HStack(spacing: overlapSpacing) {
                ForEach(visibleMembers) { member in
                    SoftLedgerAvatar(member: member, size: avatarSize)
                        .overlay {
                            Circle().stroke(borderColor, lineWidth: borderWidth)
                        }
                        .accessibilityHidden(true)
                }

                if hiddenCount > 0 {
                    Circle()
                        .fill(SoftLedgerTheme.canvas)
                        .frame(width: avatarSize, height: avatarSize)
                        .overlay {
                            Text("+\(hiddenCount)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(SoftLedgerTheme.secondaryInk)
                        }
                        .overlay {
                            Circle().stroke(borderColor, lineWidth: borderWidth)
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

let transferCategory = expenseCategories.first(where: { $0.id == "transfer" })!

func expenseCategory(for id: String) -> ExpenseCategory {
    if id == "debtResolve" || id == "debt-resolve" {
        return transferCategory
    }
    return expenseCategories.first(where: { $0.id == id }) ?? expenseCategories.last!
}

func expenseCategory(for record: WalkRecord) -> ExpenseCategory {
    record.isDebtResolve ? transferCategory : expenseCategory(for: record.type)
}

func signedMoney(_ value: MoneyMinor?) -> String {
    if Money.isZero(value) {
        return "¥\(Money.compactDisplay(value))"
    }
    if Money.isNegative(value) {
        return "-¥\(Money.compactDisplay(Money.negate(value ?? "0")))"
    }
    return "+¥\(Money.compactDisplay(value))"
}

func moneyColor(_ value: MoneyMinor?) -> Color {
    if Money.isZero(value) { return SoftLedgerTheme.mutedInk }
    return Money.isNegative(value) ? SoftLedgerTheme.negative : SoftLedgerTheme.positive
}

func recordTitle(_ record: WalkRecord) -> String {
    if !record.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return record.text
    }
    return L(expenseCategory(for: record).titleKey)
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
