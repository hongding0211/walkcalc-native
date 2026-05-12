# Simulator E2E Test Report

Date: 2026-05-12  
Tester: Codex, user-perspective heuristic run  
Scope: native iOS app running in Simulator against the already-running dev frontend/backend stack

## Environment

- App: Walking Calculator, bundle `ltd.hong97.walkingcalc-native`
- Project: `walkcalc-native.xcodeproj`
- Scheme: `walkcalc-native`
- Build configuration: Debug
- Simulator: iPhone 17 Pro, iOS 26.4
- Simulator UDID: `85BA4D9D-0915-463B-82A7-D81B49CC72D1`
- Test account observed in app: `mehaaa`
- Start state: logged in, one active group `142412412`
- Build/run result: passed via XcodeBuildMCP `build_run_sim`
- Build log: `/Users/hong/Library/Developer/XcodeBuildMCP/workspaces/walkcalc-native-fdf4ad3d74b6/logs/build_run_sim_2026-05-12T09-40-34-133Z_pid24585_2b4ada4f.log`
- Runtime log: `/Users/hong/Library/Developer/XcodeBuildMCP/workspaces/walkcalc-native-fdf4ad3d74b6/logs/ltd.hong97.walkingcalc-native_2026-05-12T09-40-38-304Z_helperpid25182_ownerpid24585_88ae3875.log`

## Executive Summary

The app was usable end to end for the primary ledger flows tested from the Simulator UI: home bootstrap, group navigation, empty states, expense create/edit/delete, search, balances, member detail, group creation with a temporary member, group deletion, archived-group empty state, settings, and logout confirmation.

No app crash or fatal runtime error was observed during the run. The only runtime text matched by an error/crash scan was an Apple simulator WebCore/WebKit accessibility duplicate-class warning, not an app failure.

One behavioral issue was observed: submitting an invalid join code (`BAD1`) closed the join dialog and returned to the groups list without visible error feedback or a newly joined group. This should be clarified as either expected silent failure or fixed to keep the dialog open with a visible error.

## Evidence Summary

| Gate | Evidence | Result |
| --- | --- | --- |
| Build and launch | `build_run_sim` succeeded in 5266 ms | Pass |
| Home bootstrap | Stored session opened directly to `Groups`, total balance `¥0.00`, `Across 1 group` | Pass |
| Runtime stability | Runtime and oslog scan found no app fatal/crash/error records | Pass |
| Data cleanup | Created E2E expense and E2E group were deleted; home returned to one active group | Pass |

## Prompt Coverage Audit

| Requirement | Concrete evidence in this report | Status |
| --- | --- | --- |
| Complete E2E test of the current app | Build/run gate plus tested flows across home, group detail, expense editor, search, balances, member detail, create/delete group, archived groups, settings, and logout confirmation | Covered |
| Cover boundary content | Boundary matrix covers empty, malformed, negative, over-precision, valid minimum, create/join empty states, temp member validation, no-result search, delete/archive/logout confirmations | Covered for reachable UI and current dev data |
| Use user perspective rather than source-code context | Simulator UI and accessibility interactions were the primary evidence; source code was not used to drive assertions | Covered |
| Use Simulator | Run executed on iPhone 17 Pro iOS 26.4 simulator `85BA4D9D-0915-463B-82A7-D81B49CC72D1` | Covered |
| Free to create/delete dev data | Created and deleted one expense and one E2E group with a temporary member | Covered |
| Produce report in the project | This file: `docs/simulator-e2e-test-report-2026-05-12.md` | Covered |

## Tested Flows

| Area | User path | Result |
| --- | --- | --- |
| Home | Launch app with stored token, verify total balance card, group count, active group row, member count, row navigation | Pass |
| Group detail | Open `142412412`, verify balance card, balance preview rows, expenses list, empty/filled toolbar controls | Pass |
| Add expense | Open new expense, verify default `0.00` cannot save, select payer/split/category, create `0.01`, edit to `1.23`, verify row update | Pass |
| Delete expense | Open created expense, verify delete confirmation cancel keeps record, confirm delete removes record and updates member detail count | Pass |
| Search records | Search `Meal`, verify matching records; clear search; search `zzzz-no-result-20260512`, verify `No matching records` | Pass |
| Balances | Open all balances sheet, verify rows for all participants and zero balances | Pass |
| Member detail | Open Hong member detail, verify balance, record count, filtered records, and row navigation to editor | Pass |
| Create group | Open plus menu, verify create/join entries; create `E2E Group 20260512`; add temp member `Temp E2E`; verify group appears with two members | Pass |
| Group settings | Open group settings, verify name, group ID `YH7Y`, members, archive/delete controls | Pass |
| Group delete | Verify delete group cancel keeps group; confirm delete removes E2E group and home returns to one group | Pass |
| Archived groups | Open archived groups from home menu, verify empty state `No archived groups` | Pass |
| Settings | Open settings, verify account card, edit profile entry, archived groups entry, logout entry | Pass |
| Logout confirmation | Tap log out, verify `Confirm logout?`; cancel keeps the user logged in | Pass |

## Boundary Coverage

| Boundary | Input / action | Observed behavior | Result |
| --- | --- | --- | --- |
| Empty expense amount | New expense default `0.00` | Save button disabled | Pass |
| Non-numeric amount | `abc` | Save button disabled | Pass |
| Negative amount | `-1` | Save button disabled | Pass |
| More than two decimals | `1.234` | Save button disabled | Pass |
| Minimum positive amount | `0.01` | Save enabled; record created | Pass |
| Decimal amount edit | Update created expense to `1.23` | Record row updated to `¥1.23` | Pass |
| Empty temp member name | Add temporary member with blank name | Add button disabled | Pass |
| Valid temp member name | `Temp E2E` | Member added to create-group preview | Pass |
| Empty create group name | Create group sheet with blank name | Save button disabled | Pass |
| Valid create group name | `E2E Group 20260512` | Group created and visible on home | Pass |
| Empty join code | Join group dialog with blank code | Join button disabled | Pass |
| Invalid join code | `BAD1` | Dialog closed, no group added, no visible error | Fail / needs product decision |
| Search no-result | `zzzz-no-result-20260512` | `No matching records` visible | Pass |
| Delete confirmation cancel | Expense and group delete cancel buttons | Target item remains visible | Pass |
| Delete confirmation confirm | Created expense and group | Target item removed | Pass |
| Archive confirmation cancel | Created group archive alert | Group remains active | Pass |
| Archived empty state | Open archived groups | Empty state shown | Pass |
| Logout cancel | Logout confirmation cancel | User remains logged in | Pass |

## Notes And Limitations

- The run intentionally used the Simulator UI and accessibility tree rather than source-code inspection as the main context.
- Full SSO login from a logged-out state was not completed, because the run preserved the current dev session after validating logout confirmation cancel.
- Large pagination, deep links, offline/network failure, settlement-limit errors, and resolve-all settlement were not exercised in this pass because the reachable dev data only had small settled groups and two-member examples.
- XcodeBuildMCP coordinate taps did not reliably trigger the circular save button in sheet headers; direct Simulator window interaction did. This was treated as a test tooling limitation, not an app defect.

## Recommended Follow-Ups

1. Fix or define the invalid join-code behavior so the dialog either shows a visible error or documents silent no-op behavior.
2. Add a seedable dev fixture with many records, unsettled balances, three formal users, temporary users, and archived groups so pagination, settlement, archive rejection, and resolve-all can be verified from the UI.
3. Promote the high-value paths above into repeatable XCTest UI tests once the fixture setup is stable.
