## Network Failure Audit

### Silent Recoverable Loads

- `fetchUser`: bootstrap/auth lookup. Logs the failure and returns no user instead of showing a generic network alert.
- `refreshHome`: background home/group refresh. Logs failed group or summary requests and preserves the current cached home state.
- `loadMoreGroups`: pagination. Logs failure, clears the loading flag through `defer`, and keeps loaded groups visible.
- `refreshGroup`: background group/detail refresh. Logs failed group or record responses and keeps existing group and record state.
- `refreshGroupBalances`: secondary detail load. Logs failure and keeps last known member balances.
- `loadMoreRecords`: pagination. Logs failure, clears loading state through `defer`, and keeps loaded records visible.
- `searchRecords`: secondary search load. Logs failure and keeps local matches or existing search results visible.
- `refreshMemberRecords`: secondary detail load. Logs failure and keeps cached member records.
- `loadMoreMemberRecords`: pagination. Logs failure, clears loading state through `defer`, and keeps loaded member records visible.
- `searchUsers`: secondary member search. Logs transport failure and returns an empty result set.
- `refreshSettlementSuggestion`: secondary detail load. Logs failure and keeps locally computed or cached settlement suggestions.

### Local User Actions

- `joinGroupWithFeedback`: already returns sheet-local feedback; now logs transport failures as local feedback.
- `createGroupWithFeedback`: returns action status and does not write global alert state.
- `archiveGroupWithFeedback`, `unarchiveGroupWithFeedback`, `deleteGroupWithFeedback`, `changeGroupNameWithFeedback`: return action status and preserve server messages when provided.
- `addMembersWithFeedback`: returns action status for invite and temporary-member failures.
- `addRecordWithFeedback`, `editRecordWithFeedback`, `deleteRecordWithFeedback`: return action status and preserve validation/business-rule messages when provided.
- `resolveSingleWithFeedback`, `resolveAllWithFeedback`: return action status for settlement failures.
- Write-action transport failures do not synthesize generic `Add fail`, `Edit fail`, or `Network issues` copy; the initiating sheet/editor remains open so the user can retry or cancel.

### Urgent Alerts

- The global `ContentView` alert is now bound to typed `urgentAlert` only.
- No generic `Network issues` writer targets the urgent alert path. Future urgent uses must set an explicit title and message.
