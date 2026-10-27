## Context

GroupView uses a native large navigation title and nested lazy stacks. GroupExpensesSection caches localized date/year sections. Reading GroupView.records performs filtering, so scroll state must not invalidate GroupView's body continuously. Member detail reuses GroupExpensesSection and must retain its own navigation title.

## Goals / Non-Goals

**Goals:** Follow the date section at the viewport top, restore the group name above expenses, and isolate scroll-driven title updates from ledger computations.

**Non-Goals:** Change grouping, card layout, backend APIs, or member-detail titles; replace native navigation collapse; implement date jumping.

## Decisions

- Each realized date section transforms its geometry directly into a Boolean: whether it covers the line below the native navigation bar. Include the 16-point inter-section gap with the preceding section. Long sections remain active after their headings leave the viewport.
- The scroll container reports only its top content inset, which accounts for native large-title collapse. Continuous content offsets and per-record geometry are never published. This display-only feature does not install a scroll-position binding or issue scroll commands.
- A view-owned Observation model carries the active date and inset. Small modifiers observe these properties; GroupView passes the reference without reading them. The shared store is not involved. Coalesce adjacent sections' enter/leave callbacks on the next main queue turn so callback order cannot briefly replace a date with the group name.
- Use stable date-based section IDs and the existing section title formatter, including year groups. Refresh the title's clock when the calendar day changes.
- Intersect active candidates with available dates when records change, remove candidates when sections disappear, and clear empty-content state. Do not reset active geometry merely because a refresh task starts: unchanged geometry might not emit another Boolean transition.
- Include a data-layout revision with each section's Boolean. Replacing or restoring dates re-reports an unchanged Boolean, and late callbacks from the previous layout cannot overwrite the current title. The revision changes only with section membership or an explicit empty reset, never with scroll offsets.

## Risks / Trade-offs

- Native ID-based tracking also participates in position retention and requires target-layout registration → use section boundary observation so display logic does not control scrolling.
- Nested lazy stacks refine estimated heights when realizing distant sections → the automated fixture aligns a target again after layout before checking its identity.
- Native navigation preferences can cause layout work even with isolated state → compare body evaluation diagnostics with position changes and record the limits of simulator verification.
- Simulator smoothness is not device performance evidence → leave physical-device profiling explicitly unverified.
