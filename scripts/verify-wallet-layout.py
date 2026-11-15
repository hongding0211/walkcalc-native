#!/usr/bin/env python3
"""Check wallet sizing across window shapes, currency counts and Dynamic Type."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'walkcalc-native/Features/Groups/WalletLayoutMetrics.swift').read_text()
source += (root / 'walkcalc-native/Features/Groups/WalletStackSpacing.swift').read_text()
source += r'''
func metrics(width: CGFloat, height: CGFloat, count: Int, text: CGFloat = 110,
             exposure: CGFloat = 32, fraction: Double = 0.3,
             regularWidth: Bool = true) -> WalletLayoutMetrics {
    WalletLayoutMetrics(width: width, cardInset: 18, glassHeightRatio: 0.8,
        exposedHeight: exposure,
        stackHeight: WalletStackSpacing(count: count, exposure: exposure, compression: 0.04).stackHeight,
        contentHeight: text,
        maximumHeight: WalletHeightLimit.maximumHeight(viewportHeight: height, fraction: fraction,
            regularWidth: regularWidth))
}
let phone = metrics(width: 353, height: 852, count: 1, regularWidth: false)
precondition(phone.height < 852 * 0.3, "An ordinary phone retains its natural wallet height")
let duo = metrics(width: 660, height: 960, count: 4)
let duoStack = WalletStackSpacing(count: 4, exposure: 32, compression: 0.04).stackHeight
precondition(abs(duo.height - duoStack - 288) < 0.001,
    "Cap the single-card baseline, then add the exposed stack height")
precondition(duo.glassHeight >= 110, "Settlement copy stays readable")
let uncappedDuo = metrics(width: 660, height: 960, count: 4, regularWidth: false)
precondition(duo.cardHeight < uncappedDuo.cardHeight, "Capped deck resizes the artwork too")
let smaller = metrics(width: 660, height: 960, count: 4, fraction: 0.25)
let larger = metrics(width: 660, height: 960, count: 4, fraction: 0.4)
precondition(smaller.height < duo.height && larger.height > duo.height, "Slider changes visible wallet height")
for width: CGFloat in [280, 353, 500, 660, 900] {
    for height: CGFloat in [320, 600, 852, 960] {
        for count in [1, 4, 12] {
            for text: CGFloat in [110, 240] {
                let value = metrics(width: width, height: height, count: count, text: text)
                precondition(value.height.isFinite && value.glassHeight >= text)
                let stack = WalletStackSpacing(count: count, exposure: 32, compression: 0.04).stackHeight
                let single = metrics(width: width, height: height, count: 1, text: text)
                precondition(abs(value.height - single.height - stack) < 0.001,
                    "Additional cards grow the total height by their exposed stack")
                precondition(abs(value.cardHeight - single.cardHeight) < 0.001
                    && abs(value.glassHeight - single.glassHeight) < 0.001,
                    "More cards never squeeze the baseline card or pocket")
                precondition(value.height >= 22 + stack + 32 + text + 12 - 0.001,
                    "Never overlap the currency headers and settlement copy")
                precondition(22 + stack + value.cardHeight <= value.height - 12,
                    "Even with the mask fully open, resting cards cannot extend below the wallet")
                let renderedCardHeight = WalletLayoutMetrics.fittedCardHeight(width: width,
                    cardInset: 18, walletHeight: value.height, stackHeight: stack)
                precondition(abs(renderedCardHeight - value.cardHeight) < 0.001,
                    "Foreground cards use the same size as layout")
                // The optional frosted backdrop only knows the final pocket
                // height. Its reconstructed artwork must align with the deck.
                let backdrop = WalletLayoutMetrics(width: width, cardInset: 18,
                    glassHeightRatio: 0.8, exposedHeight: 32, stackHeight: stack,
                    contentHeight: value.glassHeight, maximumHeight: height * 0.3)
                precondition(abs(backdrop.height - value.height) < 0.001)
                precondition(abs(backdrop.cardHeight - value.cardHeight) < 0.001,
                    "Frosted backdrop and draggable cards must have identical heights")
            }
        }
    }
}
precondition(WalletHeightLimit.maximumHeight(viewportHeight: 0, fraction: 0.3, regularWidth: true) == nil)
precondition(WalletHeightLimit.maximumHeight(viewportHeight: 1000, fraction: .nan, regularWidth: true) == 300)
for width: CGFloat in [280, 400, 466, 500, 660, 900] {
    let small = metrics(width: width, height: 669, count: 4, fraction: 0.2, regularWidth: false)
    let large = metrics(width: width, height: 669, count: 4, fraction: 0.5, regularWidth: false)
    precondition(small.height == large.height && small.cardHeight == large.cardHeight,
        "Compact size class retains the natural size regardless of geometry or slider")
    precondition(abs(small.cardHeight - (width - 36) / WalletLayoutMetrics.cardAspectRatio) < 0.001)
}
let narrowRegular = metrics(width: 466, height: 669, count: 1, fraction: 0.3)
precondition(abs(narrowRegular.height - 669 * 0.3) < 0.001,
    "Regular size class applies the cap even below the former width breakpoint")
let naturallyShort = metrics(width: 280, height: 960, count: 1, fraction: 0.5)
let uncappedShort = metrics(width: 280, height: 960, count: 1, fraction: 0.5, regularWidth: false)
precondition(naturallyShort.height == uncappedShort.height,
    "Regular size class does not enlarge a wallet that already fits below the cap")
print("PASS: baseline cap, additive stack height, system size-class policy, open-mask bounds, large text and backdrop alignment")
'''
with tempfile.TemporaryDirectory(prefix='walkcalc-wallet-layout-') as folder:
    path = Path(folder)
    (path / 'main.swift').write_text(source)
    subprocess.run(['xcrun', 'swiftc', str(path / 'main.swift'), '-o', str(path / 'verify')], check=True)
    subprocess.run([str(path / 'verify')], check=True)
