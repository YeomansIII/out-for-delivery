# Design ↔ Code Map — Newborn Dashboard

This maps the **Newborn Dashboard** design (the "Poops Pumps Feeds" mockups) to the
SwiftUI code that implements it, frame by frame, with the context a future agent or
designer needs to keep the two in sync.

## Where the design lives

- **Source mockups:** `docs/design/project/Poops Pumps Feeds Dashboard.dc.html` — a
  Claude Design (claude.ai/design) HTML/CSS prototype. Ten phone frames laid out on a
  canvas, each wrapped in a `data-screen-label` div. `docs/design/README.md` is the
  original handoff note.
- **Origin:** exported from claude.ai/design project `33757f4d-119b-4708-a197-112798c8a3bc`.
  Re-export the bundle and replace `docs/design/` to refresh it.

The HTML is a **baseline for layout and content only**. The app deliberately does
*not* copy its structure: surfaces use native iOS 26 SwiftUI + system materials (so
light/dark both adapt — frame 09 is "free"), and **Liquid Glass is reserved for the
primary actions** (quick-log buttons, the Save button), while the medical numbers
stay in solid, legible cards with monospaced digits. See `CLAUDE.md` › Conventions.

## Status legend

- ✅ **Built** — implemented and shipping.
- 🚧 **Partial** — core built; a sub-interaction deferred (noted).
- ⛔ **Not built** — out of current scope (epic noted for when it lands).

## Frame-by-frame map

| # | Frame (design label) | Status | App code | Notes |
|---|----------------------|--------|----------|-------|
| 01 | Dashboard — status at a glance | ✅ | `NewbornModeView.swift` (`BabyDashboardView`, `RecentTile`), `NewbornStyle.swift` | Header, feed-reminder countdown card, recent feed/diaper/pump tiles, daily totals, quick-log buttons. The "Weight & growth" row is omitted (growth out of scope). |
| 02 | Log feed — bottle | ✅ | `EditFeedView.swift` | Bottle/Nursing segmented, big ± volume stepper with presets + ml/oz toggle, Formula/Breast milk, time, note, Save bar with attribution. |
| 03 | Nursing timer — running | 🚧 | `EditFeedView.swift` (Nursing mode) | Live tap-a-side timer + haptics deferred (stories 8.1/8.4/8.5). Nursing is captured as manual minutes-per-side steppers (story 8.2). |
| 04 | Log diaper | ✅ | `EditDiaperView.swift` | Wet/Dirty/Both, stool color swatches + consistency (dirty only), time, note. |
| 05 | Log pump | ✅ | `EditPumpView.swift` | Per-side **or** combined total entry, derived total readout, manual duration (minutes), time, note. The "Time it" live timer is deferred. |
| 06 | Growth — add measurement | ⛔ | `NewbornModeView.swift` (`GrowthPlaceholderView`) | Epic 12 (weight/length/head, trend chart). Not built — the Growth tab is a "coming soon" stub for now. |
| 07 | Timeline — unified, with attribution | ✅ | `TimelineView.swift` (`BabyTimelineView`), `NewbornModeView.swift` (bottom nav) | Cross-type merged list (feeds+diapers+pumps), grouped by day (Today / Yesterday / date), newest first, with per-entry attribution. Filter chips (All / Feeds / Diapers / Pumps) in Liquid Glass; tap a row to edit and swipe to delete via the existing editors/services; an "Add past" + menu logs any type. Reached via the bottom nav (below). |
| 08 | Dashboard B — feed-clock hero | ⛔ | — | Alternative layout (a large "since last feed" ring). Not adopted; frame 01's layout is the shipped one. |
| 09 | Dashboard — warm light mode | ✅ (implicitly) | `NewbornModeView.swift` | Not a separate screen — light mode falls out of using system materials + semantic tints instead of hard-coded colors. |
| 10 | Nursing timer — ready to start | 🚧 | — | Same deferral as frame 03 (live timer + next-side suggestion, story 8.3). |

## Cross-cutting structure

**Data model** (programmatic Core Data, CloudKit-mirrored — see `PersistenceController.makeModel`):
- `Feed.swift` — bottle volume (canonical ml), `bottle` (formula/breast milk, 8.7),
  nursing minutes per side, `note` (8.11).
- `Diaper.swift` — `DiaperKind` (wet/dirty/both), `DiaperColor`, `DiaperConsistency`, note.
- `Pump.swift` — left/right/combined volume (canonical ml), duration, note.
- Each event is a cascade child of its `Baby` (the per-baby CKShare root) and carries
  caregiver attribution (`loggedByID`/`loggedByName`, stamped by `CurrentUserIdentity`).

**Services** (one shared `viewContext`, mirror `FeedService`): `FeedService`,
`DiaperService`, `PumpService` — fetch helpers, time-since-last, today's totals,
add/update/delete. Feeds additionally re-arm the feed-on-demand reminder
(`FeedReminderManager`); diapers and pumps do not alert (calm-by-default ethos).

**Shared style:** `NewbornStyle.swift` — `NewbornEvent` (feed = orange, diaper = green,
pump = pink; icon per type) and `DiaperColor.swatch`. Change accent colors/icons here.

**Bottom navigation** (design frames 01/07): newborn mode is a native iOS 26 `TabView`
(the floating Liquid Glass bar) in `NewbornModeView`, with tabs **Home** (the dashboard),
**Timeline** (`BabyTimelineView`), and **Growth** (a stub until Epic 12). Each tab has its
own `NavigationStack`; the baby picker + "More" menu (mode switch, Family, manage babies)
is the shared top toolbar on every tab. The design's 4th tab, **Family**, is deferred — it
stays in the More menu (`Sheet.family`) for now, shared with labor mode. Quick-log lives on
the Home tab, not in the bar (matching the design).

**Specs:** the *what/why* for these screens is `docs/Newborn-Care-Features.md`
(Epic 8 feeds, 9 pumps, 10 diapers, 11 dashboard/timeline, 12 growth).

## Editing guidance for future changes

- **A frame's layout changes** → edit the file in the table above. Dashboard tiles,
  totals, and the reminder card are private subviews of `BabyDashboardView` in
  `NewbornModeView.swift`.
- **Add a field to an event** → add the attribute in the model class *and* in
  `PersistenceController.makeModel` (every attribute must be optional or defaulted for
  CloudKit), thread it through the service `add`/`update`, the editor `Draft`, and any
  row/detail strings. Then push the CloudKit schema (below).
- **Add a whole new event type** (e.g. sleep) → follow the diaper/pump pattern:
  model + enums → register entity & `Baby` relationship in `makeModel` →
  `XxxService` → `EditXxxView` (draft create/edit) → `XxxListView` (recent/edit/delete)
  → a `NewbornEvent` case + a dashboard `RecentTile` and quick-log button.
- **CloudKit schema:** new entities/attributes are additive. In the **Development**
  environment the container creates the new record types/fields automatically on first
  sync from an iCloud-signed device — no manual step (the `-InitializeCloudKitSchema`
  launch arg only forces/verifies that push early, e.g. for CI). The non-automatic step
  is **Production**: promote the schema Development → Production in the CloudKit Console
  before any TestFlight/release build (additive only — prod fields can't be removed/renamed).
- **In-app copy:** no em-dashes in user-facing strings (comments are fine).
