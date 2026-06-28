# Multi-Caregiver Sharing — Technical Design (Epic 13)

This is the technical design for **Epic 13 — Multi-Caregiver Shared Sync** in
`Newborn-Care-Features.md`. It covers letting a caregiver invite family members so several people, on
their own iCloud accounts, see and edit one shared household of data (contractions, babies, feeds, and
future diaper/pump/growth events).

Status: **Implemented, per-record sharing** (Phases A, A', B, C landed and building green; the original single-`Household` share was replaced by **per-record sharing** — see §3/§4 and `docs/per-record-sharing-migration.md` — because a single shared anchor reliably delivered an empty household to participants; cross-account behavior pending two-device verification). It is the companion implementation spec for the work plan. See the Implementation status section at the end for the as-built notes.

---

## 1. Why this is an architectural shift

The app today uses **pure SwiftData** with `cloudKitDatabase: .automatic` (`AppData.swift`). That gives
each user automatic sync of their own data to their **private** CloudKit database, across that one
person's devices. It does **not** allow two different iCloud accounts to see the same data.

The blocker is concrete: SwiftData's `ModelConfiguration.CloudKitDatabase` only offers `.automatic`,
`.private(_:)`, and `.none` — there is no shared-database option, even on iOS 26. CloudKit's
cross-account sharing primitives (`CKShare`, the shared database scope, invite/accept) are exposed to a
persistence stack **only** through Core Data's `NSPersistentCloudKitContainer` (methods like
`share(_:to:)`, `acceptShareInvitations(from:into:)`, `fetchParticipants…`, `persistUpdatedShare…`).

SwiftData is itself built on `NSPersistentCloudKitContainer`, but it does not surface the sharing API.
So enabling family sharing means moving the data layer from SwiftData to
`NSPersistentCloudKitContainer` directly. This is a one-time, foundational change; once done, the rest
of the app keeps the same shape (see §9).

---

## 2. Data stack

Replace the `AppData` SwiftData singleton with a **`PersistenceController`** that owns a single
`NSPersistentCloudKitContainer`. Key configuration:

- **Two persistent stores** on the one container:
  - a **private** store (`NSPersistentCloudKitContainerOptions` with `databaseScope = .private`) for data
    this user owns;
  - a **shared** store (`databaseScope = .shared`) for data shared *with* this user as a participant.
  `NSPersistentCloudKitContainer` routes objects to the correct store automatically and presents them
  through one `viewContext`.
- **History tracking + remote-change notifications** enabled on both store descriptions
  (`NSPersistentHistoryTrackingKey`, `NSPersistentStoreRemoteChangeNotificationPostOptionKey`) so
  push-driven updates merge in. `viewContext.automaticallyMergesChangesFromParent = true`,
  `viewContext.transactionAuthor` set per device.
- **Local-only fallback** preserved from today's behavior (`AppData.swift` falls back to a local store
  when CloudKit discovery fails): if the container can't load CloudKit stores, fall back to a non-synced
  store so the app still works fully offline.
- **`CKSharingSupported = true`** in `Info.plist` so the system can launch the app from a share link.

The container is a `@MainActor` singleton, `PersistenceController.shared`, mirroring how `AppData.shared`
is used today (including from the in-process Live Activity intent path).

---

## 3. Schema

Recreate the current SwiftData schema as a Core Data managed object model (a `.xcdatamodeld` or a
programmatic `NSManagedObjectModel`), preserving entity and attribute names/types so behavior is
unchanged. CloudKit rules still apply: **no unique constraints**, **every attribute optional or
defaulted**, and **all relationships optional**.

**Existing entities** (tracking `Contraction.swift`, `Baby.swift`, `Feed.swift`):
- `Contraction` — `id`, `startDate`, `endDate?`, `startsNewSession`.
- `Baby` — `id`, `name`, `birthDate`, `isArchived`, `createdAt`, plus the per-baby feed-reminder fields
  (`feedReminderEnabled`, `feedReminderInterval`, `feedAlarmID?`).
- `Feed` — `id`, `babyID`, `timestamp`, `kind`, `volume?`, `note?`.

**Per-record share roots (replaces the single `Household`).** Each shareable thing is its own share
root, so a graph is never shared empty and there is no cross-zone middleman:
- **`Baby` is its own share root.** It gains a to-many `Baby → feeds` (inverse to-one `Feed.baby`,
  **cascade** from the baby). A baby's feeds are its children, so they travel with it when it is shared.
  A Baby has **no parent** (top-level), so each baby can be shared independently.
- **`LaborLog` (new) — per-user share root for contraction data.** `id`, `createdAt`, and a to-many
  `LaborLog → contractions` (inverse to-one `Contraction.laborLog`, **cascade**). Exactly one is created
  on first launch in the private store (`PersistenceController.ensureLaborLog()`); `laborLog` prefers a
  shared-store log so a participant's new contractions attach to the shared graph.
- `Feed` keeps `babyID` (the per-baby `@FetchRequest` predicate uses it) **and** sets the `baby`
  relationship on create — both point at the same baby.
- The old `Household` entity is **removed** entirely.

Why per-record: `NSPersistentCloudKitContainer` shares an **object graph** rooted at one object, but it
does **not** support cross-zone relationships, and sharing an empty/just-created anchor produced an empty
shared zone for the participant (confirmed on two devices). Sharing the **actual records** — a baby with
its feeds, or the labor log with its contractions — is robust and idiomatic, and it is the product win:
granular, privacy-respecting sharing (mom shares her contraction log; a parent shares Baby Emma to grandma
while Baby Noah stays private).

**Attribution fields** (Epic 13.5) on each event entity (`Contraction`, `Feed`, future events):
`loggedByName: String?` and `loggedByID: String?`, stamped on creation from the current iCloud identity
(`CKContainer.fetchUserRecordID`, or the matching `CKShare.Participant`). Used to show "who logged it."

The existing computed helpers stay on the managed-object subclasses: `Baby.ageDescription`,
`Feed.feedKind`/volume accessors, `Contraction.isInProgress` and duration.

---

## 4. Sharing flows

**Invite (owner).** A `CKShareItem` (`Transferable` via `CKShareTransferRepresentation`) wraps any share
root by its `NSManagedObjectID` + a friendly title, so both a Baby and the LaborLog produce one. The
system sheet is presented with SwiftUI **`ShareLink`**. The transfer representation asks `SharingManager`
to create-or-fetch the `CKShare` for that record via `NSPersistentCloudKitContainer.share(_:to:)`. The
system sheet handles sending the link (Messages, Mail, etc.) and participant/permission management. Share
controls live **on the records**: "Share [baby]" in the baby manager, "Share contraction history" in the
labor menu, with a `Family & Caregivers` overview that lists every record's share status and deep-links to
its controls.

**Accept (participant).** SwiftUI apps need UIKit delegates to receive an accepted invitation:
- an `AppDelegate` (`@UIApplicationDelegateAdaptor`) that points new scenes at a custom `SceneDelegate`;
- a `SceneDelegate` implementing `windowScene(_:userDidAcceptCloudKitShareWith:)` that calls
  `container.acceptShareInvitations(from:[metadata], into: sharedStore)`.
After acceptance the shared record — a baby with its feeds, or a labor log with its contractions —
appears in the participant's **shared** store and flows through the same `viewContext` and
`@FetchRequest`s, so the UI needs no special-casing. (`RootView.reconcileActiveBaby()` switches a
participant who adopts a shared baby into newborn mode.)

**Manage / revoke / leave / stop.** Surfaced in each record's `RecordShareView` (keyed by objectID):
- owner can **remove a participant** (via the system share sheet);
- a participant can **leave** the share (`SharingManager.leaveShare(objectID:)`);
- owner can **stop sharing** that record (`SharingManager.stopSharing(objectID:)`, deleting the share); the
  record reverts to private. Note: a direct `CKShare` delete leaves PCK local state stale, so the UI
  reloads and tolerates lag rather than assuming an immediate change.

**Family / Caregivers overview (Epic 13.4).** `FamilyView` lists the contraction history and each baby
with its current share status; tapping a row opens that record's `RecordShareView`, which shows the
`CKShare.participants` roster (owner + caregivers with name/identity, role, and acceptance status) and the
invite/stop/leave controls.

---

## 5. Offline & conflict behavior (Epic 13.3)

`NSPersistentCloudKitContainer` queues local changes while offline and exports them when connectivity
returns; remote changes arrive via push (or a periodic pull) and merge into `viewContext`. Conflicts use
CloudKit's **last-writer-wins** at the record level. For this app's data (append-mostly event logs:
contractions, feeds), that is acceptable — concurrent edits to the *same* record are rare, and divergent
new events from different caregivers simply both persist. No custom merge policy is planned beyond
setting a sensible `NSMergePolicy` (e.g. `.mergeByPropertyObjectTrump`) on background contexts.

---

## 6. Attribution (Epic 13.5)

Every event records who logged it (`loggedByName`/`loggedByID`, §3). On create, the service stamps the
current user's identity. In shared mode the value is resolved to the matching `CKShare.Participant`'s
display name so each device shows a friendly "Logged by …" on contraction/feed rows and the future
timeline. Solo users see their own name (or nothing) — attribution is informational, never required.

---

## 7. CSV import/export framework

A small, extensible framework gives each event type a **symmetric** CSV export and import. It ships with
contractions and feeds now; pumps/diapers slot in when Epics 9/10 land. It is a **general feature**
(any user can export/import), and it is also how existing data is brought across the stack migration —
e.g. a caregiver who has contraction history exports it from the old app and imports it into the
household.

**Framework.** A `CSVRecordType` abstraction (per-type `header`, `filenamePrefix`, `csvRow(...)`,
`parse(rows:)`) plus a shared `CSVImporter` that picks a file (`.fileImporter`), sniffs the header to
choose the matching type, parses, **dedups**, and reports imported/skipped counts. The existing
`CSVExporter` (contractions) is refactored to conform, **keeping its exact current header/format** so
prior exports still round-trip.

**Contractions.** Header (unchanged):
`index,start_iso8601,end_iso8601,duration_seconds,interval_since_prev_start_seconds,duration_mmss,interval_mmss`.
Only `start_iso8601` (→ `startDate`) and `end_iso8601` (empty → in-progress, `endDate == nil`) are
authoritative; index/duration/interval columns are derived and `startsNewSession` is not exported. This
is lossy by design and fine: durations are `end − start` and sessions are re-derived from start-to-start
gaps by `SessionGrouper`. Parse with the same `ISO8601DateFormatter` options the exporter uses
(`.withInternetDateTime, .withFractionalSeconds`). Dedup by `startDate` (idempotent re-import).

**Feeds** (new export + import). Header: `index,timestamp_iso8601,kind,volume_ml,note`. Authoritative:
`timestamp`; plus `kind` (raw string), `volume` (ml), optional `note`. Export is **scoped to the active
baby**; import attaches feeds to the active baby (`AppState.activeBabyID`), setting both `babyID` and the
`baby` relationship. Free-text `note` is CSV-escaped (quote fields containing commas/quotes/newlines).
Dedup by `(babyID, timestamp)`.

**Pumps / diapers.** Add conforming `CSVRecordType`s when those models exist (Epics 9/10). No unbuilt
models are created as part of this design.

All event imports attach new objects to their share root (a feed to its `baby`, a contraction to the
`laborLog`) so imported data participates in sharing.

---

## 8. Migration & rollout

- **Fresh schema.** The app's CloudKit schema is not yet promoted to Production, so there is no
  production data to preserve in place. The migration stands up a fresh Core Data schema rather than an
  in-place SwiftData→Core Data store adoption. Existing real data (e.g. a caregiver's contraction
  history) is carried over via the CSV import (§7), not an automatic store migration.
- **Dev schema init.** Initialize the CloudKit development schema from the new model
  (`initializeCloudKitSchema` during `#if DEBUG` launch), verify in the CloudKit Console.
- **Promotion checklist.** Get the full Epic-13 schema right — `Baby` (with `feeds`), `Feed` (with
  `baby`), `Contraction` (with `laborLog`), `LaborLog`, the `loggedBy*` attribution fields, and
  `cloudkit.share` — **before** promoting Development → Production, because CloudKit schemas are
  additive-only afterward.
- **Two-account verification.** Sharing can only be validated on two physical devices signed into two
  different iCloud accounts (the Simulator does not support CloudKit sharing or Live Activities).

---

## 9. Pattern decision — service layer, not MVVM

The app already centralizes every mutation in `@MainActor` "single source of truth" services
(`ContractionService`, `FeedService`) and reads through SwiftUI bindings. That is effectively a
repository/domain layer and maps onto Core Data + SwiftUI almost 1:1:

| SwiftData today | Core Data target | Role |
|---|---|---|
| `AppData.shared.container` | `PersistenceController.shared` (dual store) | Stack |
| services writing `mainContext` | same services writing `viewContext` | Repository / domain |
| `@Query` in views | `@FetchRequest` in views | Read binding |
| `@Environment(\.modelContext)` | `@Environment(\.managedObjectContext)` | Context access |

**Decision: keep the service-singleton + `@FetchRequest` pattern; do not introduce per-view MVVM
ViewModels.** It is the standard lightweight Core Data/SwiftUI approach, preserves the existing
single-source-of-truth rule, and keeps the migration scoped. The only new collaborators are the
`PersistenceController` (stack), a `SharingManager` (CKShare operations), the CSV framework, and the thin
App/Scene delegates for accepting invitations.

---

## Implementation status (as built)

All phases have landed and the project builds clean; the unit suite (CSV + feed reminder) is green.

**Done:**
- **Phase A — stack.** SwiftData replaced by a programmatic `NSPersistentCloudKitContainer`
  (`PersistenceController`) with a dual private/`.shared` store, history tracking, remote-change merge,
  and an offline local-only fallback. `ensureLaborLog()` creates one LaborLog in the private store and
  `laborLog` prefers a shared-store log so a participant's new contractions attach to the shared graph; a
  launch backfill migrates pre-relationship rows (feed→baby, contraction→laborLog).
- **Phase A' — CSV framework.** `CSV` codec, `CSVImporter` (header-sniffing, idempotent), and symmetric
  contraction + feed export/import.
- **Phase B — sharing capability.** `SharingManager` (objectID-keyed create/fetch share, participants,
  stop/leave), `CKShareItem` (`Transferable` via `CKShareTransferRepresentation`) for any share root,
  `CKSharingSupported`, and the `AppDelegate`/`SceneDelegate` accept flow wired through
  `@UIApplicationDelegateAdaptor`.
- **Phase C — UI + attribution.** Per-record share controls: `RecordShareView` (solo empty state, roster
  with avatars, invite/manage via ShareLink, stop/leave) reached from "Share [baby]" in `BabyManagerView`,
  "Share contraction history" in the labor menu, and a `FamilyView` overview of every record's share
  status. `Feed`/`Contraction` `loggedBy*` fields, a cached `CurrentUserIdentity` warmed at launch (its
  name resolved from any share the user participates in), `CurrentUserIdentity.stamp` applied at all
  event-create sites, and the shared `LoggedByLabel` on contraction/feed rows.
- **Per-record sharing pivot.** The original single-`Household` share (one `CKShare` over all data)
  delivered an empty household to participants because PCK does not support cross-zone relationships and an
  empty/just-created anchor exports an empty zone. Replaced by sharing the **actual records**: each `Baby`
  is its own root (feeds as cascade children), contractions share via the per-user `LaborLog`. The
  `Household` entity was removed. See `docs/per-record-sharing-migration.md`.
- **Participant mode routing (fix).** `RootView.reconcileActiveBaby()` switches a device to newborn
  mode when it adopts its first baby — whether created locally or arrived from a caregiver's shared
  baby — so an accepting participant lands on the nursery dashboard instead of the contraction timer.
  A user who later switches back to labor keeps their choice.

**Pending (cannot be done in the Simulator):**
- **Two-device / two-account verification.** Owner invites via ShareLink; participant accepts the link
  (`windowScene(_:userDidAcceptCloudKitShareWith:)`); confirm the baby, feeds, and contractions appear on
  the participant with attribution, and that participant-logged events flow back to the owner.
- **CloudKit dev-schema push.** `initializeCloudKitSchema` is gated behind the `-InitializeCloudKitSchema`
  launch argument (it is blocking and must not run on normal launches); run it once on an iCloud-signed
  device and verify entities/relationships/`cloudkit.share` in the Console.
- **Development → Production promotion** before any TestFlight/release (additive-only afterward).
