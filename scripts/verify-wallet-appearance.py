#!/usr/bin/env python3
"""Exercise saved-setting migration, palette math, contrast selection, and round-trips."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
folder = root / 'walkcalc-native/Features/Groups'
source = (folder / 'WalletColor.swift').read_text() + '\n' + (folder / 'WalletAppearance.swift').read_text()
source += r'''
let oldJSON = """
{"angleVariation":0,"backingOffset":-0.9090858697891235,"blur":2.370370179414749,"cardInset":18,"clarity":0.7828282713890076,"exposure":37.037037670612335,"flow":0.15,"glassHeightRatio":0.7977777659893036,"regularGlass":false,"saturation":1.2621212124824523,"spread":0.40909092128276825,"tilt":0.6969696879386902,"tint":0.33723905086517336}
"""
let saved = WalletAppearance.decode(Data(oldJSON.utf8))
precondition(saved.exposure == 37.037037670612335 && saved.cardInset == 18)
precondition(saved.tint == 0.33723905086517336 && saved.blur == 2.370370179414749)
precondition(saved.colorSeparation == 0 && saved.extraFrost && saved.interactiveGlass)
precondition(saved.backingColor.hex == "#000000")
precondition(WalletAppearance.decode(saved.encoded) == saved)
precondition(!saved.nativeGlassOnly && saved.extraFrost, "Default to the retained tuned material")
let oldNativeDefault = WalletAppearance.decode(Data(#"{"nativeGlassOnly":true,"blur":17}"#.utf8))
precondition(!oldNativeDefault.nativeGlassOnly && oldNativeDefault.blur == 17, "Restore tuned mode without resetting stored adjustments")
precondition(saved.motion == WalletMotion(), "Older exports receive motion defaults")
var motionAppearance = saved
motionAppearance.motion.easing = .custom
motionAppearance.motion.x1 = 0.35
motionAppearance.motion.lift = 73
motionAppearance.motion.dragRange = 36
motionAppearance.motion.dragReturnDuration = 0.4
precondition(WalletAppearance.decode(motionAppearance.encoded) == motionAppearance)
let partialMotion = WalletAppearance.decode(Data(#"{"motion":{"duration":0.5}}"#.utf8))
precondition(partialMotion.motion.duration == 0.5 && partialMotion.motion.lift == 44)
precondition(WalletMotion().springEnabled, "New and migrated settings use spring response")
motionAppearance.motion.bounce = 0.35
motionAppearance.motion.dragBounce = 0.27
precondition(WalletAppearance.decode(motionAppearance.encoded).motion == motionAppearance.motion)
let distanceMotion = WalletMotion()
let reference = 32.0
precondition(distanceMotion.duration(forDistance: 0, referenceDistance: reference) == distanceMotion.duration)
precondition(distanceMotion.duration(forDistance: reference, referenceDistance: reference) == distanceMotion.duration)
var lastDuration = distanceMotion.duration
for distance in stride(from: reference, through: 1000.0, by: 4) {
    let duration = distanceMotion.duration(forDistance: distance, referenceDistance: reference)
    precondition(duration >= lastDuration && duration <= distanceMotion.duration * (1 + distanceMotion.distanceExtraDuration))
    lastDuration = duration
}
var fixedMotion = distanceMotion
fixedMotion.distanceResponse = 0
precondition(fixedMotion.duration(forDistance: 1000, referenceDistance: reference) == fixedMotion.duration)
precondition(distanceMotion.duration(forDistance: 0, referenceDistance: 0).isFinite)
motionAppearance.motion.distanceResponse = 0.6
motionAppearance.motion.distanceExtraDuration = 1.2
precondition(WalletAppearance.decode(motionAppearance.encoded).motion == motionAppearance.motion)
var edited = saved
edited.nativeGlassOnly = true
edited.palette[0].first = WalletRGB(hex: 0x001177)
edited.palette[0].second = WalletRGB(hex: 0x4433AA)
edited.hueShift = 25
edited.cardInkMode = .custom
edited.cardInkColor = WalletRGB(hex: 0xFADEAA)
edited.glassTintAmount = 0.2
precondition(WalletAppearance.decode(edited.encoded) == edited, "Custom colors and options round-trip")
precondition(edited.cardInk(at: 0).hex == "#FADEAA")
edited.colorSeparation = 0
precondition(edited.colors(at: 0).first == edited.colors(at: 0).second, "Zero separation is genuinely one color")
edited.saturation = 0
let gray = edited.colors(at: 0).first
precondition(abs(gray.red - gray.green) < 0.000001 && abs(gray.green - gray.blue) < 0.000001)
let defaultAppearance = WalletAppearance()
let darkAppearance = WalletAppearance(isDark: true)
precondition(defaultAppearance.glassTintAmount == 0.6952861547470093)
precondition(darkAppearance.glassTintAmount == 0.619528591632843)
precondition(defaultAppearance.backingColor == .black)
precondition(darkAppearance.backingColor == WalletRGB(red: 0.07843017578125, green: 0.07843017578125, blue: 0.07843017578125))
var normalizedDark = darkAppearance
normalizedDark.backingColor = defaultAppearance.backingColor
normalizedDark.glassTintAmount = defaultAppearance.glassTintAmount
precondition(normalizedDark == defaultAppearance, "Only the two exported fields differ by mode")
precondition(defaultAppearance.flow == 0 && defaultAppearance.colorSeparation == 0)
precondition(defaultAppearance.backingOffset == 25.757580995559692)
precondition(defaultAppearance.exposure == 32.074074268341064)
precondition(defaultAppearance.spacingDecay == 0.03872053697705269)
precondition(defaultAppearance.tiltDecay == 0.7946127653121948)
precondition(defaultAppearance.tilt == 0.680134654045105 && defaultAppearance.spread == 0)
precondition(defaultAppearance.motion.selectionHaptic == 0.45 && defaultAppearance.motion.landingHaptic == 0.3)
precondition(defaultAppearance.glassHeightRatio == 0.7957575619220734)
precondition(defaultAppearance.blur == 12.525252103805542 && defaultAppearance.clarity == 0.7356902360916138)
precondition(defaultAppearance.saturation == 1.5999999046325684 && defaultAppearance.extraFrost)
precondition(defaultAppearance.cardInkMode == .automatic && defaultAppearance.glassInkMode == .light)
let expectedPalette: [UInt32] = [0xA4BAEA, 0xC1D99B, 0xEAB0C5, 0xEAD59A, 0x93D8EF, 0x9DD7C8, 0xB9AFEA, 0xF2BD9E]
precondition(defaultAppearance.palette.map(\.first) == expectedPalette.map { WalletRGB(hex: $0) })
precondition(defaultAppearance.palette.allSatisfy { $0.first == $0.second })
precondition(WalletAppearance.decode(Data(), isDark: true) == darkAppearance)
precondition(WalletAppearance.decode(Data("{}".utf8), isDark: true) == darkAppearance)
precondition(WalletAppearance.decode(darkAppearance.encoded, isDark: true) == darkAppearance)
let isolatedDefaults = UserDefaults(suiteName: "wallet-appearance-verification-" + UUID().uuidString)!
isolatedDefaults.set(edited.encoded, forKey: WalletAppearance.lightStorageKey)
precondition(isolatedDefaults.data(forKey: WalletAppearance.darkStorageKey) == nil)
isolatedDefaults.set(darkAppearance.encoded, forKey: WalletAppearance.darkStorageKey)
precondition(WalletAppearance.decode(isolatedDefaults.data(forKey: WalletAppearance.lightStorageKey)!) == edited)
isolatedDefaults.removeObject(forKey: WalletAppearance.lightStorageKey)
isolatedDefaults.removeObject(forKey: WalletAppearance.darkStorageKey)

for index in defaultAppearance.palette.indices {
    let pair = defaultAppearance.colors(at: index)
    let ink = defaultAppearance.cardInk(at: index)
    for step in 0...10 {
        precondition(ink.contrast(with: pair.first.mixed(with: pair.second, amount: Double(step)/10)) >= 4.5)
    }
}
for color in [WalletRGB.black, .white, WalletRGB(hex: 0x001177), WalletRGB(hex: 0xEBA9BE)] {
    let pair = WalletColorPair(first: color, second: color)
    let ink = pair.ink(mode: .automatic, custom: .black)
    precondition(ink.contrast(with: color) >= 4.5, "Automatic ink follows light and dark backgrounds")
    let v = color.hsb
    let roundTrip = WalletRGB(hue: v.hue, saturation: v.saturation, brightness: v.brightness)
    precondition(roundTrip.hex == color.hex, "HSB round-trip")
}
precondition(WalletAppearance.decode(Data("{}".utf8)) == WalletAppearance())
precondition(!WalletAppearance.decode(Data("{\"palette\":[]}".utf8)).palette.isEmpty)
print("PASS: independent light/dark defaults and persistence; legacy settings preserved; custom color persistence; same-color and grayscale limits; adaptive ink contrast; HSB round-trip")
'''
with tempfile.TemporaryDirectory(prefix='walkcalc-palette-') as temp:
    path = Path(temp)
    (path / 'main.swift').write_text(source)
    subprocess.run(['xcrun', 'swiftc', '-DDEBUG', str(path / 'main.swift'), '-o', str(path / 'verify')], check=True)
    subprocess.run([str(path / 'verify')], check=True)
