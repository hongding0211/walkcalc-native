## Why

WalkCalc now has a unified ledger repository boundary, but production local ledger access is still represented by an in-memory source used for verification. App Review requires users to access account-independent ledger features without registration or login, and those features must survive app relaunches. The next model-layer step is to add a persistent local backend that can satisfy the same source-agnostic ledger operations as the existing remote backend wherever account identity is not inherently required.

SwiftData is a good fit for this step because the app already targets modern iOS versions, the required data graph is local to the device, and the repository contract can keep SwiftData details out of SwiftUI views and panels.

## What Changes

- Add a production `SwiftDataLedgerDataSource` behind the existing `LedgerDataSource` contract.
- Add SwiftData model objects for local groups, participants, records, and source metadata/mapping fields needed for future upload.
- Persist local ledger groups, temporary members, expense records, settlement records, archive state, and modification timestamps across app launches.
- Implement local parity for source-agnostic backend behavior: home loading, group pagination/search, group detail, record pagination/search, member records, balances, settlement suggestions, group/member/record mutations, archive/unarchive/delete, rename, and resolve debts.
- Preserve explicit account-required outcomes for operations that cannot be local-only: joining shared remote groups, searching registered users, and inviting real users.
- Keep this change model/data-layer only. No startup route, login UI, home UI, sync UI, or local-to-remote upload behavior is changed here.

## Capabilities

### New Capabilities

- `swiftdata-local-ledger-source`: Defines the persistent local ledger backend and its expected parity/differences against the existing remote ledger source.

### Modified Capabilities

- None. Existing remote-backed collection behavior and current UI routing remain unchanged until a later change wires the local source into launch/home behavior.

## Impact

- Affected native code: `walkcalc-native/Core/Ledger/LedgerDataLayer.swift`, new SwiftData ledger model/source files under `walkcalc-native/Core/Ledger/`, `walkcalc-native/App/WalkcalcStore.swift` only if repository construction needs local-source injection, and debug verification under `walkcalc-native/Debug/`.
- No backend API changes.
- No UI changes.
- No local-to-remote merge/upload in this change.
- Testing impact: add SwiftData in-memory container verification and persistent container smoke verification for CRUD, pagination/search, balance recomputation, settlement generation, account-required outcomes, and relaunch persistence.
