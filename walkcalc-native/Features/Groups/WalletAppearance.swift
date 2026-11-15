import Foundation

enum WalletMotionEasing: String, Codable, CaseIterable, Identifiable {
    case snappy, easeOut, easeInOut, linear, custom
    var id: Self { self }
}

struct WalletMotion: Codable, Equatable {
    var springEnabled: Bool = true
    var bounce: Double = 0.24
    var dragBounce: Double = 0.18
    var hapticsEnabled: Bool = true
    var selectionHaptic: Double = 0.45
    var landingHaptic: Double = 0.3
    var duration: Double = 0.34
    var distanceResponse: Double = 0.35
    var distanceExtraDuration: Double = 0.75
    var horizontal: Double = 28
    var lift: Double = 44
    var rotation: Double = 4
    var scale: Double = 0.012
    var slotDelay: Double = 0.18
    var peak: Double = 1.0 / 3.0
    var amountDuration: Double = 0.32
    var dragRange: Double = 28
    var dragReturnDuration: Double = 0.24
    var maskRestoreFraction: Double = 0.85
    var maskFadeDuration: Double = 0.24
    var maskOpenDuration: Double = 0.18
    var easing: WalletMotionEasing = .snappy
    var x1: Double = 0.22
    var y1: Double = 0
    var x2: Double = 0.32
    var y2: Double = 1

    init() {}

    // One exposed-card height keeps the base speed. Additional physical distance
    // adds time along a bounded exponential curve, including compressed decks.
    func duration(forDistance distance: Double, referenceDistance: Double) -> Double {
        let extraDistance = max(0, distance / max(1, referenceDistance) - 1)
        let growth = 1 - exp(-max(0, distanceResponse) * extraDistance)
        return duration * (1 + max(0, distanceExtraDuration) * growth)
    }

    var controlPoints: (x1: Double, y1: Double, x2: Double, y2: Double) {
        switch easing {
        case .snappy: (0.22, 0, 0.32, 1)
        case .easeOut: (0, 0, 0.58, 1)
        case .easeInOut: (0.42, 0, 0.58, 1)
        case .linear: (0, 0, 1, 1)
        case .custom: (x1, y1, x2, y2)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case springEnabled, bounce, dragBounce, hapticsEnabled, selectionHaptic, landingHaptic
        case distanceResponse, distanceExtraDuration
        case duration, horizontal, lift, rotation, scale, slotDelay, peak, amountDuration
        case easing, x1, y1, x2, y2, dragRange, dragReturnDuration
        case maskRestoreFraction, maskOpenDuration
        // New fade baseline replaces the previous abrupt closing preset.
        case maskFadeDuration = "maskClosingDuration"
    }

    init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        hapticsEnabled = try values.decodeIfPresent(Bool.self, forKey: .hapticsEnabled) ?? hapticsEnabled
        selectionHaptic = try values.decodeIfPresent(Double.self, forKey: .selectionHaptic) ?? selectionHaptic
        landingHaptic = try values.decodeIfPresent(Double.self, forKey: .landingHaptic) ?? landingHaptic
        springEnabled = try values.decodeIfPresent(Bool.self, forKey: .springEnabled) ?? springEnabled
        bounce = try values.decodeIfPresent(Double.self, forKey: .bounce) ?? bounce
        dragBounce = try values.decodeIfPresent(Double.self, forKey: .dragBounce) ?? dragBounce
        duration = try values.decodeIfPresent(Double.self, forKey: .duration) ?? duration
        distanceResponse = try values.decodeIfPresent(Double.self, forKey: .distanceResponse) ?? distanceResponse
        distanceExtraDuration = try values.decodeIfPresent(Double.self, forKey: .distanceExtraDuration) ?? distanceExtraDuration
        horizontal = try values.decodeIfPresent(Double.self, forKey: .horizontal) ?? horizontal
        lift = try values.decodeIfPresent(Double.self, forKey: .lift) ?? lift
        rotation = try values.decodeIfPresent(Double.self, forKey: .rotation) ?? rotation
        scale = try values.decodeIfPresent(Double.self, forKey: .scale) ?? scale
        slotDelay = try values.decodeIfPresent(Double.self, forKey: .slotDelay) ?? slotDelay
        peak = try values.decodeIfPresent(Double.self, forKey: .peak) ?? peak
        amountDuration = try values.decodeIfPresent(Double.self, forKey: .amountDuration) ?? amountDuration
        dragRange = try values.decodeIfPresent(Double.self, forKey: .dragRange) ?? dragRange
        dragReturnDuration = try values.decodeIfPresent(Double.self, forKey: .dragReturnDuration) ?? dragReturnDuration
        maskRestoreFraction = try values.decodeIfPresent(Double.self, forKey: .maskRestoreFraction) ?? maskRestoreFraction
        maskFadeDuration = try values.decodeIfPresent(Double.self, forKey: .maskFadeDuration) ?? maskFadeDuration
        maskOpenDuration = try values.decodeIfPresent(Double.self, forKey: .maskOpenDuration) ?? maskOpenDuration
        easing = try values.decodeIfPresent(WalletMotionEasing.self, forKey: .easing) ?? easing
        x1 = try values.decodeIfPresent(Double.self, forKey: .x1) ?? x1
        y1 = try values.decodeIfPresent(Double.self, forKey: .y1) ?? y1
        x2 = try values.decodeIfPresent(Double.self, forKey: .x2) ?? x2
        y2 = try values.decodeIfPresent(Double.self, forKey: .y2) ?? y2
    }
}


// Shared defaults come from the user's exported tuning values. Extra options
// decode independently so older saved settings retain all their existing values.
struct WalletAppearance: Codable, Equatable {
    var motion = WalletMotion()
    var clarity: Double = 0.7356902360916138
    var blur: Double = 12.525252103805542
    var tint: Double = 0
    var saturation: Double = 1.5999999046325684
    var flow: Double = 0
    var regularGlass: Bool = false
    var backingOffset: Double = 25.757580995559692
    var exposure: Double = 32.074074268341064
    var spacingDecay: Double = 0.03872053697705269
    var tiltDecay: Double = 0.7946127653121948
    var maskStartFraction: Double = 2.0 / 3.0
    var cardInset: Double = 18
    var tilt: Double = 0.680134654045105
    var spread: Double = 0
    var glassHeightRatio: Double = 0.7957575619220734
    // Keep the tuned material as the default; native glass is an opt-in comparison.
    var nativeGlassOnly: Bool = false
    var extraFrost: Bool = true
    var interactiveGlass: Bool = true
    var glassTint: WalletRGB = .black
    var glassTintAmount: Double = 0.6952861547470093
    var edgeHighlight: Double = 0
    var backingColor: WalletRGB = .black
    var colorSeparation: Double = 0
    var brightness: Double = 0.004040384292602561
    var hueShift: Double = 1.2121224403381348
    var colorBalance: Double = 0.3434343636035919
    var gradientSoftness: Double = 0.7632378339767456
    var palette: [WalletColorPair] = WalletColorPair.defaults
    var cardInkMode: WalletInkMode = .automatic
    var cardInkColor: WalletRGB = WalletRGB(hex: 0x141927)
    var glassInkMode: WalletInkMode = .light
    var glassInkColor: WalletRGB = WalletRGB(hex: 0xFFFFFF)

    init(isDark: Bool = false) {
        if isDark {
            backingColor = WalletRGB(red: 0.07843017578125, green: 0.07843017578125, blue: 0.07843017578125)
            glassTintAmount = 0.619528591632843
        }
    }

    private static let darkModeKey = CodingUserInfoKey(rawValue: "walletDarkMode")!

    private enum CodingKeys: String, CodingKey {
        case motion
        case clarity
        case blur
        case tint
        case saturation
        case flow
        case regularGlass
        case backingOffset
        case exposure
        case spacingDecay, tiltDecay, maskStartFraction
        case cardInset
        case tilt
        case spread
        case glassHeightRatio
        // A separate opt-in key prevents the previous default-on cache from
        // overriding the restored tuned default. All other settings stay intact.
        case nativeGlassOnly = "nativeGlassComparison"
        case extraFrost
        case interactiveGlass
        case glassTint
        case glassTintAmount
        case edgeHighlight
        case backingColor
        case colorSeparation
        case brightness
        case hueShift
        case colorBalance
        case gradientSoftness
        case palette
        case cardInkMode
        case cardInkColor
        case glassInkMode
        case glassInkColor
    }

    init(from decoder: Decoder) throws {
        self.init(isDark: decoder.userInfo[Self.darkModeKey] as? Bool ?? false)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        motion = try values.decodeIfPresent(WalletMotion.self, forKey: .motion) ?? motion
        clarity = try values.decodeIfPresent(Double.self, forKey: .clarity) ?? clarity
        blur = try values.decodeIfPresent(Double.self, forKey: .blur) ?? blur
        tint = try values.decodeIfPresent(Double.self, forKey: .tint) ?? tint
        saturation = try values.decodeIfPresent(Double.self, forKey: .saturation) ?? saturation
        flow = try values.decodeIfPresent(Double.self, forKey: .flow) ?? flow
        regularGlass = try values.decodeIfPresent(Bool.self, forKey: .regularGlass) ?? regularGlass
        backingOffset = try values.decodeIfPresent(Double.self, forKey: .backingOffset) ?? backingOffset
        spacingDecay = try values.decodeIfPresent(Double.self, forKey: .spacingDecay) ?? spacingDecay
        tiltDecay = try values.decodeIfPresent(Double.self, forKey: .tiltDecay) ?? tiltDecay
        maskStartFraction = try values.decodeIfPresent(Double.self, forKey: .maskStartFraction) ?? maskStartFraction
        exposure = try values.decodeIfPresent(Double.self, forKey: .exposure) ?? exposure
        cardInset = try values.decodeIfPresent(Double.self, forKey: .cardInset) ?? cardInset
        tilt = try values.decodeIfPresent(Double.self, forKey: .tilt) ?? tilt
        spread = try values.decodeIfPresent(Double.self, forKey: .spread) ?? spread
        glassHeightRatio = try values.decodeIfPresent(Double.self, forKey: .glassHeightRatio) ?? glassHeightRatio
        nativeGlassOnly = try values.decodeIfPresent(Bool.self, forKey: .nativeGlassOnly) ?? nativeGlassOnly
        extraFrost = try values.decodeIfPresent(Bool.self, forKey: .extraFrost) ?? extraFrost
        interactiveGlass = try values.decodeIfPresent(Bool.self, forKey: .interactiveGlass) ?? interactiveGlass
        glassTint = try values.decodeIfPresent(WalletRGB.self, forKey: .glassTint) ?? glassTint
        glassTintAmount = try values.decodeIfPresent(Double.self, forKey: .glassTintAmount) ?? glassTintAmount
        edgeHighlight = try values.decodeIfPresent(Double.self, forKey: .edgeHighlight) ?? edgeHighlight
        backingColor = try values.decodeIfPresent(WalletRGB.self, forKey: .backingColor) ?? backingColor
        colorSeparation = try values.decodeIfPresent(Double.self, forKey: .colorSeparation) ?? colorSeparation
        brightness = try values.decodeIfPresent(Double.self, forKey: .brightness) ?? brightness
        hueShift = try values.decodeIfPresent(Double.self, forKey: .hueShift) ?? hueShift
        colorBalance = try values.decodeIfPresent(Double.self, forKey: .colorBalance) ?? colorBalance
        gradientSoftness = try values.decodeIfPresent(Double.self, forKey: .gradientSoftness) ?? gradientSoftness
        palette = try values.decodeIfPresent([WalletColorPair].self, forKey: .palette) ?? palette
        cardInkMode = try values.decodeIfPresent(WalletInkMode.self, forKey: .cardInkMode) ?? cardInkMode
        cardInkColor = try values.decodeIfPresent(WalletRGB.self, forKey: .cardInkColor) ?? cardInkColor
        glassInkMode = try values.decodeIfPresent(WalletInkMode.self, forKey: .glassInkMode) ?? glassInkMode
        glassInkColor = try values.decodeIfPresent(WalletRGB.self, forKey: .glassInkColor) ?? glassInkColor
        if palette.isEmpty { palette = WalletColorPair.defaults }
    }

    var paletteCount: Int { palette.isEmpty ? WalletColorPair.defaults.count : palette.count }

    func colors(at index: Int) -> WalletColorPair {
        let choices = palette.isEmpty ? WalletColorPair.defaults : palette
        let pair = choices[abs(index) % choices.count]
        let a = pair.first.adjusted(saturation: saturation, brightness: brightness, hue: hueShift)
        let b = pair.second.adjusted(saturation: saturation, brightness: brightness, hue: hueShift)
        return WalletColorPair(first: a, second: a.mixed(with: b, amount: colorSeparation))
    }

    func cardInk(at index: Int) -> WalletRGB {
        colors(at: index).ink(mode: cardInkMode, custom: cardInkColor)
    }

    func glassInk(at index: Int) -> WalletRGB {
        let pair = colors(at: index)
        let backing = backingColor.mixed(with: pair.first.mixed(with: pair.second, amount: 0.5), amount: 0.3)
            .mixed(with: .black, amount: tint)
        return WalletColorPair(first: backing, second: backing).ink(mode: glassInkMode, custom: glassInkColor)
    }

    #if DEBUG
    // New approved baselines: leave the old single-mode v1 tuning untouched.
    static let lightStorageKey = "debug.currencyWallet.appearance.v2.light"
    static let darkStorageKey = "debug.currencyWallet.appearance.v2.dark"
    static func decode(_ data: Data, isDark: Bool = false) -> Self {
        let decoder = JSONDecoder()
        decoder.userInfo[darkModeKey] = isDark
        return (try? decoder.decode(Self.self, from: data)) ?? Self(isDark: isDark)
    }
    var encoded: Data { (try? JSONEncoder().encode(self)) ?? Data() }
    var parameterSummary: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
    #endif
}
