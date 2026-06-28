# Phase A Migration Changeset — SwiftData → NSPersistentCloudKitContainer

> Apply-ready, behavior-preserving stack swap. No sharing yet (that is Phase B/C).
> This document is the mechanical checklist + concrete code for the migration
> described in `Multi-Caregiver-Sharing-Design.md`. It exists so the swap can land
> in **one atomic pass** — the change cannot be done piecemeal, because both
> `ContractionService` and `FeedService` share `AppData.shared.container`, so any
> partial conversion leaves the build red.

## Why atomic / sequencing note

`AppData.shared.container` (a SwiftData `ModelContainer`) is consumed by:

| Consumer | Today | After |
|---|---|---|
| `Out_for_DeliveryApp` | `.modelContainer(AppData.shared.container)` | `.environment(\.managedObjectContext, PersistenceController.shared.viewContext)` |
| `ContractionService` | `container.mainContext` | `PersistenceController.shared.viewContext` |
| `FeedService` | `container.mainContext` | `PersistenceController.shared.viewContext` |
| `@Query` views (6) | `@Query` | `@FetchRequest` |
| `@Environment(\.modelContext)` (1) | `BabyFormView` | `@Environment(\.managedObjectContext)` |

There is no subset of these that compiles independently. Land them together.
Because the **feed files** (`Feed.swift`, `FeedService.swift`, `FeedSectionView.swift`)
are being actively reshaped by the newborn-feeding work, apply this changeset only
once those files are settled, then re-read them before transcribing (the `Feed`
attribute set below must match the latest model — it currently includes
`leftMinutes`/`rightMinutes`).

## Model decision: `.xcdatamodeld` (primary) vs programmatic model

`NSPersistentCloudKitContainer` is happiest with an `.xcdatamodeld` (the model
editor, the "Used with CloudKit" container checkbox, and `initializeCloudKitSchema`
all assume one). **Create `OutForDelivery.xcdatamodeld` in Xcode** (File ▸ New ▸
Data Model), define the entities per the spec table below, set each entity's
**Codegen = Manual/None**, and add the hand-written `NSManagedObject` subclasses in
this doc (kept in source control, explicit, and CloudKit-safe). A fully
programmatic `NSManagedObjectModel` is a viable fallback if we want to avoid the
bundle, but the `.xcdatamodeld` path is the recommended, Apple-idiomatic one and is
required tooling for the Phase B CloudKit schema push.

### CloudKit-safety rules (unchanged from the SwiftData era)

- No unique constraints.
- Every attribute **optional in the Core Data sense** (checkbox) — even where the
  Swift type is non-optional with a default. (Core Data "optional" ≠ Swift optional.)
- Every relationship optional, and **every relationship must have an inverse**.
- Additive-only once the schema is promoted to Production.
- Delete rule for Household → events: **Cascade** (deleting the household removes its
  events). Events → Household: **Nullify**.

## Entity model spec

> Anchor everything to a single `Household` root so Phase B can share the whole
> object graph as one `CKShare`. In Phase A the Household is created on first launch
> and every inserted object is related to it; queries are unchanged.

### Household (NEW — root anchor)

| Attribute | Type | Optional | Default | Notes |
|---|---|---|---|---|
| `id` | UUID | yes | — | app-enforced uniqueness |
| `createdAt` | Date | yes | — | |

| Relationship | Destination | Type | Inverse | Delete rule |
|---|---|---|---|---|
| `contractions` | Contraction | to-many | `household` | Cascade |
| `babies` | Baby | to-many | `household` | Cascade |
| `feeds` | Feed | to-many | `household` | Cascade |

### Contraction

| Attribute | Type | Optional | Default | Notes |
|---|---|---|---|---|
| `id` | UUID | yes | — | |
| `startDate` | Date | yes | — | |
| `endDate` | Date | yes | — | nil = in progress |
| `startsNewSession` | Boolean | yes | NO | |
| `loggedByID` | String | yes | — | **attribution (Phase B populates; nil in A)** |
| `loggedByName` | String | yes | — | attribution |

Relationship: `household` → Household (to-one, inverse `contractions`, Nullify).

### Baby

| Attribute | Type | Optional | Default | Notes |
|---|---|---|---|---|
| `id` | UUID | yes | — | |
| `name` | String | yes | "" | |
| `birthDate` | Date | yes | — | |
| `isArchived` | Boolean | yes | NO | |
| `createdAt` | Date | yes | — | |
| `feedReminderEnabled` | Boolean | yes | NO | |
| `feedReminderInterval` | Double | yes | 10800 | 3h |
| `feedAlarmID` | UUID | yes | — | |

Relationship: `household` → Household (to-one, inverse `babies`, Nullify).

### Feed (re-verify against latest `Feed.swift` before applying)

| Attribute | Type | Optional | Default | Notes |
|---|---|---|---|---|
| `id` | UUID | yes | — | |
| `babyID` | UUID | yes | — | loose FK to Baby (kept) |
| `timestamp` | Date | yes | — | |
| `kind` | String | yes | "unspecified" | raw `FeedKind` |
| `volume` | Double | yes | — | ml |
| `leftMinutes` | Integer 64 | yes | — | nursing |
| `rightMinutes` | Integer 64 | yes | — | nursing |
| `note` | String | yes | — | |

Relationship: `household` → Household (to-one, inverse `feeds`, Nullify).

> Keep `babyID` as a loose FK (not a Core Data relationship) so `FeedSectionView`'s
> per-baby predicate and `FeedService.feeds(for:)` port over verbatim. The Household
> relationship is purely the sharing anchor.

---

## File-by-file changes

### 1. NEW `PersistenceController.swift` (replaces `AppData.swift`)

```swift
//
//  PersistenceController.swift
//  Out for Delivery
//
//  Single CloudKit-backed Core Data stack (NSPersistentCloudKitContainer).
//  Replaces the SwiftData AppData stack. Exposes ONE viewContext shared by the
//  app's environment, ContractionService, and FeedService — the same
//  single-context discipline the SwiftData version relied on. Two persistent
//  stores are configured: `.private` (data we own) and `.shared` (data shared
//  with us); the container routes both through `viewContext`. Sharing wiring
//  (CKShare) is added in Phase B — Phase A only stands up the dual-store stack.
//

import Foundation
import CoreData
import CloudKit

final class PersistenceController {
    @MainActor static let shared = PersistenceController()

    let container: NSPersistentCloudKitContainer

    /// The single context everything uses (app environment + services).
    var viewContext: NSManagedObjectContext { container.viewContext }

    private init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "OutForDelivery")

        // --- Private store (data we own) ---
        guard let privateDesc = container.persistentStoreDescriptions.first else {
            fatalError("No persistent store description")
        }
        if inMemory {
            privateDesc.url = URL(fileURLWithPath: "/dev/null")
        }
        privateDesc.setOption(true as NSNumber,
                              forKey: NSPersistentHistoryTrackingKey)
        privateDesc.setOption(true as NSNumber,
                              forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        privateDesc.cloudKitContainerOptions =
            NSPersistentCloudKitContainerOptions(containerIdentifier: Self.cloudKitContainerID)
        privateDesc.cloudKitContainerOptions?.databaseScope = .private

        // --- Shared store (data shared WITH us) — Phase B uses it; declared now. ---
        let sharedURL = privateDesc.url?
            .deletingLastPathComponent()
            .appendingPathComponent("shared.sqlite")
        let sharedDesc = privateDesc.copy() as! NSPersistentStoreDescription
        if let sharedURL { sharedDesc.url = sharedURL }
        let sharedOptions =
            NSPersistentCloudKitContainerOptions(containerIdentifier: Self.cloudKitContainerID)
        sharedOptions.databaseScope = .shared
        sharedDesc.cloudKitContainerOptions = sharedOptions

        container.persistentStoreDescriptions = [privateDesc, sharedDesc]

        var loadError: Error?
        container.loadPersistentStores { _, error in
            if let error { loadError = error }
        }

        // Fall back to a local-only store if CloudKit setup fails (e.g. no iCloud
        // profile). The app still works fully offline — only sync is unavailable.
        if loadError != nil {
            privateDesc.cloudKitContainerOptions = nil
            container.persistentStoreDescriptions = [privateDesc]
            container.loadPersistentStores { _, error in
                if let error { fatalError("Could not load store: \(error)") }
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        try? container.viewContext.setQueryGenerationFrom(.current)

        ensureHousehold()
    }

    static let cloudKitContainerID = "iCloud.us.yeomans.Out-for-Delivery"

    // MARK: - Household anchor

    /// The single local Household root. Created on first launch; everything new
    /// is related to it so Phase B can share the whole graph as one CKShare.
    @discardableResult
    func ensureHousehold() -> Household {
        let request = Household.fetchRequest()
        request.fetchLimit = 1
        if let existing = try? viewContext.fetch(request).first {
            return existing
        }
        let household = Household(context: viewContext)
        household.id = UUID()
        household.createdAt = Date()
        try? viewContext.save()
        return household
    }

    var household: Household { ensureHousehold() }
}
```

> Note: `Date()`/`UUID()` are fine in app code; they are only forbidden inside
> Workflow scripts, not the app.

### 2. NEW managed-object subclasses (Codegen = Manual/None)

```swift
// Contraction.swift
import Foundation
import CoreData

@objc(Contraction)
final class Contraction: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var startDate: Date?
    @NSManaged var endDate: Date?
    @NSManaged var startsNewSession: Bool
    @NSManaged var loggedByID: String?
    @NSManaged var loggedByName: String?
    @NSManaged var household: Household?

    static func fetchRequest() -> NSFetchRequest<Contraction> {
        NSFetchRequest<Contraction>(entityName: "Contraction")
    }

    var isInProgress: Bool { endDate == nil }
    var duration: TimeInterval? {
        guard let startDate, let endDate else { return nil }
        return endDate.timeIntervalSince(startDate)
    }
}
```

```swift
// Baby.swift  (ageDescription helper unchanged — copy from current file)
@objc(Baby)
final class Baby: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var name: String?
    @NSManaged var birthDate: Date?
    @NSManaged var isArchived: Bool
    @NSManaged var createdAt: Date?
    @NSManaged var feedReminderEnabled: Bool
    @NSManaged var feedReminderInterval: TimeInterval
    @NSManaged var feedAlarmID: UUID?
    @NSManaged var household: Household?
    // + ageDescription computed property (verbatim from current Baby.swift)
}
```

```swift
// Feed.swift  (re-verify attributes against latest before applying)
@objc(Feed)
final class Feed: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var babyID: UUID?
    @NSManaged var timestamp: Date?
    @NSManaged var kind: String?
    @NSManaged var volume: NSNumber?       // Double? — NSNumber for Core Data optionality
    @NSManaged var leftMinutes: NSNumber?  // Int?
    @NSManaged var rightMinutes: NSNumber? // Int?
    @NSManaged var note: String?
    @NSManaged var household: Household?
    // + feedKind, nursingMinutes helpers (adapt to NSNumber-backed optionals)
    // FeedKind / VolumeUnit enums move out to their own file (pure value types).
}
```

```swift
// Household.swift
@objc(Household)
final class Household: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var createdAt: Date?
    @NSManaged var contractions: NSSet?
    @NSManaged var babies: NSSet?
    @NSManaged var feeds: NSSet?

    static func fetchRequest() -> NSFetchRequest<Household> {
        NSFetchRequest<Household>(entityName: "Household")
    }
}
```

> **Optionality gotcha:** Core Data scalar optionals (`volume`, `leftMinutes`,
> `rightMinutes`) are best modeled as `NSNumber?` on the subclass to preserve the
> nil/zero distinction the feed logic relies on. Wrap/unwrap at the service and
> view boundary, or add typed computed accessors:
> ```swift
> var volumeML: Double? {
>     get { volume?.doubleValue }
>     set { volume = newValue.map(NSNumber.init) }
> }
> ```

### 3. `ContractionService.swift`

- `import SwiftData` → `import CoreData`.
- Drop the `container`/`ModelContext` fields; add
  `private let context: NSManagedObjectContext`.
- `init`: `self.context = PersistenceController.shared.viewContext` then `recompute()`.
- Inserts: `let new = Contraction(context: context)` then set `id`, `startDate`,
  and **`new.household = PersistenceController.shared.household`**.
- `context.insert(...)` for new objects is implicit via the `(context:)` initializer;
  keep `try? context.save()`.
- `context.delete(_:)`, `try? context.save()` — same API names, no change.
- `allContractions()`: replace `FetchDescriptor` with `NSFetchRequest`:
  ```swift
  func allContractions() -> [Contraction] {
      let request = Contraction.fetchRequest()
      request.sortDescriptors = [NSSortDescriptor(key: "startDate", ascending: true)]
      return (try? context.fetch(request)) ?? []
  }
  ```
- `recompute()` body unchanged (operates on `[Contraction]`), but guard the new
  optional `startDate`/`endDate` where the old code assumed non-optional. Prefer
  giving the subclass non-optional convenience accessors to minimize churn, e.g.
  `var start: Date { startDate ?? .distantPast }`, and keep `SessionGrouper` /
  `PatternAnalyzer` operating on those.

### 4. `FeedService.swift`

- `import SwiftData` → `import CoreData`.
- `self.context = PersistenceController.shared.viewContext`.
- `feeds(for:)`:
  ```swift
  func feeds(for babyID: UUID) -> [Feed] {
      let request = Feed.fetchRequest()
      request.predicate = NSPredicate(format: "babyID == %@", babyID as CVarArg)
      request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
      return (try? context.fetch(request)) ?? []
  }
  ```
- `baby(with:)`: `NSPredicate(format: "id == %@", id as CVarArg)`, `fetchLimit = 1`.
- `addFeed(...)`: `let feed = Feed(context: context)`, set fields, set
  `feed.household = PersistenceController.shared.household`, `try? context.save()`.
- `update`/`delete`/`save`: same `context.save()` / `context.delete()` API.
- `FeedMath` enum: unchanged (pure).

### 5. View conversions (`@Query` → `@FetchRequest`)

`@FetchRequest` requires the context in the environment (wired in step 7).

- **`ContentView.swift`**
  - `import SwiftData` → `import CoreData` (keep `import SwiftUI`).
  - `@Environment(\.modelContext)` → `@Environment(\.managedObjectContext) private var moc`.
  - `@Query(sort: \Contraction.startDate, order: .reverse)` →
    ```swift
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "startDate", ascending: false)],
        animation: .default
    ) private var contractionsNewestFirst: FetchedResults<Contraction>
    ```
  - `.modelContainer(for: Contraction.self, inMemory: true)` (preview, line 293) →
    `.environment(\.managedObjectContext, PersistenceController(inMemory: true).viewContext)`
    (make a small preview helper; `PersistenceController.init(inMemory:)` is already
    provided above — relax its `private` to `internal` or add a `static let preview`).
- **`RootView.swift`**
  - `@Query(sort: \Baby.createdAt, order: .forward)` →
    ```swift
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "createdAt", ascending: true)]
    ) private var allBabies: FetchedResults<Baby>
    ```
  - Body uses `allBabies` as a sequence — `FetchedResults` is a `RandomAccessCollection`,
    so `.filter`, `.map`, `.first`, `.contains`, `.isEmpty` all work unchanged.
- **`BabyManagerView.swift`**, **`NewbornModeView.swift`** — same Baby `@FetchRequest`
  swap as RootView (`createdAt` ascending).
- **`ModeMenuButtons.swift`** — `@Query private var allBabies: [Baby]` →
  `@FetchRequest(sortDescriptors: []) private var allBabies: FetchedResults<Baby>`.
- **`FeedSectionView.swift`** — dynamic predicate built in `init`:
  ```swift
  @FetchRequest private var feeds: FetchedResults<Feed>
  init(baby: Baby) {
      self.baby = baby            // @Bindable note below
      let id = baby.id ?? UUID()
      _feeds = FetchRequest(
          sortDescriptors: [NSSortDescriptor(key: "timestamp", ascending: false)],
          predicate: NSPredicate(format: "babyID == %@", id as CVarArg)
      )
  }
  ```
  - `@Bindable var baby: Baby` (SwiftData) → with Core Data, `Baby` is an
    `NSManagedObject` (an `ObservableObject`); use
    `@ObservedObject var baby: Baby` and bind via `$baby.feedReminderEnabled`, etc.
    (`@ObservedObject` gives the same `$`-projected bindings the toggles/pickers use).
  - All `feeds.first`, `feeds.count`, `feeds.prefix`, `feeds.firstIndex`,
    `Array(feeds...)` usage ports unchanged (`FetchedResults` conforms).

### 6. `BabyFormView.swift`

- `import SwiftData` → `import CoreData`.
- `@Environment(\.modelContext) private var modelContext` →
  `@Environment(\.managedObjectContext) private var moc`.
- `let newBaby = Baby(...)` + `modelContext.insert(newBaby)` →
  ```swift
  let newBaby = Baby(context: moc)
  newBaby.id = UUID()
  newBaby.name = name
  newBaby.birthDate = birthDate
  newBaby.createdAt = Date()
  newBaby.household = PersistenceController.shared.household
  try? moc.save()
  ```
- If the form also edits an existing `Baby`, mutate the managed object and
  `try? moc.save()` (no `insert`).

### 7. `Out_for_DeliveryApp.swift`

- `import SwiftData` → `import CoreData`.
- Remove `.modelContainer(AppData.shared.container)`.
- Inject the shared context:
  ```swift
  var body: some Scene {
      WindowGroup {
          RootView()
              .environment(\.managedObjectContext,
                           PersistenceController.shared.viewContext)
      }
  }
  ```
- `IntentDispatcher.toggle` and `FeedReminderManager.shared.registerIntentHandlers()`
  in `init()` are **unchanged** — the in-process intent path doesn't touch the stack.

### 8. Delete `AppData.swift`

Removed entirely; `PersistenceController.shared` replaces every `AppData.shared`
reference. Grep for `AppData` after the swap — there should be zero hits.

---

## Things explicitly NOT in Phase A (deferred)

- **CKSharingSupported / ShareLink / accept delegates** → Phase B/C.
- **`.shared` entitlement scope** is declared in code (store description) but the
  `Info.plist` `CKSharingSupported = YES` and the UIKit `App/SceneDelegate` accept
  flow come in Phase B.
- **Attribution population** (`loggedByID`/`loggedByName`) — fields exist now; they
  stay nil until Phase B knows the current CloudKit user.
- **CSV framework** (Phase A') — separate changeset; independent of this swap.

## Verification after applying

1. `XcodeRefreshCodeIssuesInFile` on each changed file (fast) — zero unresolved types.
2. `BuildProject` (scheme `Out for Delivery`) — clean build.
3. Grep `import SwiftData`, `@Query`, `@Model`, `ModelContext`, `AppData` → **0 hits**.
4. `RunAllTests` — `FeedReminderTests` and existing tests still pass (their math is
   stack-independent; only the service construction context changed).
5. Smoke on device: log a contraction (Live Activity updates), log a bottle + breast
   feed, edit/delete each, archive a baby (drops to labor mode). All identical to today.
6. Confirm a single Household row exists and new objects carry the `household`
   relationship (one-off fetch in `RunCodeSnippet`).

## Migration of existing data

First launch on the Core Data store starts **empty** (new store file). Existing
users' SwiftData data is in the old store and will not auto-appear. Options, in
order of preference, to be decided before shipping:

- **Lightweight import on first run**: read the legacy SwiftData store read-only and
  copy rows into Core Data (one-time, guarded by a `UserDefaults` flag).
- **CSV round-trip** (leans on Phase A'): export from the SwiftData build, import into
  the Core Data build. This is also the path for bringing a second caregiver's
  existing data across, so it is being built regardless.

Pick the import strategy when scheduling the swap; it does not change any code above.
