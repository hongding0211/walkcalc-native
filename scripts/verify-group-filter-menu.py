#!/usr/bin/env python3
"""Run real UIKit menu regression checks locally using the Mac Catalyst SDK."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
sdk = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True).strip()
support = Path(sdk) / "System/iOSSupport"
with tempfile.TemporaryDirectory(prefix="walkcalc-menu-regression-") as directory:
    source = Path(directory) / "main.swift"
    source.write_text(
        (root / "walkcalc-native/Features/Groups/GroupRecordFilterMenu.swift").read_text()
        + "\n" + (root / "scripts/verification/group-filter-menu.swift").read_text()
    )
    binary = Path(directory) / "verify"
    subprocess.run([
        "xcrun", "swiftc", "-target", "arm64-apple-ios26.0-macabi", "-sdk", sdk,
        "-F", str(support / "System/Library/Frameworks"),
        "-I", str(support / "usr/include"), str(source), "-o", str(binary)
    ], check=True)
    subprocess.run([str(binary)], check=True)
