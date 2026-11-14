#!/usr/bin/env python3
"""Verify the production icon grid geometry at narrow, wide and scaled sizes."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'walkcalc-native/Shared/UI/JustifiedIconLayout.swift').read_text()
geometry = source[source.index('struct JustifiedIconGeometry'):source.index('struct JustifiedIconLayout')]
harness = r'''
func close(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool { abs(lhs - rhs) < 0.001 }
var cases = 0
for scale in [CGFloat(1), 1.5, 2.5] {
    let geometry = JustifiedIconGeometry(itemWidth: 56 * scale, iconWidth: 40 * scale, spacing: 10 * scale)
    for width in [CGFloat(180), 240, 320, 390, 600, 844] {
        for count in [0, 1, 2, 4, 5, 6, 8, 13] {
            let heights = (0..<count).map { CGFloat(54 + $0 % 3 * 7) * scale }
            let frames = geometry.frames(width: width, heights: heights)
            precondition(frames.count == count)
            let rows = Dictionary(grouping: frames, by: \.minY).sorted { $0.key < $1.key }
            var previousBottom: CGFloat?
            for (_, row) in rows {
                precondition(close(row.first!.midX - geometry.iconWidth / 2, 0))
                if row.count > 1 {
                    precondition(close(row.last!.midX + geometry.iconWidth / 2, width))
                    for index in 1..<row.count {
                        precondition(row[index].minX - row[index - 1].maxX >= geometry.spacing - 0.001)
                    }
                }
                if let previousBottom { precondition(close(row[0].minY, previousBottom + geometry.spacing)) }
                previousBottom = row.map(\.maxY).max()!
            }
            cases += 1
        }
    }
}
let four = JustifiedIconGeometry(itemWidth: 56, iconWidth: 40, spacing: 10).frames(width: 340, heights: [60, 60, 60, 60])
precondition(close(four[3].midX + 20, 340), "No phantom fifth slot")
print("PASS: \(cases) grid cases; icons touch both content edges, actual row heights, no overlaps or empty slots")
'''
with tempfile.TemporaryDirectory(prefix='walkcalc-editor-grid-') as directory:
    source_file = Path(directory) / 'main.swift'
    source_file.write_text('import Foundation\nimport CoreGraphics\n' + geometry + harness)
    binary = Path(directory) / 'verify'
    subprocess.run(['xcrun', 'swiftc', str(source_file), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
