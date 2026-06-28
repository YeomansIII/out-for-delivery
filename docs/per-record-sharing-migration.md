# Per-Record Sharing Migration (replaces the single-Household share)

> Apply-ready changeset for a fresh implementing agent. Repo:
> `/Users/jason/dev/Out for Delivery`. Builds via the `xcode-tools` MCP `BuildProject`.
> Companion spec: `docs/Multi-Caregiver-Sharing-Design.md` (update its §3 model + §4 flows
> after applying). Style mirrors `docs/Phase-A-Migration-Changeset.md`.

## Why this change

The current design shares **all** data via one `Household` anchor as a single `CKShare`. In practice
the invited participant reliably receives an **empty** household (`babies=0`) even from a clean slate
(CloudKit env reset + app delete on both devices). Root causes, confirmed on two physical devices via the
`sharing` os_log channel:
- `NSPersistentCloudKitContainer` does **not** support cross-zone relationships. A Baby/Feed created in
  the default zone, then related to a Household that later moved to a shared zone, never syncs.
- Sharing an anchor that is empty (or sharing immediately after creating data, before export) produces an
  empty shared zone the participant imports.

**Pivot:** share the **actual records**. Each `Baby` is its own share root (its feeds are children, so
they travel with it). Contractions share via a small per-user `LaborLog` anchor. Drop the universal
`Household` share. Benefits: robust (no empty middleman, no cross-zone trap), idiomatic CloudKit (share a
record hierarchy), and the product win the user asked for — granular, privacy-respecting sharing (mom
shares her contraction log; dad shares Baby Emma to grandma while Baby Noah stays private).

Keep these hard-won notes in mind (see project memory): CloudKit cross-zone-relationship limit; direct
`CKShare` deletion leaves PCK local state stale (so "stop sharing" must reload/tolerate lag);
`initializeCloudKitSchema` is blocking and gated behind `-InitializeCloudKitSchema`.

## Target data model (programmatic, in `PersistenceController.makeModel`)

CloudKit rules unchanged: no unique constraints; every attribute optional or defaulted; every
relationship optional **with an inverse**. Share roots have **no parent**.

- **Baby** — share root for one baby's data.
  - Keep: `id, name, birthDate, isArchived, createdAt, feedReminderEnabled, feedReminderInterval, feedAlarmID`.
  - **Add** `feeds` (to-many → Feed, inverse `Feed.baby`, **cascade** delete).
  - **Remove** `household`.
- **Feed** — child of Baby.
  - Keep: `id, timestamp, kind, volumeNumber, leftMinutesNumber, rightMinutesNumber, note, loggedByID, loggedByName`.
  - **Add** `baby` (to-one → Baby, inverse `Baby.feeds`, **nullify** delete).
  - **Remove** `household`.
  - **`babyID`**: keep it (the per-baby `@FetchRequest` predicate in `FeedSectionView`/`FeedService.feeds(for:)`
    uses it). Set BOTH `babyID` and the `baby` relationship on create. (Alternative: migrate those fetches
    to the relationship and drop `babyID` — more churn; only do if the implementer prefers one source of truth.)
- **Contraction** — child of LaborLog.
  - Keep: `id, startDate, endDate, startsNewSession, loggedByID, loggedByName`.
  - **Add** `laborLog` (to-one → LaborLog, inverse `LaborLog.contractions`, **nullify** delete).
  - **Remove** `household`.
- **LaborLog** (NEW — rename/repurpose the existing `Household`) — per-user share root for contraction data.
  - `id, createdAt`; `contractions` (to-many → Contraction, inverse `Contraction.laborLog`, **cascade**).
  - Exactly one per user, created on first launch (mirror the old `ensureHousehold`).
- **Remove `Household`** entirely (rename the file/class to `LaborLog`, drop its `babies`/`feeds` rels).
  Babies are now top-level (no parent) so they can each be shared independently.

## Stack / anchors — `PersistenceController.swift`

- Dual private/`.shared` store, store-handle capture, fallback, query-generation guard, DEBUG schema-init
  gate: **unchanged**.
- Replace `ensureHousehold`/`preferredHousehold`/`backfillHouseholdRelationships` with:
  - `ensureLaborLog() -> LaborLog` (one per user; create in **private** store via `viewContext.assign(_,to:privateStore)`;
    `preferredLaborLog()` prefers a shared-store LaborLog so a participant's new contractions attach to the
    shared graph — same pattern as the old household).
  - `var laborLog: LaborLog { ensureLaborLog() }`.
  - **Backfill at launch** (migrate existing local rows to the new relationships):
    - Feeds with `baby == nil`: fetch `Baby` by `babyID`, set `feed.baby`.
    - Contractions with `laborLog == nil`: set `contraction.laborLog = ensureLaborLog()` (only for a
      LaborLog we own — private store — same guard as before).
    - Babies need no anchor; leftover `Household` rows can be deleted.
  - Keep the `Logger.sharing` "Stack ready" diagnostic; update fields to log `contractions count` and
    `laborLogInSharedStore` (babies no longer hang off an anchor).

## Services — anchor assignment

- `ContractionService` `start()` / `importContractions`: set `new.laborLog = PersistenceController.shared.laborLog`
  (instead of `household`). Keep `CurrentUserIdentity.shared.stamp(new)`. Hoist `laborLog` out of the import loop.
- `FeedService` `addFeed` / `importFeeds`: set `feed.baby = <the Baby>` (resolve via `FeedService.baby(with: babyID)`),
  and keep setting `babyID` if retained. Keep `stamp(feed)`. Resolve the Baby once per import, not per row.
- `BabyFormView.save()`: drop `newBaby.household = …` (Baby is top-level now).

## Sharing layer — generalize from "household" to "any share root"

- **`SharingManager`** — make the API objectID-based so it serves both Baby and LaborLog roots:
  - `existingShare(forObjectID:) throws -> CKShare?` (`fetchShares(matching:[objectID])`).
  - `isShared(_ objectID:)`, `participants(forObjectID:)`, `isOwner(ofObjectID:)`.
  - `makeOrFetchShare(forObjectID:, title:) async throws -> CKShare` (shares `[object]`; sets
    `CKShare.SystemFieldKey.title`). Bridge `share(_:to:)` via its completion handler (no managed object
    across an async boundary — keep current pattern).
  - `stopSharing(objectID:)` / `leaveShare(objectID:)` (owner deletes from private DB; participant from
    shared DB) — same as today, keyed by objectID. Keep the "local state lags" caveat in a comment.
  - Keep `cloudKitContainer` static; keep the `os_log` traces (update messages to name the record).
- **`HouseholdShareItem` → `CKShareItem`** (rename file): `struct CKShareItem: Transferable { let objectID:
  NSManagedObjectID; let title: String; let existingShare: CKShare? }`, `CKShareTransferRepresentation`
  branching `.existing` vs `.prepareShare { try await SharingManager.shared.makeOrFetchShare(forObjectID:
  objectID, title: title) }`. Both Baby and LaborLog produce a `CKShareItem`.
- **Accept flow** (`AppDelegate`/`SceneDelegate`, `CKSharingSupported`, `@UIApplicationDelegateAdaptor`):
  **unchanged** — `acceptShareInvitations(from:[metadata], into: sharedStore)` imports whichever root (Baby
  or LaborLog) into the shared store; `@FetchRequest`s span both stores so shared babies/contractions just
  appear. Keep the post-accept `ContractionService.refresh()` + `CurrentUserIdentity.refreshName()` and add
  a baby-fetch nudge if needed.
- **Attribution / `CurrentUserIdentity`**: unchanged.

## UI — move share controls to the records

Drop the single household-level `FamilyView` share. Replace with per-record controls (content-layer Lists;
Liquid Glass only on the one prominent invite CTA; no em-dashes):

- **Per-baby sharing.** In `BabyManagerView` (and/or a baby row in `NewbornModeView`), add **"Share [name]"**
  → `ShareLink(item: CKShareItem(objectID: baby.objectID, title: baby.name, existingShare: …))`, plus a
  roster of who that baby is shared with and **Stop sharing / Leave** (reuse the `FamilyView` roster +
  `CaregiverRowView` + avatar/haptic patterns, scoped to a baby's share). A participant who accepts a baby
  lands on the nursery dashboard automatically (the `RootView.reconcileActiveBaby` mode-switch fix already
  added covers "adopted a baby from a share").
- **Contraction sharing.** In `ContentView` (labor) menu, add **"Share contraction history"** →
  `ShareLink(item: CKShareItem(objectID: laborLog.objectID, title: "Contractions", existingShare: …))` +
  manage/stop.
- **Family/Caregivers screen.** Either retire it or repurpose it into a lightweight overview listing each
  baby's share status + the contraction-log share status, each row deep-linking to that record's share
  controls. Recommendation: per-record controls are primary; the overview is optional polish.
- `AppState.Sheet` + `RootView` sheet wiring: replace `.family` with the per-record share sheets (e.g.
  `.shareBaby(UUID)` / `.shareContractions`), or present share UI inline from the entity screens.

## Migration & rollout

- CloudKit Development schema was **reset**, so the model can change freely server-side. After applying,
  run once on an iCloud-signed device with the `-InitializeCloudKitSchema` launch arg and verify in the
  CloudKit Console: `Baby` (with `feeds`), `Feed` (with `baby`), `Contraction` (with `laborLog`),
  `LaborLog`, the `loggedBy*` fields, and `cloudkit.share`.
- Local backfill (above) migrates existing on-device rows; leftover `Household` rows are deleted.
- **Timing:** prefer sharing a Baby/LaborLog after its records have exported (PCK generally handles
  newly-related children, but sharing the *actual* record — not an empty anchor — removes the failure mode
  we hit). Surface any `share(_:to:)` error in the `sharing` log.
- Promote Development → Production only once the full model + attribution exist (additive-only after).

## Files to change

- **Model/stack:** `PersistenceController.swift`; `Feed.swift`, `Baby.swift`, `Contraction.swift`;
  `Household.swift` → `LaborLog.swift`.
- **Services:** `ContractionService.swift`, `FeedService.swift`, `BabyFormView.swift`.
- **Sharing:** `SharingManager.swift`; `HouseholdShareItem.swift` → `CKShareItem.swift`;
  `CurrentUserIdentity.swift` (only if anchor lookups referenced).
- **UI:** `FamilyView.swift` (rework/retire), `BabyManagerView.swift`, `NewbornModeView.swift`,
  `ContentView.swift`, `ModeMenuButtons.swift`, `RootView.swift`, `AppMode.swift`.
- **Unchanged:** `AppDelegate.swift`, `SceneDelegate.swift`, `Info.plist` (`CKSharingSupported`),
  `Logging.swift`, `LoggedByLabel.swift`, the CSV framework.
- **Docs:** update `docs/Multi-Caregiver-Sharing-Design.md` §3/§4 to the per-record model.

## Verification

1. `BuildProject` green after each coherent step.
2. `RunSomeTests` — CSV + `FeedReminderTests` still pass (if `babyID` is retained, feed fetches are
   unchanged; if migrated to the relationship, update any affected fetch and re-run).
3. One-off `RunCodeSnippet`/log check: a Feed has a non-nil `baby`; a Contraction has a non-nil `laborLog`;
   no `Household` rows remain.
4. Two devices / two iCloud accounts (Simulator can't): owner creates Baby → **Share [baby]** → participant
   accepts → baby + feeds appear, participant lands on the nursery; participant logs a feed → owner sees it
   with "Logged by". Separately: mom **Shares contraction history** → partner accepts → contractions appear.
5. Stop sharing / Leave per record; re-share; confirm via the `sharing` log.

## Open decisions for the implementer

- Keep `Feed.babyID` FK alongside the new `baby` relationship (less churn) vs migrate fully to the
  relationship (one source of truth). Recommended: keep `babyID`, set both on create.
- `LaborLog` as a rename of `Household` (recommended) vs a brand-new entity.
- Retire `FamilyView` vs repurpose it as a per-record sharing overview.
