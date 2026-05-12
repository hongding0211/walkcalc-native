# WalkCalc Ledger Client Backend Gaps

Date: 2026-05-12

This file records client-facing backend capabilities that cannot be fully preserved with the current backend contract without changing backend behavior.

## Current Status

No current backend-limited client gaps are known after the latest backend update.

Resolved during this migration:

- `GET /walkcalc/groups/my` now returns `participantCount` and a bounded `participantPreview`; the client uses these fields for home list member count and avatar preview without issuing per-group detail requests.
- `walkcalc.settlementLimitExceeded` now returns structured error data with `limit` and `nonZeroParticipantCount`; the client preserves the existing notice flow and includes the backend-provided counts in the message.
- `POST /walkcalc/records/update` now succeeds for the documented update body and preserves projection consistency through update/delete flows.
- Duplicate expense participants now return a structured business failure instead of HTTP 500.
