#!/usr/bin/env python3
"""Run repository contract checks with mock HTTP on Mac Catalyst (no live API)."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
sdk = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True).strip()
support = Path(sdk) / "System/iOSSupport"
sources = [
    "Core/Models/Models.swift", "Core/Models/Money.swift",
    "Core/Networking/APIClient.swift", "Core/Networking/NativeAuthSession.swift",
    "Core/Ledger/LedgerDataLayer.swift", "Core/Ledger/InMemoryLedgerDataSource.swift",
    "Core/Ledger/SwiftDataLedgerModels.swift", "Core/Ledger/SwiftDataLedgerDataSource.swift",
    "Shared/UI/ThemeConfig.swift", "Shared/Localization/L10n.swift",
    "Debug/LedgerRepositoryVerification.swift",
]
with tempfile.TemporaryDirectory(prefix="walkcalc-repository-verification-") as directory:
    # Extract unchanged shared models from the UI file without compiling unrelated views.
    ui = (root / "walkcalc-native/Shared/UI/SoftLedgerUI.swift").read_text()
    shared = Path(directory) / "SharedModels.swift"
    shared.write_text(
        "import SwiftUI\nimport UIKit\n"
        + ui[ui.index("enum SoftLedgerTheme {"):ui.index("private struct SoftLedgerAppThemeKey")]
        + ui[ui.index("struct ExpenseCategory:"):ui.index("func signedMoney(")]
    )
    runner = Path(directory) / "Runner.swift"
    runner.write_text(
        "@main struct Runner { @MainActor static func main() async { "
        "await LedgerRepositoryVerification.assertAllCasesPass() } }\n"
    )
    binary = Path(directory) / "verify"
    subprocess.run([
        "xcrun", "swiftc", "-D", "DEBUG", "-default-isolation", "MainActor", "-parse-as-library",
        "-target", "arm64-apple-ios26.0-macabi", "-sdk", sdk,
        "-F", str(support / "System/Library/Frameworks"), "-I", str(support / "usr/include"),
        *[str(root / "walkcalc-native" / source) for source in sources],
        str(shared), str(runner), "-o", str(binary),
    ], check=True)
    subprocess.run([str(binary)], check=True)
