import SwiftUI
import UIKit

/// Keep navigation touches quiet while successful writes remain distinct.
@MainActor
enum SoftLedgerHaptics {
    static func tap(emphasized: Bool = false) -> SensoryFeedback {
        .impact(weight: .light, intensity: emphasized ? 0.85 : 0.65)
    }

    static let selection = SensoryFeedback.impact(weight: .light, intensity: 0.55)

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

enum SoftLedgerTheme {
    static let canvas = SoftLedgerThemeConfig.neutral.canvas.color
    static let paper = SoftLedgerThemeConfig.neutral.paper.color
    static let formPaper = SoftLedgerThemeConfig.neutral.formPaper.color
    static let ink = SoftLedgerThemeConfig.neutral.defaultText.color
    static let secondaryInk = SoftLedgerThemeConfig.neutral.secondaryText.color
    static let mutedInk = SoftLedgerThemeConfig.neutral.mutedText.color
    static let rule = SoftLedgerThemeConfig.neutral.rule.color
    #if DEBUG
    static var positive: Color { DebugMoneyColors.shared.positive }
    static var negative: Color { DebugMoneyColors.shared.negative }
    #else
    static let positive = SoftLedgerThemeConfig.neutral.positive.color
    static let negative = SoftLedgerThemeConfig.neutral.negative.color
    #endif
    static let yellowAccent = SoftLedgerThemeConfig.yellowAccent.color
}

private struct SoftLedgerAppThemeKey: EnvironmentKey {
    static let defaultValue: AppTheme = .defaultTheme
}

extension EnvironmentValues {
    var softLedgerAppTheme: AppTheme {
        get { self[SoftLedgerAppThemeKey.self] }
        set { self[SoftLedgerAppThemeKey.self] = newValue }
    }
}

private struct SoftLedgerAccentTintModifier: ViewModifier {
    @Environment(\.softLedgerAppTheme) private var appTheme

    func body(content: Content) -> some View {
        content
            .tint(appTheme.accent)
            .background {
                SoftLedgerTextInputTintBridge(tintColor: appTheme.accentUIColor)
                    .frame(width: 0, height: 0)
            }
    }
}

private struct SoftLedgerAccentForegroundModifier: ViewModifier {
    @Environment(\.softLedgerAppTheme) private var appTheme

    func body(content: Content) -> some View {
        content.foregroundStyle(appTheme.accent)
    }
}

private struct SoftLedgerUIKitTintBridge: UIViewRepresentable {
    let appTheme: AppTheme

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            appTheme.applySystemControlTint()
            let tintColor = appTheme.systemControlTintUIColor
            uiView.window?.tintColor = tintColor
            uiView.closestViewController()?.view.tintColor = tintColor
        }
    }
}

private struct SoftLedgerTextInputTintBridge: UIViewRepresentable {
    let tintColor: UIColor

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            uiView.softLedgerApplyTextInputTint(tintColor)
        }
    }
}

private extension UIView {
    func softLedgerApplyTextInputTint(_ tintColor: UIColor) {
        var ancestor: UIView? = superview
        var remainingDepth = 4

        while let candidate = ancestor, remainingDepth > 0 {
            let inputs = candidate.softLedgerTextInputDescendants()
            if !inputs.isEmpty {
                inputs.forEach { input in
                    input.tintColor = tintColor
                }
                return
            }

            ancestor = candidate.superview
            remainingDepth -= 1
        }
    }

    func softLedgerTextInputDescendants() -> [UIView] {
        var result: [UIView] = []

        if self is UITextField || self is UITextView {
            result.append(self)
        }

        for subview in subviews {
            result.append(contentsOf: subview.softLedgerTextInputDescendants())
        }

        return result
    }

    func closestViewController() -> UIViewController? {
        var responder: UIResponder? = self

        while let candidate = responder {
            if let viewController = candidate as? UIViewController {
                return viewController
            }

            responder = candidate.next
        }

        return nil
    }
}

extension View {
    func softLedgerAccentTint() -> some View {
        modifier(SoftLedgerAccentTintModifier())
    }

    func softLedgerAccentForeground() -> some View {
        modifier(SoftLedgerAccentForegroundModifier())
    }

    func softLedgerUIKitTint(_ appTheme: AppTheme) -> some View {
        background {
            SoftLedgerUIKitTintBridge(appTheme: appTheme)
                .frame(width: 0, height: 0)
        }
    }
}

struct SoftLedgerBackground: View {
    var body: some View {
        SoftLedgerTheme.canvas.ignoresSafeArea()
    }
}

/// Inline pagination row; its parent supplies the surrounding card and insets.
struct LedgerPaginationLoadingView: View {
    @ScaledMetric(relativeTo: .subheadline) private var iconSize = 30
    @ScaledMetric(relativeTo: .subheadline) private var rowMinHeight = 54

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
                .tint(SoftLedgerTheme.secondaryInk)
                .frame(width: iconSize, height: iconSize)
            Text(L("Loading"))
                .font(.subheadline)
                .foregroundStyle(SoftLedgerTheme.secondaryInk)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: rowMinHeight, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Loading"))
    }
}

struct AsyncConfirmationIcon: View {
    let isPending: Bool
    var systemImage = "checkmark"

    var body: some View {
        Group {
            if isPending {
                ProgressView()
                    .controlSize(.small)
                    .softLedgerProgressTint()
            } else {
                Image(systemName: systemImage)
            }
        }
        .frame(width: 18, height: 18)
    }
}

struct AnimatedBalanceAmountText: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let amountMinor: MoneyMinor
    var style: MoneyDisplayStyle = .exact
    var currencyCode: String? = nil
    var isAnimationEnabled = true
    var foregroundColor: Color = SoftLedgerTheme.ink

    @State private var displayedAmountMinor: MoneyMinor?
    @State private var pendingAmountMinor: MoneyMinor?
    @State private var isPulsing = false
    @State private var pendingCommitTask: Task<Void, Never>?

    private var resolvedAmountMinor: MoneyMinor {
        displayedAmountMinor ?? amountMinor
    }

    private var transitionValue: Double {
        NSDecimalNumber(decimal: Money.decimal(resolvedAmountMinor) / 100).doubleValue
    }

    var body: some View {
        Text(signedMoney(resolvedAmountMinor, style: style, currencyCode: currencyCode))
            .foregroundStyle(foregroundColor)
            .contentTransition(.numericText(value: transitionValue))
            .scaleEffect(isPulsing ? 1.018 : 1, anchor: .leading)
            .offset(y: isPulsing ? -1 : 0)
            .onAppear {
                if displayedAmountMinor == nil {
                    displayedAmountMinor = amountMinor
                }
            }
            .onDisappear {
                pendingCommitTask?.cancel()
            }
            .onChange(of: amountMinor) { _, newValue in
                receive(newValue)
            }
            .onChange(of: isAnimationEnabled) { _, isEnabled in
                guard isEnabled, let pendingAmountMinor else { return }
                self.pendingAmountMinor = nil
                scheduleCommit(pendingAmountMinor, delayNanoseconds: 280_000_000)
            }
    }

    private func receive(_ newValue: MoneyMinor) {
        guard displayedAmountMinor != nil else {
            displayedAmountMinor = newValue
            return
        }

        guard newValue != displayedAmountMinor else {
            pendingAmountMinor = nil
            return
        }

        if isAnimationEnabled {
            scheduleCommit(newValue, delayNanoseconds: 80_000_000)
        } else {
            pendingCommitTask?.cancel()
            pendingAmountMinor = newValue
        }
    }

    private func scheduleCommit(_ newValue: MoneyMinor, delayNanoseconds: UInt64) {
        pendingCommitTask?.cancel()
        pendingCommitTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: reduceMotion ? 0 : delayNanoseconds)
            guard !Task.isCancelled else { return }
            commit(newValue)
        }
    }

    @MainActor
    private func commit(_ newValue: MoneyMinor) {
        guard newValue != displayedAmountMinor else { return }

        if reduceMotion {
            displayedAmountMinor = newValue
            isPulsing = false
            return
        }

        withAnimation(.snappy(duration: 0.34)) {
            displayedAmountMinor = newValue
            isPulsing = true
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.smooth(duration: 0.22)) {
                isPulsing = false
            }
        }
    }
}

private struct SoftLedgerProgressTintModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.tint(.secondary)
    }
}

struct SoftLedgerCard<Content: View>: View {
    var cornerRadius: CGFloat = SoftLedgerCornerRadius.card
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
                        .strokeBorder(SoftLedgerTheme.rule.opacity(0.70), lineWidth: 1)
                }
        } else {
            content
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .softLedgerSurface(cornerRadius: cornerRadius, borderOpacity: 0.68)
        }
    }
}

private struct SoftLedgerGlassModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .glassEffect(.regular.tint(SoftLedgerTheme.paper.opacity(0.26)), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct SoftLedgerAvatar: View {
    @Environment(\.colorScheme) private var colorScheme

    var user: UserProfile?
    var member: Member?
    var initial: String?
    var size: CGFloat = 40
    var borderColor: Color = SoftLedgerTheme.paper

    private var displayName: String {
        user?.name ?? member?.name ?? initial ?? "?"
    }

    private var avatarURL: URL? {
        SoftLedgerAvatarURL.url(from: user?.avatar ?? member?.avatar ?? "")
    }

    private var fallbackColors: WalletColorPair {
        let identifier = user?.uuid ?? member?.uuid ?? displayName
        // Stable across launches; Swift's hashValue uses a random seed.
        let hash = identifier.utf8.reduce(UInt64(14_695_981_039_346_656_037)) {
            ($0 ^ UInt64($1)) &* 1_099_511_628_211
        }
        let palette = WalletColorPair.defaults
        let base = palette[Int(hash % UInt64(palette.count))].first
        return CategoryBadgeAppearance.colors(base: base, saturation: colorScheme == .dark
            ? CategoryBadgeAppearance.darkSaturation : CategoryBadgeAppearance.lightSaturation)
    }

    var body: some View {
        Group {
            if let avatarURL {
                SoftLedgerCachedAvatarImage(url: avatarURL) {
                    fallback
                }
                .id(avatarURL)
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var fallback: some View {
        let colors = fallbackColors
        return Circle()
            .fill(LinearGradient(colors: [colors.first.color, colors.second.color],
                                 startPoint: .top, endPoint: .bottom))
            .overlay {
                Text(String(displayName.prefix(1)).uppercased())
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(colors.ink(mode: .automatic, custom: .black).color)
            }
    }
}

private enum SoftLedgerAvatarURL {
    static func url(from rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) ?? percentEncodedURL(from: trimmed),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = components.host?.lowercased() else {
            return nil
        }

        // Uploads include dimensions and a thumbnail hash in the fragment.
        components.fragment = nil
        if host.hasSuffix(".aliyuncs.com"), components.query == nil {
            components.queryItems = [
                URLQueryItem(name: "x-oss-process", value: "image/resize,w_320")
            ]
        }
        return components.url
    }

    private static func percentEncodedURL(from value: String) -> URL? {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.insert(charactersIn: "#")
        return value
            .addingPercentEncoding(withAllowedCharacters: allowed)
            .flatMap(URL.init(string:))
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
        .task {
            let loadedImage = await SoftLedgerAvatarImageCache.shared.image(for: url)
            if !Task.isCancelled {
                image = loadedImage
            }
        }
    }
}

private actor SoftLedgerAvatarImageCache {
    static let shared = SoftLedgerAvatarImageCache()

    private let cache = NSCache<NSURL, UIImage>()
    private let diskCache = URLCache(
        memoryCapacity: 0,
        diskCapacity: 128 * 1024 * 1024,
        diskPath: "walkcalc-avatar-cache"
    )
    private let session: URLSession
    private var downloads: [URL: Task<UIImage?, Never>] = [:]

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
        cache.countLimit = 240
        cache.totalCostLimit = 24 * 1024 * 1024
    }

    func image(for url: URL) async -> UIImage? {
        if let image = cache.object(forKey: url as NSURL) {
            return image
        }
        if let download = downloads[url] {
            return await download.value
        }

        let request = URLRequest(url: url)
        if let response = diskCache.cachedResponse(for: request), let image = UIImage(data: response.data) {
            insert(image, for: url)
            return image
        }

        let download = Task { await fetch(request, for: url) }
        downloads[url] = download
        let image = await download.value
        downloads[url] = nil
        return image
    }

    private func fetch(_ request: URLRequest, for url: URL) async -> UIImage? {
        guard let (data, response) = try? await session.data(for: request),
              let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode),
              let image = UIImage(data: data) else {
            return nil
        }

        diskCache.storeCachedResponse(CachedURLResponse(response: response, data: data), for: request)
        insert(image, for: url)
        return image
    }

    private func insert(_ image: UIImage, for url: URL) {
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        cache.setObject(image, forKey: url as NSURL, cost: cost)
    }
}

struct SoftLedgerAvatarStack: View {
    @ScaledMetric(relativeTo: .caption) private var defaultSize = 28

    let members: [Member]
    var visibleCount = 4
    var size: CGFloat?
    var borderColor: Color = SoftLedgerTheme.paper
    var showsTotal = false
    var totalCount: Int? = nil

    private var avatarSize: CGFloat {
        size ?? defaultSize
    }

    private var visibleMembers: [Member] {
        Array(members.prefix(visibleCount))
    }

    private var memberCount: Int {
        max(members.count, totalCount ?? 0)
    }

    private var hiddenCount: Int {
        memberCount - visibleMembers.count
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
                Text(L("%@ total").replacingOccurrences(of: "%@", with: "\(memberCount)"))
                    .font(.subheadline)
                    .foregroundStyle(SoftLedgerTheme.secondaryInk)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("%@ members").replacingOccurrences(of: "%@", with: "\(memberCount)"))
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
    let emoji: String
    let paletteID: String

    var paletteColor: WalletRGB {
        let entry = WalletColorPair.defaultPalette.first { $0.id == paletteID }
        return WalletRGB(hex: entry?.hex ?? 0xA4BAEA)
    }
}

let expenseCategories: [ExpenseCategory] = [
    .init(id: "food", titleKey: "Meal", symbol: "fork.knife", emoji: "🍽️", paletteID: "apricot"),
    .init(id: "beverage", titleKey: "Drink", symbol: "cup.and.saucer.fill", emoji: "☕️", paletteID: "cream"),
    .init(id: "accommodation", titleKey: "Hotel", symbol: "bed.double.fill", emoji: "🛏️", paletteID: "iris"),
    .init(id: "shopping", titleKey: "Shopping", symbol: "cart.fill", emoji: "🛍️", paletteID: "rose"),
    .init(id: "traffic", titleKey: "Transport", symbol: "tram.fill", emoji: "🚋", paletteID: "cornflower"),
    .init(id: "stay", titleKey: "Stay", symbol: "house.fill", emoji: "🏠", paletteID: "mint"),
    .init(id: "vacation", titleKey: "Vacation", symbol: "beach.umbrella.fill", emoji: "🏖️", paletteID: "sky"),
    .init(id: "transfer", titleKey: "Transfer", symbol: "banknote.fill", emoji: "💸", paletteID: "pistachio"),
    .init(id: "ticket", titleKey: "Ticket", symbol: "ticket.fill", emoji: "🎟️", paletteID: "rose"),
    .init(id: "game", titleKey: "Game", symbol: "dice.fill", emoji: "🎲", paletteID: "iris"),
    .init(id: "other", titleKey: "Other", symbol: "tag.fill", emoji: "🏷️", paletteID: "cornflower")
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

enum MoneyDisplayStyle {
    case compact
    case exact

    func string(_ value: MoneyMinor?) -> String {
        switch self {
        case .compact:
            Money.compactDisplay(value)
        case .exact:
            Money.display(value)
        }
    }
}

func signedMoney(_ value: MoneyMinor?, style: MoneyDisplayStyle = .compact, currencyCode: String? = nil) -> String {
    CurrencyCatalog.formatted(value, currencyCode: currencyCode, style: style)
}

func moneyColor(_ value: MoneyMinor?) -> Color {
    if Money.isZero(value) { return SoftLedgerTheme.mutedInk }
    return Money.isNegative(value) ? SoftLedgerTheme.negative : SoftLedgerTheme.positive
}

func recordNoteForDisplay(_ record: WalkRecord) -> String {
    record.isDebtResolve && record.text == WalkRecord.automaticSettlementNote
        ? L("Debt Resolve")
        : record.text
}

func recordTitle(_ record: WalkRecord) -> String {
    let note = recordNoteForDisplay(record)
    return note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? L(expenseCategory(for: record).titleKey)
        : note
}

extension Array {
    func chunks(of size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

extension View {
    func immersiveWebSheet() -> some View {
        modifier(ImmersiveWebSheetModifier())
    }

    func softLedgerProgressTint() -> some View {
        modifier(SoftLedgerProgressTintModifier())
    }

    func softLedgerDismissesKeyboardOnBackgroundTap(isActive: Bool = true, onDismiss: @escaping () -> Void = {}) -> some View {
        modifier(SoftLedgerKeyboardDismissModifier(isActive: isActive, onDismiss: onDismiss))
    }
}

private struct ImmersiveWebSheetModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let background: Color = colorScheme == .dark ? .black : .white
        content
            // Only the background extends behind Duo's side status region;
            // web controls continue to respect the asymmetric safe area.
            .background(background.ignoresSafeArea())
            .presentationBackground(background)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
    }
}

private extension View {
    func softLedgerGlass(cornerRadius: CGFloat) -> some View {
        modifier(SoftLedgerGlassModifier(cornerRadius: cornerRadius))
    }
}

private struct SoftLedgerKeyboardDismissModifier: ViewModifier {
    let isActive: Bool
    let onDismiss: () -> Void

    func body(content: Content) -> some View {
        content
            .background {
                SoftLedgerKeyboardDismissLayer(isActive: isActive, onDismiss: onDismiss)
                    .frame(width: 0, height: 0)
            }
    }
}

private struct SoftLedgerKeyboardDismissLayer: UIViewRepresentable {
    let isActive: Bool
    let onDismiss: () -> Void

    func makeUIView(context: Context) -> UIView {
        SoftLedgerKeyboardDismissView(isActive: isActive, onDismiss: onDismiss)
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let uiView = uiView as? SoftLedgerKeyboardDismissView else { return }
        uiView.isActive = isActive
        uiView.onDismiss = onDismiss
    }

    final class SoftLedgerKeyboardDismissView: UIView, UIGestureRecognizerDelegate {
        var isActive: Bool
        var onDismiss: () -> Void

        private weak var installedWindow: UIWindow?
        private lazy var recognizer: UITapGestureRecognizer = {
            let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self
            return recognizer
        }()

        init(isActive: Bool, onDismiss: @escaping () -> Void) {
            self.isActive = isActive
            self.onDismiss = onDismiss
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            backgroundColor = .clear
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()

            guard installedWindow !== window else { return }
            installedWindow?.removeGestureRecognizer(recognizer)
            installedWindow = window
            window?.addGestureRecognizer(recognizer)
        }

        deinit {
            installedWindow?.removeGestureRecognizer(recognizer)
        }

        @objc private func handleTap() {
            guard isActive, let window = installedWindow else { return }
            window.endEditing(true)
            onDismiss()
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard isActive else { return false }

            var touchedView: UIView? = touch.view
            while let view = touchedView {
                if view is UITextField || view is UITextView {
                    return false
                }
                touchedView = view.superview
            }
            return true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
