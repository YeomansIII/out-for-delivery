# Out for Delivery — Implementation Spec

**Out for Delivery** is a single-purpose iOS app for timing labor contractions, with a persistent Live Activity that can be operated from the Lock Screen and Dynamic Island. It frames the experience in the visual language of a package-delivery tracker (see §18), while keeping all medical numbers exact. Built for one user, with data stored locally and synced/backed up through that user's **private iCloud** (CloudKit). No third-party services, no public sharing.

---

## 1. Goals & non-goals

**Goals**
- Open directly to the contraction log with a large, unmissable Start/Stop control.
- A Live Activity that:
  - Persists on the Lock Screen for as long as practical (see §8.4 on the system cap).
  - Lets the user start/stop a contraction without unlocking or opening the app.
  - Shows a live count-up of the **current contraction's duration** while counting, and the live **time since the last contraction started** while resting.
- **Local-first with private iCloud sync.** The app works fully offline; the on-device SwiftData store is the source of truth and syncs to the user's private CloudKit database opportunistically when a network is available (for backup and cross-device access). Data stays within the user's own iCloud account. A user-initiated **CSV export** via the share sheet is the only path to take data *outside* iCloud.
- Modern iOS 26 implementation: SwiftUI + Liquid Glass, `@Observable`, SwiftData, ActivityKit, App Intents.

**Non-goals (explicitly out of scope)**
- No "add a past contraction" / manual backfill.
- No third-party backend, account system, analytics, ads, or push server. (iCloud sync uses the user's own Apple account via CloudKit, not an app-operated server.)
- No medical advice, alarms, or notifications that tell the user to act. A quiet 5-1-1 readout only.
- No multi-session management UI beyond an implicit "current session" (a contiguous run of contractions).

---

## 2. Definitions (timing conventions)

These are the conventions the app computes against. They follow standard childbirth-education usage.

- **Duration** — length of a single contraction: `endDate − startDate`.
- **Frequency / interval** — time from the **start of one contraction to the start of the next** (this includes the rest period in between). This is the number the app surfaces as "time since last contraction," per the chosen convention.
- **5-1-1 pattern** — contractions ~5 minutes apart (start-to-start), each lasting ≥1 minute, sustained for ≥1 hour. Common variants (4-1-1, 3-1-1) exist and depend on the provider's instructions. Treated here as a **passive readout only**, never an alarm. The provider's own guidance always overrides.

**Disclaimer requirement:** Include a brief, non-intrusive disclaimer (first-launch sheet + a small footer/Info item): this app is a timing aid, not a medical device; follow your provider's instructions; in an emergency call your provider or emergency services. Keep it short and dismissible. The first-launch sheet should also note, in one line, that contraction data is stored in the user's private iCloud (and that iCloud can be turned off in Settings to keep data on-device only — see §14).

---

## 3. Platform & tech stack

- **Deployment target:** iOS 26.0. (Target device is an iPhone 14 Pro or newer → Dynamic Island + interactive Live Activity buttons both available.)
- **Language:** Swift 6 (strict concurrency on).
- **UI:** SwiftUI, Liquid Glass design system (§12).
- **State:** `@Observable` services/view models (Observation framework). No `ObservableObject`.
- **Persistence:** SwiftData backed by **CloudKit** (`ModelConfiguration` with `cloudKitDatabase: .automatic`, or a named container). On-device store is local-first; CloudKit mirrors it to the user's **private database** for backup + cross-device sync. See §4 for the CloudKit-imposed model constraints.
- **Live Activity:** ActivityKit inside a WidgetKit extension.
- **Lock-screen buttons:** App Intents — specifically `LiveActivityIntent`, which executes in the **app's process**, so it can mutate the CloudKit-backed SwiftData store directly (writes then sync to iCloud like any other). **No App Group is required** — CloudKit handles cross-*device* sync; the intent and app share the same process for cross-*context* writes. (An App Group remains available on the paid account as a fallback if `LiveActivityIntent` in-process execution ever proves insufficient.)
- **Export:** SwiftUI `ShareLink` writing a `.csv` to a temp URL.
- **Entitlements:** `NSSupportsLiveActivities = YES`; **iCloud → CloudKit** with one container (e.g. `iCloud.com.yourname.outfordelivery`); **Background Modes → Remote notifications** (so SwiftData/CloudKit can apply sync changes in the background). No app-operated push server, no other background modes. Full list in §14.

**Targets**
1. `OutForDelivery` (app). Bundle id e.g. `com.yourname.outfordelivery`.
2. `OutForDeliveryWidgets` (widget extension hosting the Live Activity UI). Bundle id e.g. `com.yourname.outfordelivery.widgets`.
3. Shared source (added to both targets' membership): the `ActivityAttributes` type and the `LiveActivityIntent` definitions. Business logic that the intent calls lives in the app and runs in-process.

> Internal type names stay descriptive (`Contraction`, `ContractionService`, `ContractionActivityAttributes`, `ToggleContractionIntent`) for code clarity — the delivery theme lives in user-facing copy only (§18), not in the codebase.

---

## 4. Data model (SwiftData)

```swift
@Model
final class Contraction {
    // CloudKit-backed SwiftData forbids `@Attribute(.unique)` and requires every
    // stored property to be optional OR have a default. Hence defaults below and
    // no unique constraint on `id`.
    var id: UUID = UUID()
    var startDate: Date = Date.distantPast   // real value set on insert
    var endDate: Date?                        // nil while a contraction is in progress
    init(id: UUID = UUID(), startDate: Date, endDate: Date? = nil) { ... }

    var isInProgress: Bool { endDate == nil }
    var duration: TimeInterval? { endDate.map { $0.timeIntervalSince(startDate) } }
}
```

**CloudKit model constraints (must follow or sync silently fails):**
- No `@Attribute(.unique)` — uniqueness of `id` is enforced in app logic, not the schema.
- Every stored property is optional or has a default value (as above).
- Any relationships (none in MVP) must be optional with inverses.
- Enums/types persisted must be `Codable`/representable in CloudKit.

Other rules unchanged:
- **Frequency is derived, not stored.** Interval for contraction *n* = `startDate(n) − startDate(n−1)`. The first contraction has no interval.
- At most **one** `Contraction` may have `endDate == nil` at a time (the open/in-progress one). Enforced in `ContractionService`.
- "Session" is implicit: the ordered list of all contractions. A "Clear all" action exists (see §6); deletions tombstone-sync to iCloud normally.

**Container:** a single shared `ModelContainer` built with a CloudKit-enabled `ModelConfiguration`, exposed via an accessor (e.g. `AppData.shared.container`) used by both the app's `.modelContainer(...)` and the `LiveActivityIntent.perform()` running in-process. Initialize it lazily so a background launch of the intent can spin it up. The store is usable immediately offline; CloudKit reconciles when connectivity returns.

---

## 5. Core state machine

Two phases, derived from whether an in-progress contraction exists:

- **Idle / Resting** — no open contraction. Primary action: **Start**.
- **Contracting** — one open contraction. Primary actions: **Stop** and **Cancel**.

Transitions (all routed through one `ContractionService` so the app UI, the Live Activity buttons, and the in-app buttons share identical logic):

| Trigger | Effect |
|---|---|
| **Start** (from idle) | Insert `Contraction(startDate: now)`. Phase → Contracting. Recompute readout. Update/Start Live Activity. Haptic. |
| **Stop** (from contracting) | Set `endDate = now` on the open contraction. Phase → Idle. Recompute readout. Update Live Activity. Haptic. |
| **Cancel** (from contracting) | **Delete** the open contraction (no record kept). Phase → Idle. Update Live Activity. Haptic. *(This is the "I tapped Start but it wasn't a real contraction" path.)* |
| **Delete** (any logged row) | Remove that `Contraction`. Recompute the interval of the following contraction (its frequency depends on the deleted neighbor's start). Update readout/Live Activity if the open or most-recent item changed. |

---

## 6. Main app screen

Single screen, opens here on launch.

**Layout (top → bottom)**
1. **Status header** — small, glass chip. Shows current phase and the live primary counter (mirrors the Live Activity counter, §9), plus the quiet 5-1-1 readout (§10), e.g. `~4m 10s apart · ~55s long · 5-1-1: not yet`.
2. **Primary control** — a large `.glassProminent` button, generous tap target.
   - Idle: **"Start Contraction"**.
   - Contracting: **"Stop Contraction"**, with the live current-duration counter shown prominently above or within it, plus a secondary **"Cancel"** button (text/`.glass` style) to discard the in-progress one.
3. **Log list** — `List` driven by `@Query(sort: \.startDate, order: .reverse)`. Newest first. Each row:
   - Contraction number (oldest = #1, stable index).
   - Start time (clock, `.timer`-free static formatting, e.g. `2:14 PM`).
   - Duration (`mm:ss`, or `—` if in progress).
   - Interval since previous start (`mm:ss`, or `—` for the first).
   - **Swipe-to-delete** (`.swipeActions` / `onDelete`). The in-progress row is also deletable (equivalent to Cancel).
4. **Toolbar**
   - **Share / Export CSV** (`ShareLink`, §11).
   - **Lock Screen toggle** — "Show on Lock Screen" / "Hide" (controls the Live Activity, §8.3).
   - Overflow: **Clear all** (destructive, confirm dialog), **Info/Disclaimer**.

**UX rules during labor (important — see §13):** large hit targets, haptic confirmation on every Start/Stop, monospaced timer digits, no fiddly gestures required for the core loop.

---

## 7. Live Activity — data contract

```swift
struct ContractionActivityAttributes: ActivityAttributes {
    // Static for the life of the activity (none needed beyond a title/version).
    public struct ContentState: Codable & Hashable {
        enum Phase: String, Codable { case contracting, resting }
        var phase: Phase
        var currentStart: Date?     // start of in-progress contraction (for duration count-up)
        var lastStart: Date?        // start of most recent contraction (for "time since last" count-up)
        var lastDuration: TimeInterval?   // most recent completed duration (static display)
        var lastInterval: TimeInterval?   // most recent start-to-start interval (static display)
        var count: Int              // contractions logged so far
        // Readout snapshot (recomputed on each tap; see §10)
        var avgInterval: TimeInterval?
        var avgDuration: TimeInterval?
        var patternMet: Bool        // 5-1-1 (or selected rule) currently satisfied
    }
    var title: String               // e.g. "Contractions"
}
```

The widget renders timers **from these dates** using self-updating timer text — no per-second pushes, no networking, negligible battery. Static fields (`lastDuration`, `lastInterval`, readout) change only when a button is tapped, at which point the intent calls `activity.update(...)`.

---

## 8. Live Activity — behavior & lifecycle

### 8.1 Presentations

**Lock Screen card**
- Phase label ("Contracting" / "Resting") + state glyph.
- **Primary live counter** (large, monospaced): current duration when contracting; time-since-last-start when resting (§9).
- Secondary line: last duration, last interval, count, and the 5-1-1 readout.
- **Start/Stop button** (`Button(intent:)`, §8.2). Big, glass.

**Dynamic Island**
- *Compact leading:* state glyph (e.g. a dot that animates while contracting).
- *Compact trailing:* the primary live counter (`mm:ss`).
- *Minimal:* the primary live counter or glyph.
- *Expanded:* phase + glyph (leading), large live counter (trailing), secondary stats + readout (bottom), and the **Start/Stop button** (interactive buttons render in the expanded island and the Lock Screen, not in compact/minimal — those deep-link into the app).

### 8.2 Interactive buttons (App Intents)

```swift
struct ToggleContractionIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Toggle Contraction"
    func perform() async throws -> some IntentResult {
        // Runs in the app's process → direct SwiftData access.
        await ContractionService.shared.toggle()   // Start if idle, Stop if contracting
        return .result()
    }
}
```
- One toggle intent (Start when idle, Stop when contracting) keeps the Lock Screen UI to a single button. Cancel/delete stays in-app (space-constrained surface; avoids accidental data loss from a lock-screen mis-tap).
- `LiveActivityIntent.perform()` executes in-process and may start/update/end the activity from the background.

### 8.3 Start / show / hide

- The activity **auto-starts** when the user taps Start on the first contraction (app is foreground → `Activity.request` is permitted).
- It **persists for the whole session**. The toolbar toggle hides it (`activity.end(dismissalPolicy: .immediate)`) or re-shows it (re-`request` while foreground).
- "Clear all" and the end of a session end the activity.

### 8.4 The 8-hour system cap (key constraint + mitigation)

A Live Activity can be **active for up to 8 hours**; the system then ends it automatically and it lingers on the Lock Screen for up to **4 more hours** (12h total max). It **cannot be started from the background** without push-to-start (which needs a server we are deliberately not building). It **can be updated and ended from the background** — which is exactly what the toggle button does within the 8-hour window.

**Mitigation (no server):**
- The button taps **update** the existing activity; they do **not** need to restart it, so the normal labor loop works fully from the Lock Screen.
- To reset the 8-hour clock, the app **re-requests a fresh activity whenever it becomes foreground** (`scenePhase == .active`) if a session is active and the activity is missing or near expiry. During real labor the user opens the app well within any 8-hour window, so this is robust in practice.
- Set a `staleDate` on the content (≈ `currentStart`/`lastStart` + a sensible window) so the system can dim stale data.
- **Honest limitation to document in-app:** if the phone is untouched with no taps and no app opens for ~8 hours straight (e.g. a long early-labor sleep), the activity may lapse before the next interaction. Handle gracefully: when the app next foregrounds, detect the lapsed activity and show a small **"Live Activity expired — tap to restart"** affordance. Not literally unbounded, but covers the realistic path.

---

## 9. Timer rendering (count-up logic)

Use SwiftUI self-updating timer text (e.g. `Text(timerInterval: start...Date.distantFuture, countsDown: false)`), which ticks on the Lock Screen without updates.

**Exactly one live counter is prominent at a time, always meaningful:**

- **Contracting:** primary counter = **current duration**, counting up from `currentStart`. Secondary (static): "last interval: `mm:ss`" (the interval just measured at this Start).
- **Resting:** primary counter = **time since last contraction started**, counting up from `lastStart` (this is the developing frequency, per the chosen convention). Secondary (static): "last lasted: `mm:ss`".
- **First contraction, before any data:** interval is undefined → show `—` / "first contraction".

This design sidesteps the "pausing timer text" problem: the current-duration timer only ever runs Start→Stop and is then replaced by a static finalized value; the since-last timer runs continuously until the next Start resets its anchor. No timer ever needs to pause/resume.

**Digit jitter:** use monospaced/fixed-width digits (e.g. `.monospacedDigit()` or fixed character cells) so the surrounding layout doesn't reflow each second.

---

## 10. 5-1-1 readout (passive)

Recomputed in `perform()` / on each log change, snapshotted into `ContentState`:

- Consider completed contractions in a trailing window (default 60 min).
- Compute start-to-start intervals and durations within the window.
- **Pattern met** when intervals are ≤ threshold-apart, durations ≥ threshold-long, and the pattern has held for ≥ the sustain window. Defaults: 5 min / 1 min / 60 min (i.e. 5-1-1).
- Surface as text only: e.g. `~4m 10s apart · ~55s long · 5-1-1: met`. **No notification, no alarm, no "go to the hospital" instruction.**
- *Optional / nice-to-have (cuttable):* a rule selector (5-1-1 / 4-1-1 / 3-1-1 / custom) in the Info/settings area, since providers vary. Defaults to 5-1-1. Keep it out of the main flow.

---

## 11. CSV export

- `ShareLink` exporting a generated `.csv` file (write to `FileManager` temp dir, share the URL).
- **Filename:** `contractions-YYYYMMDD-HHmm.csv`.
- **Columns:**
  `index, start_iso8601, end_iso8601, duration_seconds, interval_since_prev_start_seconds, duration_mmss, interval_mmss`
- One row per contraction, oldest first. Empty cells for an in-progress contraction's end/duration and for the first row's interval. Times in the device's local time zone (ISO 8601 with offset).
- No sharing target is preselected; the system share sheet handles destination. The CSV is the only path that moves data *outside* the user's iCloud; routine background iCloud sync of the SwiftData store is separate and stays within the user's private database (§3, §14).

---

## 12. Design language (Liquid Glass / iOS 26)

Follow Apple's HIG layering rule: **Liquid Glass for the functional layer** (controls, the status chip, the primary button, toolbar), **standard backgrounds for the content layer** (the log list rows stay legible/solid).

- Primary button: `.buttonStyle(.glassProminent)`, large, `.tint(...)`; consider `.glassEffect(.regular.tint(...).interactive())` for press feedback.
- Status chip / secondary controls: `.glassEffect()` (regular).
- Use a `GlassEffectContainer` only if multiple glass controls sit close together and should blend/morph (e.g. Stop + Cancel as a cluster); otherwise plain `.glassEffect()` is sufficient. Don't over-apply glass.
- Native controls (`List`, toolbar, sheets, `TabView` if ever used) adopt Liquid Glass automatically when compiled against the iOS 26 SDK.
- Test with **Reduce Transparency** on (the UI must remain fully legible) and on **physical hardware** (specular highlights don't render in the simulator).

---

## 13. Accessibility & labor-specific UX

- **Haptics** on every Start/Stop/Cancel (e.g. `.sensoryFeedback`) so taps are confirmed without looking.
- **Large tap targets** for the primary control; tolerate imprecise taps.
- **Dynamic Type** support; monospaced digits on all timers.
- **VoiceOver** labels on the primary control and each log row (phase, duration, interval).
- High-contrast, glanceable counter typography on the Lock Screen.
- Don't require precise gestures for the core loop; deletion (a less time-critical action) can use swipe.

---

## 14. Configuration / Info.plist / entitlements

- App Info.plist: `NSSupportsLiveActivities = YES`.
- **iCloud capability → CloudKit**, with one container (e.g. `iCloud.com.yourname.outfordelivery`).
- **Background Modes → Remote notifications** enabled, so SwiftData/CloudKit can receive and apply sync changes when the app isn't foreground. (This is for CloudKit's silent sync pushes — not an app-operated push server.)
- No other background modes. No network usage description needed (no direct `URLSession`/custom networking; CloudKit is handled by the system).
- No App Group (see §3).
- **iCloud account dependency:** sync requires the user to be signed into iCloud with iCloud Drive available for the app. The app must degrade gracefully when there's no account or iCloud is disabled: the **local SwiftData store still works fully** (timing, log, Live Activity, CSV export all function); only cross-device sync/backup is unavailable. Surface a quiet, non-blocking indicator if iCloud is unavailable — never block the core timing loop on it.
- Provide a way to verify/observe sync state for debugging (e.g. log `NSPersistentCloudKitContainer`/SwiftData sync events), but keep it out of the main UI.
- Lock Screen Live Activities must be enabled by the user in Settings (Face ID & Passcode → Live Activities, and the app's own Live Activities toggle). Surface a hint in-app if `ActivityAuthorizationInfo().areActivitiesEnabled == false`.

---

## 15. Distribution

- **Primary:** install via Xcode to the device.
- **Risk:** a *free* signing profile expires after 7 days and the app would refuse to launch — unacceptable near a due date. **You have a paid Apple Developer account**, so:
  - Use a development/distribution profile (no 7-day expiry), and/or
  - Ship a **TestFlight** build (valid 90 days, installs without a Mac tether). Recommended as the dependable path so nothing lapses during labor.
- Regardless of path, do a fresh install and a full smoke test (start/stop from Lock Screen, Dynamic Island, CSV export, delete/cancel) a few days before the due date.

---

## 16. Risks & constraints (summary)

1. **8-hour Live Activity cap** — mitigated by foreground re-request + an explicit "expired, tap to restart" state (§8.4). Cannot be made truly unlimited without a push server, which is out of scope by design.
2. **Background start not allowed** — the activity must first be created with the app in the foreground; thereafter Lock Screen buttons only update it.
3. **`LiveActivityIntent` in-process execution** — the design depends on the toggle intent running in the app process for SwiftData access; verify against the current SDK during implementation. (Fallback if ever needed: an App Group + shared store, which the paid account supports.)
4. **Glass legibility** — must pass the Reduce Transparency check.
5. **CloudKit privacy/scope change** — this reverses the original strictly-on-device goal. Labor data is mirrored to the user's private iCloud database. It stays within their Apple account (no third parties), but it does leave the device. Confirm this tradeoff is intended; an on-device-only configuration is a one-line container change if not.
6. **iCloud availability** — sync depends on the user being signed into iCloud with space available; schema mismatches or `.unique`/non-default properties will make CloudKit sync fail silently. The model in §4 is written to avoid that. The app must remain fully functional offline / without an iCloud account.
7. **CloudKit schema deployment** — the development CloudKit schema must be promoted to **Production** in the CloudKit Console before a TestFlight/release build, or synced data won't appear for real users/builds.

---

## 17. Build checklist / verify-against-SDK

- [ ] App target opens directly to the log + Start/Stop; SwiftData store wired via shared **CloudKit-backed** container.
- [ ] Model is CloudKit-compatible (no `.unique`, all properties optional/defaulted); sync verified on a second signed-in device.
- [ ] iCloud capability + CloudKit container + Remote-notifications background mode configured; CloudKit schema promoted to Production before release.
- [ ] App fully functional with iCloud signed out / offline; quiet non-blocking indicator when sync is unavailable.
- [ ] `ContractionService` single source of truth for Start/Stop/Cancel/Delete.
- [ ] Widget extension: Lock Screen + all Dynamic Island presentations; timers via self-updating timer text with monospaced digits.
- [ ] `ToggleContractionIntent` (`LiveActivityIntent`) wired to the same service; confirm in-process execution + background update/end.
- [ ] Auto-start activity on first contraction; foreground re-request to reset the 8h clock; "expired, tap to restart" handling.
- [ ] 5-1-1 readout (passive); optional rule selector behind settings.
- [ ] CSV export via `ShareLink` with the column layout in §11.
- [ ] Liquid Glass applied to the functional layer only; Reduce Transparency + on-device verification.
- [ ] Haptics, Dynamic Type, VoiceOver, large tap targets.
- [ ] First-launch disclaimer + Info footer.
- [ ] Smoke-tested end-to-end on the actual device before the due date; distributed via a non-expiring profile or TestFlight.
- [ ] Display copy follows the theme map in §18; action/destructive controls kept literal; medical numbers always shown plainly.

---

## 18. Naming & display copy (theme)

App name: **Out for Delivery**. The UI borrows package-tracker phrasing as flavor on **ambient/status text only**. Two hard rules:

1. **Action and destructive controls stay literal and unambiguous** — "Start", "Stop", "Cancel", "Clear all". Never make the critical labor controls cute; they must be instantly readable mid-contraction.
2. **The medical numbers are always visible and plainly labeled** — interval (start-to-start) and duration in `mm:ss`. The partner may be reading these aloud to a provider, so the theme never replaces or obscures them; it sits alongside.

| Surface / state | Themed copy | Literal value shown alongside |
|---|---|---|
| Live Activity / app title | "Out for Delivery" | — |
| Resting (between contractions) | "In transit" | time since last start, `mm:ss`, labeled "since last" |
| Contracting (in progress) | "Out for delivery" | current duration, `mm:ss`, labeled "this one" |
| Before any data (first tap pending) | "Order placed" | — |
| 5-1-1 (or selected rule) met | "Arriving soon" | `~Xm apart · ~Ys long` |
| Session count | "{n} updates" | n |
| Export action (toolbar) | "Export tracking history" | produces the CSV in §11 |
| Primary control | **"Start" / "Stop"** (literal) | live counter |
| Cancel in-progress / Clear all | **"Cancel" / "Clear all"** (literal) | — |

Keep it light — a couple of themed touches read as charming; theming every string reads as gimmicky and hurts legibility. If a label's theme ever fights clarity, clarity wins.
