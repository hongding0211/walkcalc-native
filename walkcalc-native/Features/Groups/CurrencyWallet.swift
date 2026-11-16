import SwiftUI
import UIKit

extension WalletRGB {
    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: 1) }
}

// Stable seeds vary the mesh and placement without a timer or random redraws.
private struct WalletComposition {
    private var state: UInt64

    init(seed: Int) { state = UInt64(seed + 1) &* 2_654_435_761 }

    mutating func next() -> Float {
        state = state &* 6_364_136_223_846_793_005 &+ 1
        return Float((state >> 32) & 0xFFFF) / 65_535
    }

    static func points(seed: Int) -> [SIMD2<Float>] {
        var generator = Self(seed: seed)
        return (0..<(WalletFluidField.columns * WalletFluidField.rows)).map { index in
            let row = index / WalletFluidField.columns
            let column = index % WalletFluidField.columns
            let x = Float(column) / Float(WalletFluidField.columns - 1)
            let y = Float(row) / Float(WalletFluidField.rows - 1)
            // Bound jitter inside each cell; edges remain pinned to the card.
            let dx: Float = column == 0 || column == WalletFluidField.columns - 1
                ? 0 : (generator.next() - 0.5) * 0.055
            let dy: Float = row == 0 || row == WalletFluidField.rows - 1
                ? 0 : (generator.next() - 0.5) * 0.065
            return SIMD2(x + dx, y + dy)
        }
    }

    static func angle(at index: Int, count: Int, appearance: WalletAppearance) -> Double {
        guard count > 1 else { return 0 }
        var generator = Self(seed: index + 41)
        // A progressive fan keeps neighbouring text baselines from colliding.
        let angles = [-5.0, -1.5, 2.0]
        let base = angles[index % angles.count] + Double(generator.next()) * 0.35
        let convergence = WalletStackSpacing.tiltFactor(count: count, decay: appearance.tiltDecay)
        return base * appearance.tilt * convergence
    }
}

private enum WalletGeometry {
    // Leave visible side rails around the rotated cards; only their tops peek out.
    static let topInset = WalletLayoutMetrics.topInset
    static let glassInset: CGFloat = 10
    static let bottomInset = WalletLayoutMetrics.bottomInset
    static let cardRadius = SoftLedgerCornerRadius.card
    static let backingRadius = SoftLedgerCornerRadius.card
    static let pocketRadius = SoftLedgerCornerRadius.card

    static func spacing(count: Int, exposedHeight: CGFloat, compression: Double) -> WalletStackSpacing {
        WalletStackSpacing(count: count, exposure: Double(exposedHeight), compression: compression)
    }

    static func backingTopInset(offset: Double) -> CGFloat {
        // Anchor to the resting top of the entire deck, independent of its count
        // and compressed gaps. Extra cards then extend the backing with the wallet.
        max(0, topInset + offset)
    }


    static func stagger(_ index: Int, count: Int, spread: Double) -> CGFloat {
        count == 1 ? 0 : [-4.0, 4.0, 0.0][index % 3] * spread
    }
}

// Static domain-warped colour field, inspired by the fBm/domain-warping method
// described in The Book of Shaders, chapter 13. There is deliberately no clock.
private enum WalletFluidField {
    static let columns = 11
    static let rows = 9

    private static func smooth(_ value: Double) -> Double {
        let t = min(1, max(0, value))
        return t * t * (3 - 2 * t)
    }

    private static func hash(_ x: Double, _ y: Double, seed: Double) -> Double {
        let value = sin(x * 127.1 + y * 311.7 + seed * 53.3) * 43_758.5453
        return value - floor(value)
    }

    private static func noise(_ x: Double, _ y: Double, seed: Double) -> Double {
        let ix = floor(x), iy = floor(y)
        let tx = smooth(x - ix), ty = smooth(y - iy)
        let a = hash(ix, iy, seed: seed), b = hash(ix + 1, iy, seed: seed)
        let c = hash(ix, iy + 1, seed: seed), d = hash(ix + 1, iy + 1, seed: seed)
        return (a + (b - a) * tx) * (1 - ty) + (c + (d - c) * tx) * ty
    }

    private static func fbm(_ x: Double, _ y: Double, seed: Double) -> Double {
        var px = x, py = y, result = 0.0, amplitude = 0.57, weight = 0.0
        for octave in 0..<3 {
            result += amplitude * noise(px, py, seed: seed + Double(octave) * 7)
            weight += amplitude
            // Rotate octave coordinates to avoid grid-aligned details.
            let nextX = (px * 0.8 - py * 0.6) * 2.03 + 4.7
            py = (px * 0.6 + py * 0.8) * 2.03 + 1.9
            px = nextX
            amplitude *= 0.46
        }
        return result / weight
    }

    static func colors(index: Int, appearance: WalletAppearance) -> [Color] {
        let pair = appearance.colors(at: index)
        let flow = appearance.flow
        let seed = Double(index * 17 + 11)
        return (0..<(columns * rows)).map { cell in
            let u = Double(cell % columns) / Double(columns - 1)
            let v = Double(cell / columns) / Double(rows - 1)
            // Broad off-centre curl, then nested noise displacement. Sampling
            // the final field gives islands and curved streams, not colour rows.
            let dx = u - 0.35, dy = v - 0.42
            let angle = flow * 2.8 * exp(-(dx * dx * 3.0 + dy * dy * 2.0))
            let x = dx * cos(angle) - dy * sin(angle) + 0.35
            let y = dx * sin(angle) + dy * cos(angle) + 0.42
            let qx = fbm(x * 2.1, y * 1.7, seed: seed)
            let qy = fbm(x * 2.1 + 5.2, y * 1.7 + 1.3, seed: seed)
            let rx = x + flow * 1.1 * (qx - 0.5)
            let ry = y + flow * 1.1 * (qy - 0.5)
            let bend = fbm(rx * 2.2 + 1.7, ry * 2.2 + 9.2, seed: seed + 3)
            let stream = 0.5 + 0.5 * sin(rx * 5.8 + ry * 3.6 + flow * 2.5 * bend + Double(index) * 1.8)
            let width = 0.25 + appearance.gradientSoftness * 1.25
            let blend = smooth((stream - 0.5) / width + appearance.colorBalance)
            return pair.first.mixed(with: pair.second, amount: blend).color
        }
    }
}

private struct WalletCurrencySurface: View {
    let index: Int
    let appearance: WalletAppearance

    var body: some View {
        if appearance.colorSeparation == 0 {
            appearance.colors(at: index).first.color
        } else {
            MeshGradient(width: WalletFluidField.columns, height: WalletFluidField.rows,
                         points: WalletComposition.points(seed: index + 7),
                         colors: WalletFluidField.colors(index: index, appearance: appearance))
        }
    }
}

// Shared by the visible cards and the background rendered under the glass.
private struct WalletCardArtwork: View {
    let index: Int
    let appearance: WalletAppearance

    var body: some View {
        WalletCurrencySurface(index: index, appearance: appearance)
            .clipShape(RoundedRectangle(cornerRadius: WalletGeometry.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: WalletGeometry.cardRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.65), lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(0.16), radius: 4, y: -1)
    }
}

// Use the same system spring parameters as the card/slot animations. These
// timings do not rely on onChange observing every keyframe-rendered value.
private extension WalletMotion {
    func firstArrival(duration: Double, springBounce: Double? = nil) -> Double {
        guard springEnabled || springBounce != nil else { return duration }
        let spring = Spring(duration: duration, bounce: springBounce ?? bounce)
        let end = spring.settlingDuration
        // First arrival at the pocket, before subsequent spring oscillations.
        for step in 1...240 {
            let time = end * Double(step) / 240
            if spring.value(target: 1.0, time: time) >= 0.98 { return time }
        }
        return end
    }

    var landingDelay: Double {
        max(duration * peak + firstArrival(duration: duration * (1 - peak)),
            duration * slotDelay + firstArrival(duration: duration))
    }

    var maskRestoreDelay: Double {
        landingDelay * maskRestoreFraction
    }

}

// Each card owns its draw keyframes; slot placement is a separate, retargetable
// system animation. A new tap restarts from the current value/velocity, not from
// a queued resting pose, and SpringKeyframe preserves the overshoot on landing.
private struct WalletDrawRequest: Equatable {
    let id = UUID()
    let duration: Double
}

private struct WalletCardTravel: ViewModifier {
    let request: WalletDrawRequest?
    let slotDuration: Double?
    let index: Int
    let count: Int
    let exposedHeight: CGFloat
    let appearance: WalletAppearance
    let flatCards: Bool
    let reduceMotion: Bool

    private var slotAnimation: Animation? {
        guard !reduceMotion else { return nil }
        let motion = appearance.motion
        let duration = slotDuration ?? motion.duration
        let curve = motion.controlPoints
        let animation: Animation = motion.springEnabled
            ? .spring(duration: duration, bounce: motion.bounce)
            : .timingCurve(curve.x1, curve.y1, curve.x2, curve.y2, duration: duration)
        return animation.delay(duration * motion.slotDelay)
    }

    func body(content: Content) -> some View {
        let motion = appearance.motion
        let duration = request?.duration ?? motion.duration
        let drawDuration = duration * motion.peak
        let returnDuration = duration * (1 - motion.peak)
        content
            .keyframeAnimator(initialValue: 0.0, trigger: request) { view, draw in
                view
                    .rotationEffect(.degrees(flatCards || reduceMotion || count <= 1 ? 0 : motion.rotation * draw), anchor: .top)
                    .scaleEffect(reduceMotion ? 1 : 1 + motion.scale * draw, anchor: .top)
                    .offset(x: reduceMotion ? 0 : motion.horizontal * draw,
                            y: reduceMotion ? 0 : -motion.lift * draw)
            } keyframes: { _ in
                KeyframeTrack(\.self) {
                    if reduceMotion {
                        MoveKeyframe(0.0)
                    } else {
                        CubicKeyframe(1.0, duration: drawDuration)
                        if motion.springEnabled {
                            SpringKeyframe(0.0, spring: Spring(duration: returnDuration, bounce: motion.bounce))
                        } else {
                            CubicKeyframe(0.0, duration: returnDuration)
                        }
                    }
                }
            }
            .rotationEffect(.degrees(flatCards ? 0 :
                WalletComposition.angle(at: index, count: count, appearance: appearance)), anchor: .top)
            .offset(x: WalletGeometry.stagger(index, count: count, spread: appearance.spread),
                    y: CGFloat(WalletGeometry.spacing(count: count, exposedHeight: exposedHeight,
                        compression: appearance.spacingDecay).offset(at: index)))
            .animation(slotAnimation, value: index)
    }
}

// Preserve native button semantics without the pressed opacity of PlainButtonStyle.
private struct WalletCardButtonStyle: ButtonStyle {
    let onPickup: () -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, pressed in
                // Native press state begins on touch-down, before either the
                // button action or the six-point drag threshold is recognized.
                if pressed { onPickup() }
            }
    }
}

// A matching render of the card artwork cropped to the glass window. Only this
// background gets a Gaussian blur; exposed card labels and front text stay sharp.
private struct WalletBlurredBackdrop: View {
    let samples: [WalletCurrency]
    let exposedHeight: CGFloat
    let appearance: WalletAppearance
    let flatCards: Bool
    let orderedIDs: [String]
    let drawRequests: [String: WalletDrawRequest]
    let slotDurations: [String: Double]
    let reduceMotion: Bool
    let draggedID: String?
    let dragOffset: CGSize
    let maximumHeight: CGFloat?
    private var count: Int { samples.count }

    var body: some View {
        GeometryReader { geometry in
            let cardWidth = max(1, geometry.size.width + 2 * WalletGeometry.glassInset - 2 * appearance.cardInset)
            let stackHeight = CGFloat(WalletGeometry.spacing(count: count, exposedHeight: exposedHeight,
                compression: appearance.spacingDecay).stackHeight)
            let metrics = WalletLayoutMetrics(
                width: geometry.size.width + 2 * WalletGeometry.glassInset,
                cardInset: appearance.cardInset, glassHeightRatio: appearance.glassHeightRatio,
                exposedHeight: exposedHeight, stackHeight: stackHeight,
                contentHeight: geometry.size.height, maximumHeight: maximumHeight)
            let deckHeight = metrics.height - WalletGeometry.topInset - stackHeight
            let cardsTop = geometry.size.height + WalletGeometry.bottomInset - stackHeight - deckHeight
            let glassTop = WalletGeometry.topInset - cardsTop
            let backingTop = max(0, WalletGeometry.backingTopInset(offset: appearance.backingOffset) - glassTop)
            ZStack(alignment: .topLeading) {
                appearance.backingColor.color
                    .frame(height: max(0, geometry.size.height - backingTop))
                    .offset(y: backingTop)
                ForEach(samples) { sample in
                    let index = orderedIDs.firstIndex(of: sample.id) ?? 0
                    WalletCardArtwork(index: sample.artworkIndex, appearance: appearance)
                        .frame(width: cardWidth, height: metrics.cardHeight)
                        .modifier(WalletCardTravel(request: drawRequests[sample.id],
                            slotDuration: slotDurations[sample.id], index: index,
                            count: count, exposedHeight: exposedHeight, appearance: appearance,
                            flatCards: flatCards, reduceMotion: reduceMotion))
                        .offset(x: appearance.cardInset - WalletGeometry.glassInset, y: cardsTop)
                        .offset(sample.id == draggedID ? dragOffset : .zero)
                        .zIndex(Double(index))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .compositingGroup()
            .blur(radius: appearance.blur)
        }
        .clipShape(RoundedRectangle(cornerRadius: WalletGeometry.pocketRadius, style: .continuous))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct WalletGlassBoundsKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

private struct WalletOpenMask: Shape {
    func path(in rect: CGRect) -> Path {
        let overflow = max(rect.width, rect.height)
        return Path(rect.insetBy(dx: -overflow, dy: -overflow))
    }
}

// Keep the card continuous through the pocket opening. Only the side rails
// and bottom corners constrain it; clipping to the glass's rounded top edge
// cuts a black seam into the card behind it.
private struct WalletPocketMask: Shape {
    let glassFrame: CGRect
    let startFraction: Double

    func path(in rect: CGRect) -> Path {
        let overflow = max(rect.width, rect.height)
        let startY = glassFrame.minY + glassFrame.height * min(0.9, max(0, startFraction))
        var path = Path()
        path.addRect(CGRect(x: rect.minX - overflow, y: rect.minY - overflow,
                            width: rect.width + 2 * overflow,
                            height: max(0, startY - rect.minY + overflow + 1)))
        // Overlap the opening by two points, rather than leaving an inset gap.
        // The side/bottom inset still hides the cards' antialiased white stroke.
        let pocket = CGRect(x: glassFrame.minX + 1, y: startY - 1,
                            width: max(0, glassFrame.width - 2),
                            height: max(0, glassFrame.maxY - startY))
        path.addPath(UnevenRoundedRectangle(bottomLeadingRadius: WalletGeometry.pocketRadius - 1,
                                           bottomTrailingRadius: WalletGeometry.pocketRadius - 1, style: .continuous)
            .path(in: pocket))
        return path
    }
}

// Full-size artwork behind a height-limited glass pocket.
private struct CurrencyWalletLayout: Layout {
    let count: Int
    let exposedHeight: CGFloat
    let appearance: WalletAppearance
    let maximumHeight: CGFloat?

    private func metrics(width: CGFloat, subviews: Subviews) -> WalletLayoutMetrics {
        let contentHeight = subviews[subviews.count - 1]
            .sizeThatFits(.init(width: width - 2 * WalletGeometry.glassInset, height: nil)).height
        let stackHeight = CGFloat(WalletGeometry.spacing(count: count, exposedHeight: exposedHeight,
                compression: appearance.spacingDecay).stackHeight)
        return WalletLayoutMetrics(width: width, cardInset: appearance.cardInset,
            glassHeightRatio: appearance.glassHeightRatio, exposedHeight: exposedHeight,
            stackHeight: stackHeight, contentHeight: contentHeight, maximumHeight: maximumHeight)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let value = metrics(width: proposal.width ?? 350, subviews: subviews)
        return CGSize(width: proposal.width ?? 350, height: value.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        let value = metrics(width: bounds.width, subviews: subviews)
        subviews[subviews.count - 1].place(
            at: CGPoint(x: bounds.minX + WalletGeometry.glassInset, y: bounds.maxY - WalletGeometry.bottomInset - value.glassHeight),
            proposal: .init(width: bounds.width - 2 * WalletGeometry.glassInset, height: value.glassHeight))
    }
}

struct CurrencyWallet: View {
    @Environment(\.walletViewportHeight) private var viewportHeight
    @Environment(\.walletUsesExpandedLayout) private var usesExpandedLayout
    #if DEBUG
    @AppStorage(WalletHeightLimit.storageKey) private var maximumHeightFraction = WalletHeightLimit.defaultFraction
    #else
    private let maximumHeightFraction = WalletHeightLimit.defaultFraction
    #endif
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .largeTitle) private var amountSize = 36
    @ScaledMetric(relativeTo: .body) private var exposureScale = 1.0
    @AppStorage private var positionData: Data
    @State private var drawRequests: [String: WalletDrawRequest] = [:]
    @State private var slotDurations: [String: Double] = [:]
    @GestureState private var activeDragID: String?
    @State private var draggedID: String?
    @State private var dragOffset = CGSize.zero
    @State private var dragReturnToken = UUID()
    @State private var haptics = WalletHaptics()
    @State private var pocketMaskAmount = 1.0
    @State private var maskRestoreRequest: UUID?
    @State private var maskRestoreAt = ContinuousClock.now

    let samples: [WalletCurrency]
    let appearance: WalletAppearance

    init(groupID: String, participantID: String?, samples: [WalletCurrency], appearance: WalletAppearance) {
        self.samples = samples
        self.appearance = appearance
        _positionData = AppStorage(wrappedValue: Data(),
            WalletCardPosition.storageKey(groupID: groupID, participantID: participantID))
    }

    private var savedPosition: WalletCardPosition { WalletCardPosition.decode(positionData) }

    private var exposedHeight: CGFloat { appearance.exposure * exposureScale }

    private var maximumHeight: CGFloat? {
        WalletHeightLimit.maximumHeight(viewportHeight: viewportHeight,
            fraction: maximumHeightFraction, regularWidth: usesExpandedLayout)
    }

    private var availableIDs: [String] { samples.map(\.id) }
    private var orderedIDs: [String] { savedPosition.order.resolved(in: availableIDs) }
    private var orderedSamples: [WalletCurrency] {
        orderedIDs.compactMap { id in samples.first { $0.id == id } }
    }

    private var selected: WalletCurrency? {
        samples.first { $0.id == savedPosition.selectedID } ?? orderedSamples.last
    }

    var body: some View {
        if let selected {
            CurrencyWalletLayout(count: samples.count, exposedHeight: exposedHeight,
                                 appearance: appearance, maximumHeight: maximumHeight) {
                information(selected)
                    .anchorPreference(key: WalletGlassBoundsKey.self, value: .bounds) { $0 }
            }
            .backgroundPreferenceValue(WalletGlassBoundsKey.self) { anchor in
                GeometryReader { geometry in
                    if let anchor {
                        cardStack(in: geometry.size)
                            .mask {
                                ZStack {
                                    // Fade only the outside area: the card itself
                                    // stays fully opaque while the crop returns.
                                    WalletOpenMask().fill(.white.opacity(1 - pocketMaskAmount))
                                    WalletPocketMask(glassFrame: geometry[anchor],
                                                     startFraction: appearance.maskStartFraction).fill(.white)
                                }
                            }
                    }
                }
            }
            .coordinateSpace(name: "currency-wallet")
            .task(id: maskRestoreRequest) {
                guard maskRestoreRequest != nil else { return }
                do { try await ContinuousClock().sleep(until: maskRestoreAt) }
                catch { return }
                guard !Task.isCancelled, activeDragID == nil else { return }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: appearance.motion.maskFadeDuration)) { pocketMaskAmount = 1 }
            }
            .onChange(of: activeDragID) { old, current in
                // GestureState also resets on cancellation (e.g. a parent scroll).
                if current != nil { openPocketMask(immediately: true) }
                if old != nil && current == nil { returnDraggedCard() }
            }
            .onDisappear { cancelDrag() }
            .onChange(of: appearance.motion.hapticsEnabled) { _, enabled in
                if !enabled { haptics.cancelLanding() }
            }
            .onChange(of: appearance.motion.landingHaptic) { _, intensity in
                if intensity <= 0 { haptics.cancelLanding() }
            }
            .onChange(of: availableIDs) { _, ids in
                cancelDrag()
                drawRequests = drawRequests.filter { ids.contains($0.key) }
                slotDurations = slotDurations.filter { ids.contains($0.key) }
            }
            .onChange(of: reduceMotion) { _, reduced in
                if reduced { cancelDrag() }
            }
            .background {
                RoundedRectangle(cornerRadius: WalletGeometry.backingRadius, style: .continuous)
                    .fill(appearance.backingColor.color)
                    .padding(.top, WalletGeometry.backingTopInset(offset: appearance.backingOffset))
            }
        }
    }

    private func cardStack(in size: CGSize) -> some View {
        let cardWidth = max(1, size.width - 2 * appearance.cardInset)
        let stackHeight = CGFloat(WalletGeometry.spacing(count: samples.count,
            exposedHeight: exposedHeight, compression: appearance.spacingDecay).stackHeight)
        let cardHeight = WalletLayoutMetrics.fittedCardHeight(width: size.width,
            cardInset: appearance.cardInset, walletHeight: size.height, stackHeight: stackHeight)
        return ZStack(alignment: .topLeading) {
            ForEach(samples) { sample in
                let index = orderedIDs.firstIndex(of: sample.id) ?? 0
                currencyCard(sample, index: index)
                    .frame(width: cardWidth, height: cardHeight)
                    .offset(x: appearance.cardInset, y: WalletGeometry.topInset)
                    .zIndex(Double(index))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private func currencyCard(_ sample: WalletCurrency, index: Int) -> some View {
        Button { selectCard(sample.id) } label: {
            VStack {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    HStack(alignment: .center, spacing: 3) {
                        Text(sample.id)
                            .font(.subheadline.weight(.semibold))
                        if sample.isSettled {
                            Image(systemName: "checkmark.circle")
                                .font(.caption.weight(.semibold))
                                .accessibilityHidden(true)
                        }
                    }
                    Spacer(minLength: 4)
                    Text(sample.spending)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                Spacer(minLength: 0)
            }
            .foregroundStyle(appearance.cardInk(at: sample.artworkIndex).color)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { WalletCardArtwork(index: sample.artworkIndex, appearance: appearance) }
            .contentShape(RoundedRectangle(cornerRadius: WalletGeometry.cardRadius, style: .continuous))
        }
        .buttonStyle(WalletCardButtonStyle(onPickup: pickUpCard))
        .modifier(WalletCardTravel(request: drawRequests[sample.id],
            slotDuration: slotDurations[sample.id], index: index,
            count: samples.count, exposedHeight: exposedHeight, appearance: appearance,
            flatCards: typeSize.isAccessibilitySize, reduceMotion: reduceMotion))
        .offset(sample.id == draggedID ? dragOffset : .zero)
        .highPriorityGesture(cardDrag(sample.id), including: appearance.motion.dragRange > 0 ? .all : .subviews)
        .accessibilityLabel("\(sample.name), \(String(format: L("Personal spending: %@"), sample.spending))")
        .accessibilityValue(sample.isSettled ? L("Settled") : "")
        .accessibilityHint(L("Show settlement overview for this currency"))
        .accessibilityAddTraits(sample.id == selected?.id ? .isSelected : [])
    }

    private func cardDrag(_ id: String) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named("currency-wallet"))
            .updating($activeDragID) { _, active, _ in
                active = id
            }
            .onChanged { value in
                // Remove the crop in the same update as the first movement.
                // Waiting for GestureState's onChange clips the initial frame.
                openPocketMask(immediately: true)
                haptics.cancelLanding()
                dragReturnToken = UUID()
                let distance = hypot(value.translation.width, value.translation.height)
                let limit = max(0, appearance.motion.dragRange)
                let factor = distance > 0 ? min(1, limit / distance) : 0
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    draggedID = id
                    dragOffset = CGSize(width: value.translation.width * factor,
                                        height: value.translation.height * factor)
                }
            }
    }

    private func returnDraggedCard() {
        guard draggedID != nil else { return }
        let token = UUID()
        dragReturnToken = token
        haptics.scheduleLanding(
            after: appearance.motion.firstArrival(duration: appearance.motion.dragReturnDuration,
                                                   springBounce: appearance.motion.dragBounce),
            intensity: appearance.motion.landingHaptic,
            enabled: appearance.motion.hapticsEnabled && !reduceMotion)
        maskRestoreRequest = nil
        withAnimation(reduceMotion ? nil : .spring(duration: appearance.motion.dragReturnDuration,
                                                   bounce: appearance.motion.dragBounce),
                      completionCriteria: .removed) {
            dragOffset = .zero
        } completion: {
            guard dragReturnToken == token else { return }
            draggedID = nil
            scheduleMaskRestore(after: 0)
        }
    }

    private func pickUpCard() {
        // Feedback belongs to contact, not selection or an animation trigger.
        haptics.pickUp(intensity: appearance.motion.selectionHaptic,
                       enabled: appearance.motion.hapticsEnabled)
    }

    private func selectCard(_ id: String) {
        guard activeDragID == nil, availableIDs.contains(id) else { return }
        // Commit the latest intent immediately. Per-card keyframes and native
        // slot animations handle interruption without waiting for completion.
        let previousOrder = orderedIDs
        let sourceIndex = previousOrder.firstIndex(of: id) ?? 0
        let frontIndex = max(0, previousOrder.count - 1)
        let spacing = WalletGeometry.spacing(count: samples.count, exposedHeight: exposedHeight,
                                              compression: appearance.spacingDecay)
        let distance = abs(spacing.offset(at: frontIndex) - spacing.offset(at: sourceIndex))
        var motion = appearance.motion
        motion.duration = motion.duration(forDistance: distance, referenceDistance: Double(exposedHeight))

        var position = savedPosition
        position.select(id, available: availableIDs)
        let nextOrder = position.order.resolved(in: availableIDs)
        // All cards making room share this switch's duration. Draw requests keep
        // their own snapshot so a later tap doesn't retime another card in flight.
        for (index, cardID) in nextOrder.enumerated() where previousOrder.firstIndex(of: cardID) != index {
            slotDurations[cardID] = motion.duration
        }
        positionData = position.encoded
        haptics.scheduleLanding(after: motion.landingDelay,
                                intensity: motion.landingHaptic,
                                enabled: motion.hapticsEnabled && !reduceMotion)
        if !reduceMotion {
            openPocketMask()
            scheduleMaskRestore(after: motion.maskRestoreDelay)
            drawRequests[id] = WalletDrawRequest(duration: motion.duration)
        }
    }

    private func scheduleMaskRestore(after delay: Double) {
        // Rapid taps may leave another card in flight; respect its closing time.
        maskRestoreAt = max(maskRestoreAt, ContinuousClock.now.advanced(by: .seconds(delay)))
        maskRestoreRequest = UUID()
    }

    private func openPocketMask(immediately: Bool = false) {
        maskRestoreRequest = nil
        if immediately || reduceMotion {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) { pocketMaskAmount = 0 }
        } else {
            withAnimation(.easeInOut(duration: appearance.motion.maskOpenDuration)) {
                pocketMaskAmount = 0
            }
        }
    }

    private func cancelDrag() {
        haptics.cancelLanding()
        maskRestoreRequest = nil
        maskRestoreAt = ContinuousClock.now
        dragReturnToken = UUID()
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            draggedID = nil
            dragOffset = .zero
            pocketMaskAmount = 1
        }
    }

    private func information(_ sample: WalletCurrency) -> some View {
        informationContent(sample)
            // Keep the glass responsive to touch without opening a details sheet.
            .onTapGesture { }
    }

    private var nativeGlass: Glass {
        if appearance.nativeGlassOnly {
            return Glass.regular.interactive(appearance.interactiveGlass)
        }
        let tint = appearance.glassTintAmount > 0
            ? appearance.glassTint.color.opacity(appearance.glassTintAmount) : nil
        return (appearance.regularGlass ? Glass.regular : Glass.clear)
            .tint(tint)
            .interactive(appearance.interactiveGlass)
    }

    private func informationContent(_ sample: WalletCurrency) -> some View {
        VStack(alignment: .center, spacing: 6) {
            Text(sample.spending)
                .font(.system(size: amountSize, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: NSDecimalNumber(decimal: Money.decimal(sample.expenseMinor)).doubleValue))
                .animation(reduceMotion ? nil : .smooth(duration: appearance.motion.amountDuration), value: sample.spending)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .accessibilityLabel(String(format: L("Personal spending: %@"), sample.spending))
            Text(sample.settlement)
                .font(.footnote)
                // Reserve short/long settlement summaries consistently; allow
                // longer accessible text to grow instead of truncating it.
                .lineLimit(2...)
                .foregroundStyle(appearance.glassInk(at: sample.artworkIndex).color.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
                .transaction { transaction in
                    transaction.animation = nil
                    transaction.disablesAnimations = true
                }
        }
        .foregroundStyle(appearance.glassInk(at: sample.artworkIndex).color)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 22)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: WalletGeometry.pocketRadius, style: .continuous).fill(appearance.backingColor.color)
            }
        }
        // The baseline samples the real stack with unmodified system glass.
        // Optional legacy treatments remain available for an explicit comparison.
        .glassEffect(reduceTransparency ? .identity : nativeGlass, in: RoundedRectangle(cornerRadius: WalletGeometry.pocketRadius, style: .continuous))
        .background {
            if !reduceTransparency && !appearance.nativeGlassOnly {
                ZStack {
                    if appearance.extraFrost {
                        WalletBlurredBackdrop(samples: samples, exposedHeight: exposedHeight,
                                              appearance: appearance, flatCards: typeSize.isAccessibilitySize,
                                              orderedIDs: orderedIDs, drawRequests: drawRequests, slotDurations: slotDurations,
                                              reduceMotion: reduceMotion,
                                              draggedID: draggedID, dragOffset: dragOffset,
                                              maximumHeight: maximumHeight)
                        RoundedRectangle(cornerRadius: WalletGeometry.pocketRadius, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .opacity(1 - appearance.clarity)
                    }
                    RoundedRectangle(cornerRadius: WalletGeometry.pocketRadius, style: .continuous)
                        .fill(WalletRGB.black.color.opacity(appearance.tint))
                }
                .clipShape(RoundedRectangle(cornerRadius: WalletGeometry.pocketRadius, style: .continuous))
                .allowsHitTesting(false)
            }
        }
        .overlay {
            if !reduceTransparency && !appearance.nativeGlassOnly && appearance.edgeHighlight > 0 {
                RoundedRectangle(cornerRadius: WalletGeometry.pocketRadius, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [
                        .white.opacity(appearance.edgeHighlight), .white.opacity(0.03),
                        .white.opacity(appearance.edgeHighlight * 0.6)
                    ], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
