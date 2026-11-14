// Run this with an iOS Simulator build of Swift and `simctl spawn`.
// Argument: absolute path to Resources/Assets.xcassets/StartupTitle.imageset.
// Keep the title vector-based so the launch storyboard and runtime share the
// exact same native font rendering at every scale, without custom launch code.
import UIKit

let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let font = UIFont.systemFont(ofSize: 21, weight: .medium)
let bounds = CGRect(x: 0, y: 0, width: 310, height: 31)
let variants: [(String, UIColor)] = [
    ("Light", UIColor(red: 30 / 255, green: 30 / 255, blue: 30 / 255, alpha: 1)),
    ("Dark", UIColor(red: 245 / 255, green: 245 / 255, blue: 242 / 255, alpha: 1))
]
for (name, color) in variants {
    let data = UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
        context.beginPage()
        ("Walking Calculator" as NSString).draw(at: .zero, withAttributes: [
            .font: font, .foregroundColor: color
        ])
    }
    try data.write(to: destination.appendingPathComponent("StartupTitle-\(name).pdf"))
}
