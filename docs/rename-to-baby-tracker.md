# Rename: "Out for Delivery" → "Baby Tracker"

Display name (Home Screen + share sheet) = **"Poops, Pumps, Feeds"** (already done via
`CFBundleDisplayName` + the in-app `SharePreview`/`CKShare` title). This doc covers the heavier
**project / target / scheme / bundle-identifier** rename to **Baby Tracker** (`baby-tracker`).

## Do this as a dedicated session, AFTER sharing is verified
A bundle-ID change ripples into provisioning, the CloudKit container, and both physical devices. Don't
interleave it with the in-progress sharing test. Finish verifying sharing first, then rename.

## Critical decision: the CloudKit container
CloudKit container identifiers are **independent of the bundle ID** — a container created earlier can be
attached to a renamed bundle via its entitlements.

- **Recommended — keep `iCloud.us.yeomans.Out-for-Delivery`.** Rename the app/target/bundle but leave the
  container ID untouched (`PersistenceController.cloudKitContainerID` stays as-is, entitlement keeps the
  same container). This preserves the dev environment you just reset, the schema, and the provisioning —
  zero CloudKit rework. The container ID is invisible to users.
- **Optional — new `iCloud.us.yeomans.baby-tracker`.** Cleaner naming, but you re-create the container in
  the dev portal, re-provision both devices, re-push the schema, and re-test sharing from scratch. Only
  worth it for a clean public launch.

Pick the recommended path unless there's a reason not to.

## Change checklist (full rename)
**Project / build settings (Xcode UI is safest for these):**
- Rename the app **target** "Out for Delivery" → "Baby Tracker" (Xcode target rename refactor).
- Rename the **scheme** "Out for Delivery" → "Baby Tracker".
- Rename `Out for Delivery.xcodeproj` and the `Out for Delivery/` source group/folder.
- `PRODUCT_BUNDLE_IDENTIFIER`: app `us.yeomans.Out-for-Delivery` → `us.yeomans.baby-tracker`; widget
  `…Out-for-Delivery.LiveActivity` → `us.yeomans.baby-tracker.LiveActivity`; both test targets similarly.
  (Widget ID must stay a prefix-child of the app ID.)
- `INFOPLIST_KEY_CFBundleDisplayName` if set there instead of Info.plist (keep "Poops, Pumps, Feeds").
- Rename `Out_for_Delivery.entitlements` → `BabyTracker.entitlements`; update `CODE_SIGN_ENTITLEMENTS`.
  Keep the same `iCloud.…` container array unless going with a new container.
- App Group, if one exists for the widget/Live Activity (`group.us.yeomans.…`): rename + update both
  targets' entitlements (and any `UserDefaults(suiteName:)`).
- `Out for Delivery.xctestplan` → `Baby Tracker.xctestplan`; update the scheme's `TestPlanReference`.
- Rename the `Out-for-Delivery.icon` asset if desired.

**Code identifiers (safe, mechanical):**
- `Out_for_DeliveryApp.swift` → `BabyTrackerApp.swift`; `struct Out_for_DeliveryApp` → `struct BabyTrackerApp`.
- `Logging.swift`: `Logger(subsystem: "us.yeomans.Out-for-Delivery", …)` → new bundle ID.
- `PersistenceController`: the programmatic container `name: "OutForDelivery"` can stay (local store
  filename only) or become `"BabyTracker"` — note renaming it starts a fresh local store file.
  `cloudKitContainerID` stays unless choosing a new container.
- Grep for `Out for Delivery`, `Out_for_Delivery`, `OutForDelivery`, `Out-for-Delivery` and update
  remaining user-facing strings/comments. (User-facing app name strings should read "Poops, Pumps,
  Feeds"; internal type/scheme names use "Baby Tracker".)

**Docs:** update `docs/` references and `CLAUDE.md` (the "What this is" intro names the app).

## Sequencing
1. Close the in-progress sharing test (confirm it works on the current name).
2. Branch. Target rename → scheme rename → bundle IDs → entitlements/container decision.
3. Rename files/folders/.xcodeproj + code identifiers; fix references.
4. `BuildProject` green; run on device; **re-run the sharing test** (especially if the container changed).
5. `RunSomeTests` (CSV + feed reminder) green.

## Risks
- Bundle-ID change invalidates the current provisioning profiles → Xcode must regenerate (automatic
  signing) and both devices re-trust on first run.
- A **new** CloudKit container discards the reset/schema/shares — avoid unless deliberately starting clean.
- File-system-synchronized group: renaming the source folder must keep the group in sync, or files drop
  from the target.
