# Duo UI investigation — 2026-11-16

## Current result
The final implementation uses native SwiftUI Menu/Picker/Toggle, with currency/category subtitles and optically matched filter glyphs (22pt plain, 36pt circle including padding). The custom UIKit menu coordinator and its tests were removed. Group switching keeps the scroll container stable, resets it to the top, and preserves cached records during background refresh. Owner/member avatars and record secondary typography are aligned; wallet summaries reserve two lines. Search across fold remains unresolved and is not claimed fixed.

Debug and Release builds passed; simulator visual checks and refresh lifecycle verification passed. The final build is installed on Duo; automatic launch was blocked by the device lock. The sections below are the chronological investigation record, including approaches that were later replaced.

## Initial implementation (superseded where noted below)
- Filter button uses UIButton.Configuration for both symbol and selection background, refreshed through configurationUpdateHandler. Removes the independently inserted background subview. Existing native UIMenu and multi-selection behavior remain.
- Owner uses native LabeledContent and the same SoftLedgerAvatarStack as Members (28pt caption scaling); removes forced separator override. Owner resolution/fallback is unchanged.
- Record timestamp and participant caption both use caption size and medium weight.
- Group row declares a rounded native context-menu preview shape. No custom positioning.
- Expanded detail uses inline title, avoiding large-title inset expansion on group replacement. New detail scroll starts at top; wallet settlement text reserves at least two lines, while longer text may grow. Currency count still intentionally contributes stack height.

## Search investigation (not fixed)
Search uses native searchable and unconditional DefaultToolbarItem(.search, .bottomBar). Existing RecordToolbarVisibility UIKit helper restores a hidden toolbar outside search. Its causal role is unproven.
Experiment removing the helper and nested NavigationStack passed five repeated expanded search open/close cycles but lost toolbar items on folding. Reverted both experimental changes.
Final navigation reproduced: open search while closed, expand Duo, search UI disappears; selecting another group can reveal the pending search UI. This may involve system fold/search presentation state; no minimal standalone reproduction yet. Do not claim an Apple-confirmed bug or a search fix.

Sources:
- https://developer.apple.com/forums/thread/850163 — similar developer report, feedback FB24957842; proposed geometry-based identity rebuild is not adopted.
- https://developer.apple.com/documentation/swiftui/toolbardefaultitemkind/search — native search item placement.
- https://developer.apple.com/videos/play/tech-talks/111463/ — system menus/previews automatically adapt around reserved regions; movement alone is not proof of a defect.
- https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-27_3-release-notes — checked; no matching search issue listed.

## Initial validation / limits
Simulator Debug arm64/x86_64 build passed. Existing UIKit menu, refresh lifecycle and wallet layout checks passed; git diff --check passed.
Duo 27.1: category Meal + Hotel stayed selected and filter symbol remained visible after dismiss; Owner row visually continuous with Members; left-row long press preview/menu stayed in sidebar; switching the two one-currency fixture groups displayed wallet at top with consistent settled height. Final navigation restored and folded toolbar visible. Search across fold remains unresolved as above.
No claim of exhaustive animation-frame verification, network-loading/multicurrency jump elimination, or physical Duo 27.3 verification. No physical install, commit, push or publication.
Screenshots/build logs: /Users/mehaa/MUCAA/output/walkcalc-bugs-20261116/.

## Follow-up after physical-device recording (23:08)
User confirmed wallet height is stable, but scroll content still shifts and filter icon disappears with category submenu open. Prior visual claim did not verify the unobscured source icon during presentation.

Retained fix: keep GroupView/ScrollView identity across group changes, reset group-local search/sheet/delete/title/scroll state explicitly, key refresh tasks by group ID, and key wallet identity separately. Cached records remain visible during background refresh. Existing concurrency tests now cover cached refresh without loading replacement.

Filter: reverted the previous UIButton.Configuration conversion. Freeze source image/background from menu presentation through dismissal animation; apply final appearance only at the matching dismissal completion. Existing UIMenu multi-selection stays. New regression assertions cover source-image identity, preview ownership during dismissal and completion after rapid reopen.

Experiment with pure SwiftUI Menu/Toggle was rejected: selecting a category returned to the root menu and toolbar display regressed. No such replacement remains.

Checks: simulator build, Release device build, menu lifecycle and refresh tests passed. Recorded fixture group switches show a stable top position in sampled frames. Category All→Drink retains submenu/checkmark; source icon is obscured by menu in this simulator layout, so exact physical iOS27.3 visual disappearance remains to be rechecked. Artifacts: MUCAA/output/walkcalc-followup-20261116.

## Native menu trial — user-approved comparison
User clarified scroll jumping is fixed; the remaining issue is submenu lateral movement exposing the hidden source button. Apple WWDC25/284 describes button-to-menu morphing; a hidden source alone is not an icon-rendering failure. No public fixed-submenu-x API found in SDK 27.1. Photos implementation is unverified.

Standalone Debug NativeMenuProbe and actual group page using native SwiftUI Menu preserve right-edge alignment on Duo27.1. Selection returns to root even in the minimal probe. User explicitly accepted trying this behavior to inspect on Duo. Replaced custom UIViewRepresentable/UIButton/visible-menu update/dismissal handlers with native Menu/Picker/Toggle; removed equatable view wrapper and obsolete coordinator tests. Active-state appearance now uses a system filled filter symbol and menu rows show native checkmarks rather than custom subtitles.

Verified Meal+Drink cumulative selection and visible filter/settings glyphs after dismissal in screenshot; transient AX omission alone must not be reported as visual toolbar disappearance. Debug and Release builds passed. No search or scrolling implementation changes in this trial. Screenshots/logs: MUCAA/output/walkcalc-menu-position-20261116. Physical27.3 appearance still requires user comparison.

## Native menu presentation polish
Restored Currency/Category summaries using the documented SwiftUI Menu label composition (Label plus Text). The active SF Symbol now uses a resizable Image at 32pt, scaling with Dynamic Type; the inactive symbol is 17pt. A Label containing the image caused the native toolbar to substitute its default symbol size, so the outer Menu uses the Image directly with an explicit accessibility label/value. No custom source background or menu positioning was added.

Duo 27.1 simulator verification: active circle visibly enlarged in the shared toolbar capsule; selected CNY and Meal/Drink summaries visible; root and category submenu retain aligned right edges. Debug and Release builds passed. Screenshots/logs: MUCAA/output/walkcalc-menu-polish-20261116.

Physical Duo: code signature verification passed; in-place installation and process launch succeeded on the first attempt for this polish build.

## Inactive filter symbol comparison
User supplied matching Photos/WalkCalc Duo screenshots showing the inactive three-line glyph smaller in WalkCalc. Raised the inactive resizable SF Symbol from 17pt to 24pt, with Dynamic Type scaling, to match the reference toolbar proportions more closely. Active circle remains 32pt. Simulator verified the larger inactive glyph in the shared capsule; Debug and Release builds and diff check passed. Artifacts: MUCAA/output/walkcalc-filter-size-20261116.
Physical Duo installation and launch succeeded after retrying one connection timeout.

## Filter glyph balance
User found the 24pt inactive symbol slightly large and the selected inner glyph smaller. Reduced inactive to22pt and increased the padded circular SF Symbol to36pt. Simulator screenshots measure the longest inner line at65px in both states (previously70px inactive versus58px active). Uses native symbols and existing Menu; no custom background. Debug/Release builds and visual checks passed. Artifacts: MUCAA/output/walkcalc-filter-balance-20261116.
Physical Duo installation succeeded. Automatic launch was denied because the device was locked; user can unlock and open the installed build.
