# Visual Style Direction

## Status

Visual direction is accepted as the baseline for the next UI iteration.
UX is not frozen yet. Some interaction and layout rhythms from the earlier Soft Ledger / B direction may still be reintroduced under this visual system.

## Direction Name

Soft Utility Ledger

This direction combines the calm, warm, low-pressure feeling of the earlier Soft Ledger exploration with the clearer information density and utility-first readability of the neutral direction.

The app should feel like a personal shared-expense ledger that is pleasant to return to, not like a finance dashboard, marketing page, or nostalgic paper notebook.

## Principles

- Warm, but not yellow.
- Clean, but not cold.
- Ledger-like, but not retro or skeuomorphic.
- iOS-native first, with restrained Liquid Glass accents.
- Information clarity before decoration.
- Chinese and English mixed text must be treated as a normal case, not an edge case.
- Money, balance direction, and settlement state must be scannable at a glance.

## Current Prototype

The current visual prototype lives in:

`walkcalc-native/Features/DesignPlayground/StylePlayground.swift`

The active previews are:

- `E - Soft Utility Ledger / 中英混排`
- `E - Soft Utility Group / 中英混排`

Older B and D code may remain in the playground as reference, but they are not the accepted visual baseline.

## Color System

### Light Mode

Light mode uses a shallow grayscale app canvas so future accent themes have a neutral base while cards and rows can remain crisp white. Supporting hierarchy follows the original canvas-to-card relationship, but without warm paper tint.

| Token | Hex | Usage |
| --- | --- | --- |
| `canvas` | `#F7F7F7` | App background |
| `paper` | `#FFFFFF` | Card and row surfaces |
| `formPaper` | `#FFFFFF` | Form and list row surfaces |
| `ink` | `#1C1C1C` | Primary text |
| `secondaryInk` | `#666666` | Secondary labels |
| `mutedInk` | `#8A8A8A` | Metadata and less important text |
| `rule` | `#D9D9D9` | Borders and separators |
| `positive` | `#167454` | Receivable / positive balances |
| `negative` | `#AC2F24` | Payable / negative balances |
| `accent` | `#B15525` | Primary accent and selected action |
| `accentSoft` | `#EDCBA4` | Low-emphasis accent backgrounds |

### Dark Mode

Dark mode uses a pure black app canvas. Supporting hierarchy comes from grayscale near-black surfaces, grayscale text, and restrained accent usage.

| Token | Hex | Usage |
| --- | --- | --- |
| `canvas` | `#000000` | App background |
| `paper` | `#141414` | Card and row surfaces |
| `formPaper` | `#1C1C1C` | Form and list row surfaces |
| `ink` | `#F2F2F2` | Primary text |
| `secondaryInk` | `#C7C7C7` | Secondary labels |
| `mutedInk` | `#8E8E8E` | Metadata and less important text |
| `rule` | `#3A3A3A` | Borders and separators |
| `positive` | `#77C99E` | Receivable / positive balances |
| `negative` | `#F07C6C` | Payable / negative balances |
| `accent` | `#E49B63` | Primary accent and selected action |
| `accentSoft` | `#38322F` | Low-emphasis accent backgrounds |

## Typography

Use system sans-serif typography. Do not use serif typefaces for this direction.

- Prefer system / rounded design for major headings and large money figures.
- Use monospaced digits for amounts, balances, counts, and times.
- Keep text weights moderate. Avoid heavy display weights that make the app feel like a dashboard.
- Chinese and English should be tested together in the same preview.
- Mixed labels such as `群组 Groups`, `债务详情 Debt detail`, and `酒店 Hotel` are intentional in the prototype to test fallback, spacing, truncation, and scan rhythm.

## Surface Language

Cards and rows should feel quiet and useful.

- Use subtle rounded rectangles, generally around 10-14 pt in the current prototype.
- Use borders and separators to support scanning.
- Avoid overly large floating cards or nested-card layouts.
- Keep repeated list rows compact enough for real daily use.
- Use soft shadows sparingly; surface hierarchy should mostly come from color, border, material, and spacing.

## Liquid Glass

Liquid Glass is a supporting detail, not the whole style.

Use it for:

- Summary cards.
- Small icon buttons.
- Key action buttons.
- Floating add action.

Shape rules:

- Small icon-only glass buttons should be circular.
- Text action buttons should be capsule-shaped.
- Avoid small glass rounded rectangles for buttons; they feel too static and do not match the rounded, floating Liquid Glass control language.
- Larger content surfaces can stay rounded rectangles, because they act as information containers rather than standalone controls.

Avoid:

- Applying glass to every row.
- Making the app feel translucent for its own sake.
- Letting glass reduce contrast or make Chinese text harder to read.

## Icons And Symbols

Use SF Symbols for functional icons.

- Icons should clarify action or category.
- Avoid decorative icon density.
- Category color may appear in small icon containers, but the list should not become colorful confetti.

## UX Notes

- More relaxed emotional rhythm on the home screen.
- Friendlier summary presentation.
- Softer group card pacing.
- Less purely table-like debt expression where readability allows.
- Clearer information density.
- Better scan order.
- Stronger amount/status hierarchy.
- More direct action placement.

## Do Not Do

- Do not return to a yellow/brown dark-mode background.
- Do not make dark mode cold blue-gray.
- Do not reintroduce warm neutral backgrounds, surfaces, text, or separators into production UI.
- Do not introduce serif typography.
- Do not split Chinese and English into separate design assumptions only.
- Do not overuse Liquid Glass.
- Do not make the app feel like a generic finance dashboard.
- Do not let warm accent color become the dominant background color.
