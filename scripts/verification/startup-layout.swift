// Compile for iOS Simulator; run with simctl spawn, passing the built .app path.
// Exercises actual storyboard constraints, including compact landscape and larger displays.
import UIKit
let app = Bundle(path: CommandLine.arguments[1])!
for style: UIUserInterfaceStyle in [.light, .dark] {
 let traits = UITraitCollection(userInterfaceStyle: style)
 for name in ["LaunchBackground", "StartupSecondaryText"] {
  let color = UIColor(named: name, in: app, compatibleWith: traits)!
  assert(color.cgColor.alpha == 1, "Startup colors must be opaque: \(name)")
 }
 let lightLogo = UIImage(named: "StartupLogo", in: app, compatibleWith: traits)
 let title = UIImage(named: "StartupTitle", in: app, compatibleWith: traits)
 assert(lightLogo != nil && title != nil)
}
let sizes = [CGSize(width: 390, height: 844), CGSize(width: 844, height: 390), CGSize(width: 320, height: 568), CGSize(width: 568, height: 320), CGSize(width: 600, height: 880), CGSize(width: 880, height: 600)]
for size in sizes {
 let vc = UIStoryboard(name: "LaunchScreen", bundle: app).instantiateInitialViewController()!
 vc.overrideUserInterfaceStyle = .light
 vc.view.frame = CGRect(origin: .zero, size: size)
 vc.view.setNeedsLayout(); vc.view.layoutIfNeeded()
 let scale = min(max(min(size.width / 390, size.height / 844), 0.82), 1)
 let ref = vc.view.viewWithTag(702)!
 let logo = vc.view.viewWithTag(704)!
 let title = vc.view.viewWithTag(703)!
 let status = vc.view.viewWithTag(701)!
 let logoFrame = logo.convert(logo.bounds, to: vc.view)
 let titleFrame = title.convert(title.bounds, to: vc.view)
 let statusFrame = status.convert(status.bounds, to: vc.view)
 assert(abs(ref.bounds.width / 390 - scale) < 0.001)
 assert(abs(logoFrame.width - 42 * scale) < 0.51)
 let buttonWidth = min(318 * scale, size.width - 48)
 let buttonLeading = (size.width - buttonWidth) / 2
 assert(abs(logoFrame.minX - buttonLeading) < 0.51)
 assert(abs(titleFrame.minX - buttonLeading) < 0.51)
 assert(abs(statusFrame.minX - buttonLeading) < 0.51)
 assert(abs((logoFrame.minY + statusFrame.maxY) / 2 - size.height / 2) < 0.51)
 assert(abs(titleFrame.minY - logoFrame.maxY - 24 * scale) < 0.51)
 assert(abs(statusFrame.minY - titleFrame.minY - 31 * scale) < 0.51)
 assert(statusFrame.maxX <= size.width - 24 + 0.01)
 func verify(_ v: UIView) { assert(!v.hasAmbiguousLayout, "Ambiguous layout: \(v)"); v.subviews.forEach(verify) }
 verify(vc.view)
 print("PASS \(Int(size.width))x\(Int(size.height)), scale \(scale)")
}
