# Out for Delivery — Newborn-Care Feature Plan

This document covers the **post-birth newborn-care** features as numbered user stories. It is the companion to `Feature-Plan.md`, which covers the labor / contraction-timing app. Read that document first for personas, conventions, and the existing (shipped) epics 1–6.

Epic numbering continues from `Feature-Plan.md`: shipped labor epics are 1–6; newborn epics begin at 7.

## Conventions specific to this plan

- **Manual entry is first-class.** Unlike the contraction timer (which forbids backfill), newborn events are routinely logged after the fact. Every newborn event type supports adding a past event with a custom time and editing the time/details of any logged event. This overrides the no-backfill rule for these features only.
- **Caregiver attribution.** Because the dataset is shared between caregivers (Epic 13), every logged event records *who* logged it.
- **Status:** **Implemented** (built and compiling), **Planned** (agreed, not yet built), or **Proposed** (placeholder, no agreed stories yet). Individual stories may carry a ✅ (done) or 🚧 (partial) marker.

### Additional persona note

These epics center on the **caregiver** persona (defined in `Feature-Plan.md`) — either parent or another helper caring for the newborn after birth.

---

## Epic 7 — App Modes & Baby Profile — *Implemented*

The foundation for newborn tracking: a baby profile that anchors all newborn data and governs which mode the app is in.

> **Implementation note (2026-06-25):** Built and compiling. New `Baby` SwiftData model (CloudKit-safe) registered in the app's shared store. `RootView` routes between labor mode (`ContentView`) and newborn mode (`NewbornModeView`) based on an `@Observable AppState` (mode + active baby, persisted). `BabyFormView` (create/edit), `BabyManagerView` (list/select/archive), and a shared `ModeMenuButtons` (in both toolbars) complete the flow. Newborn mode is a placeholder dashboard until the event-type epics land. Verified via simulator build (on-device build blocked by an unrelated Xcode signing/account issue).

7.1. ✅ As a caregiver, I want to create a baby profile (name, birth date and time), so that the app has an anchor for all newborn data.

7.2. ✅ As a caregiver, I want creating my first baby profile to switch the app into newborn mode, so that the app naturally transitions from labor tracking to newborn care after birth.

7.3. ✅ As a parent expecting again, I want to switch back to contraction-timer mode once I already have a baby profile, so that I can time labor for a subsequent pregnancy.

7.4. ✅ As a caregiver, I want to toggle freely between labor mode and newborn mode once at least one baby profile exists, so that I can move between timing contractions and tracking my newborn as my needs change.

7.5. ✅ As a caregiver of more than one baby, I want to create multiple baby profiles (e.g. twins or a new sibling), so that each baby's data is tracked separately.

7.6. ✅ As a caregiver with multiple babies, I want to select which baby an event applies to (and see a clear indication of the active baby), so that I never log a feed or diaper against the wrong child. *(Active-baby selection + picker built; per-event baby assignment lands with the event-type epics.)*

7.7. ✅ As a caregiver, I want to edit or archive a baby profile, so that I can fix details or retire a profile I no longer actively track.

7.8. 🚧 As a caregiver, I want all newborn events to belong to a specific baby, so that switching the active baby filters the dashboard, timeline, and logs to that baby. *(Active-baby plumbing in place; takes full effect once Feeds/Diapers/Pump events exist to scope.)*

## Epic 8 — Feed Tracking — *In progress (phased)*

Covers timed nursing and bottle feeds, with "time since last feed" as the headline newborn metric and a resetting **feed-on-demand reminder** as the priority alerting feature.

> **Implementation phasing (2026-06-25):** Building "reminder first." **Phase 1 (in progress)** delivers the minimal feed log needed to drive the reminder — one-tap *Log Feed*, time-since-last, edit/delete (slices of 8.8–8.9) — plus the full feed-on-demand reminder (8.12–8.17) on AlarmKit, with per-baby on/off + interval stored on `Baby`. It also includes a **feed-kind scaffold** (Bottle / Breast / Other on `Feed`), **bottle volume (8.6)** — an optional amount per bottle feed, entered/displayed in an app-wide preferred unit (ml or oz, stored canonically as ml; preference in `AppState`) — and **breast nursing minutes per side (8.2)**, entered manually in the feed editor (left/right minutes on `Feed`). New types: `Feed` model (+ `FeedKind`, `VolumeUnit`), `FeedService`, `FeedReminderManager` (+ shared `FeedReminderMetadata` / `StopFeedReminderIntent`), an AlarmKit countdown widget in the LiveActivity extension, and `FeedSectionView` / `EditFeedView` in the dashboard. **Now built (a later feed phase):** the *live* nursing timer + start/stop haptics (8.1, 8.4, 8.5) and next-side suggestion (8.3) in `NursingTimerView` / `NursingSession`, plus formula vs expressed-breast-milk (8.7) and per-feed notes (8.11). Feeding plan & targets (8.18–8.26) remain deferred as below.

### Nursing (timed)

8.1. ✅ As a caregiver, I want to start and stop a nursing session with a single tap, so that I can time a feed in real time the way the contraction timer works. *(`NursingTimerView` / `NursingSession`; tap a side to start, the running side to pause, reached from the dashboard "Nursing" quick action. Stop & save commits one breast feed.)*

8.2. ✅ As a caregiver, I want to record which side(s) were used (left, right, or both) for a nursing session, so that I can alternate sides and report this to a lactation consultant or pediatrician. *(The live timer records per-side time; the feed editor's manual left/right minute steppers remain for after-the-fact entry.)*

8.3. ✅ As a caregiver, I want the app to suggest which side to start on next based on the last session, so that I don't have to remember which side was used last. *(`NursingSession.suggestedStartSide` highlights the side opposite the heavier one in the last nursing feed.)*

8.4. ✅ As a caregiver, I want a haptic confirmation on start/stop of a nursing session, so that I know the tap registered without watching the screen while holding the baby. *(`.sensoryFeedback(.impact, …)` on every start/switch/pause; `.success` on save.)*

8.5. ✅ As a caregiver, I want a live count-up of the current nursing session's duration, so that I can see how long the baby has been feeding. *(Per-side and total `Text(timerInterval:)` count-ups on `NursingTimerView`.)*

### Bottle

8.6. 🚧 *(Phase 1, in progress)* As a caregiver, I want to log a bottle feed by volume (in my preferred unit, ml or oz), so that I have an accurate record of how much the baby consumed. *(Volume is an optional amount on a bottle-kind feed; unit is an app-wide preference, stored canonically as ml.)*

8.7. ✅ As a caregiver, I want to mark a bottle feed as formula or expressed breast milk, so that I can distinguish the two in my records. *(Built in the improved feed sheet: `BottleContent` on `Feed`, Formula / Breast milk selector in `EditFeedView`.)*

### Shared feed behavior

8.8. As a caregiver, I want to see the time since the last feed (any type), so that I know when the baby is likely due to feed again — the newborn equivalent of the contraction interval.

8.9. As a caregiver, I want to add a past feed with a custom time and edit any logged feed, so that I can record feeds I forgot to log live or correct mistakes.

8.10. As a caregiver, I want each feed to record which caregiver logged it, so that a hand-off partner can see who fed the baby last.

8.11. ✅ As a caregiver, I want to add an optional note to a feed, so that I can capture details like fussiness, spit-up, or latch quality. *(Note field in `EditFeedView`, stored on `Feed.note`.)*

### Feed-on-demand reminder — *Phase 1, in progress* 🚧

This is the priority alerting feature for newborn mode. Rather than a fixed clock schedule, it tracks feeds *on demand*: each logged feed (re)arms a countdown to the next feed, and if the interval lapses without a feed, the app alerts the caregiver — including the ability to wake a sleeping caregiver.

> **Note on the calm ethos.** The labor side of the app is deliberately calm and never alarms (`Feature-Plan.md` Epic 3). The feed-on-demand reminder is a deliberate, scoped exception for newborn care, where going too long without a feed matters clinically. It is still under the caregiver's control: the reminder can be disabled, and its interval adjusted.

8.12. As a caregiver, I want logging a feed to automatically arm a "feed-on-demand" countdown (defaulting to 3 hours) to the next feed, so that I'm reminded if the baby goes too long without feeding.

8.13. As a caregiver, I want logging a new feed before the countdown lapses to reset it to a full interval from the latest feed, so that the reminder always measures time since the most recent feed.

8.14. As a caregiver, I want the reminder — when the interval lapses with no feed logged — to alert me with a time-sensitive, alarm-style alert that can break through silent mode and Focus and wake me (like the Clock app's alarm), so that a sleeping caregiver doesn't miss a feed.

8.15. As a caregiver, I want to adjust the on-demand interval (default 3 hours), so that it matches my baby's feeding needs or my provider's guidance.

8.16. As a caregiver, I want to turn the feed-on-demand reminder on or off, and to snooze or dismiss the alert when it fires, so that I stay in control of when and whether the app alerts me.

8.17. As a caregiver, I want to see the time remaining until the next feed reminder (on the dashboard and feed screen), so that I know at a glance when the next alert will fire.

### Feeding plan & targets — *Deferred (post-initial)*

> **Deferred (2026-06-25):** Provider-prescribed feeding *schedules* and *volume targets* are pushed back past the initial newborn release. The resetting feed-on-demand reminder above covers the core "don't go too long without a feed" need; fixed clock schedules and age-based volume targets are a later enhancement. Stories retained below for when this is brought back into scope.

These let a caregiver record what a lactation consultant or pediatrician recommended, reference it easily, and compare it to what actually happened. All plan values are user-entered guidance, never medical advice from the app (consistent with the disclaimer ethos in `Feature-Plan.md` Epic 6).

8.18. As a caregiver, I want to define a planned feeding schedule as specific clock times (e.g. 8am, 11am, 2pm), so that I can follow a fixed daily schedule my provider recommended.

8.19. As a caregiver, I want to alternatively define the plan as a target interval between feeds (e.g. every 3 hours), so that I can follow an interval-based recommendation instead of fixed times.

8.20. As a caregiver, I want the app to show the next planned feed time, easily referenceable at a glance (on the dashboard and feed screen), so that I always know when the baby is due to feed next.

8.21. As a caregiver, I want the next-feed time derived correctly for whichever plan type I use — the next scheduled clock time, or last-feed-plus-interval — so that the reference stays accurate however my provider phrased it.

8.22. As a caregiver, I want to set expected feed volumes that change by the baby's age (e.g. per day or per week), so that the target reflects how a newborn's intake grows over time as my provider prescribed.

8.23. As a caregiver, I want the app to automatically surface the volume target that applies to my baby's current age, so that I see the right number without recalculating it myself as the baby grows.

8.24. As a caregiver, I want to compare actual intake against the target (per feed and/or daily total), so that I can see whether the baby is meeting the recommended amount.

8.25. As a caregiver, I want to optionally enable local reminders when a planned feed is due, so that I don't lose track of the schedule during sleep-deprived days. *(Opt-in only; off by default, consistent with the app's calm, no-alarm default.)*

8.26. As a caregiver, I want to edit the feeding plan and volume targets whenever my provider revises them, so that the plan stays current as recommendations change.

## Epic 9 — Pump Tracking — *Implemented (live timer deferred)*

> **Implementation note (2026-06-27):** Built. `Pump` model (left/right/combined ml +
> duration + note), `PumpService`, `EditPumpView` (per-side or combined entry, manual
> duration), and `PumpListView` (recent / add-past / edit / delete). Surfaced on the
> dashboard (last pump + today's expressed total). The live "Time it" session timer
> (9.2) is now built — an inline count-up in `EditPumpView` that fills the minutes field.

Pump sessions only — no milk-inventory/storage tracking in this scope.

9.1. As a caregiver, I want to log a pump session recording the volume expressed per side (left, right, or combined total), so that I can track my pumping output.

9.2. ✅ As a caregiver, I want to record the duration of a pump session (timed live or entered manually), so that I have a complete record of the session. *(Inline "Time it" live count-up in `EditPumpView` fills the minutes field on stop; manual entry still available.)*

9.3. As a caregiver, I want to see the time since my last pump session, so that I can keep a consistent pumping schedule.

9.4. As a caregiver, I want to add a past pump session with a custom time and edit any logged session, so that I can record sessions I forgot to log live or fix mistakes.

9.5. As a caregiver, I want each pump session to record which caregiver logged it, so that attribution is consistent across the shared dataset.

> **Out of scope (proposed, not planned):** milk inventory / storage tracking (fridge & freezer stash, oldest-first usage, bottles drawing down stored milk). Revisit as a future epic if needed.

## Epic 10 — Diaper Tracking — *Implemented*

> **Implementation note (2026-06-27):** Built. `Diaper` model (`DiaperKind` wet/dirty/both,
> `DiaperColor`, `DiaperConsistency`, note), `DiaperService` (today's wet/dirty counts,
> time-since-last), `EditDiaperView` (color swatches + consistency for dirty), and
> `DiaperListView` (recent / add-past / edit / delete). Surfaced on the dashboard
> (last change + today's wet/dirty totals).

The lowest-friction feature; matters clinically in the newborn weeks for confirming adequate intake.

10.1. As a caregiver, I want to log a diaper change as wet, dirty, or both in as few taps as possible, so that logging never interrupts the change itself.

10.2. As a caregiver, I want to optionally record color and consistency for a dirty diaper, so that I can answer pediatrician questions and watch for concerning changes.

10.3. As a caregiver, I want to see the time since the last diaper change and a count of today's wet/dirty diapers, so that I can confirm the baby is getting enough (a common newborn-week check).

10.4. As a caregiver, I want to add a past diaper change with a custom time and edit any logged change, so that I can record changes I forgot to log live or fix mistakes.

10.5. As a caregiver, I want each diaper change to record which caregiver logged it, so that attribution is consistent across the shared dataset.

10.6. As a caregiver, I want to add an optional note to a diaper change, so that I can flag something unusual (e.g. blood, rash).

## Epic 11 — Newborn Dashboard & Timeline — *Implemented (growth tab stubbed)*

> **Implementation note (2026-06-27):** The dashboard (`NewbornModeView` /
> `BabyDashboardView`) is built per design frame 01 — recent feed/diaper/pump tiles
> with time-since (11.1), quick-log buttons (11.2), daily totals (11.6), per-event
> attribution in the logs (11.7), and tap-through to each per-type log for view/edit/
> delete (11.5, per type).
>
> **Update (2026-06-27):** Newborn mode now uses a native iOS 26 Liquid Glass bottom
> nav (design frames 01/07): tabs **Home**, **Timeline**, and **Growth** (a stub until
> Epic 12). The **unified cross-type timeline** is built (`TimelineView.swift` /
> `BabyTimelineView`, design frame 07): all events merged newest-first and grouped by
> day (11.3), type-filter chips All/Feeds/Diapers/Pumps (11.4), tap-to-edit and
> swipe-to-delete via the existing editors/services plus an "Add past" menu for any
> type (11.5), and per-entry caregiver attribution (11.7). The design's **Family** tab
> is deferred (stays in the More menu); growth (mentioned in 11.3) lands with Epic 12.

The home screen of newborn mode, tying every feature together.

11.1. As a caregiver, I want a dashboard summarizing the most recent activity (e.g. last feed, last diaper, last pump and how long ago each was), so that I can assess the baby's status at a glance.

11.2. As a caregiver, I want quick-action buttons on the dashboard to start a feed, log a diaper, or log a pump, so that I can record common events without digging through menus.

11.3. ✅ As a caregiver, I want a unified chronological timeline of all events (feeds, diapers, pumps, growth) for the active baby, so that I can review the day's history in one place. *(Feeds/diapers/pumps merged, newest-first, grouped by day. Growth events join when Epic 12 lands.)*

11.4. ✅ As a caregiver, I want to filter the timeline by event type, so that I can focus on, say, just feeds when reviewing patterns.

11.5. ✅ As a caregiver, I want to tap any timeline entry to view, edit, or delete it, so that the timeline is also where I correct records. *(Tap to edit via the per-type editor; swipe to delete.)*

11.6. As a caregiver, I want at-a-glance daily totals (feeds, diapers, pump volume), so that I have the summary figures pediatricians often ask for.

11.7. ✅ As a caregiver, I want each timeline entry to show which caregiver logged it, so that hand-offs between caregivers are clear. *(Each entry shows the "logged by" attribution via `LoggedByLabel`.)*

## Epic 12 — Growth Tracking — *Planned*

Periodic measurements tracked against pediatric visits.

12.1. As a caregiver, I want to record the baby's weight and length on a given date, so that I can track growth over time.

12.2. As a caregiver, I want to optionally record head circumference, so that I capture the full set of measurements pediatricians take.

12.3. As a caregiver, I want to view my baby's measurements over time as a simple chart, so that I can see the growth trend at a glance.

12.4. As a caregiver, I want to choose my preferred units (kg/g or lb/oz; cm or in), so that measurements match what my provider uses.

12.5. As a caregiver, I want to edit or delete a recorded measurement, so that I can correct entry mistakes.

12.6. As a caregiver, I want to optionally tag a measurement as taken at a pediatric visit, so that I can distinguish official measurements from at-home ones.

## Epic 13 — Multi-Caregiver Shared Sync — *Planned*

Sharing one household's data across multiple caregivers' separate iCloud accounts. This is an architectural shift from the labor app's private-only sync (see `Feature-Plan.md` Epic 5).

> **Technical design:** see `Multi-Caregiver-Sharing-Design.md` for the full implementation design — the SwiftData → `NSPersistentCloudKitContainer` stack migration, the single shared `Household` anchor (all data, including labor history, shared as one share), `ShareLink` invite + accept flow, the Family / Caregivers access list, caregiver attribution, and the generic CSV import/export framework.

13.1. As a parent, I want to invite my partner or another caregiver to share my baby's data, so that we both log and view events from our own devices.

13.2. As a caregiver, I want to accept an invitation to a shared baby and then see and contribute to the same dataset, so that our records stay unified.

13.3. As a caregiver, I want changes I make to sync to all other caregivers reliably (and work offline, reconciling later), so that the shared record stays consistent without anyone babysitting the sync.

13.4. As a parent, I want to see who has access to my baby's data and revoke access, so that I stay in control of who can see and edit it.

13.5. As a caregiver, I want every event attributed to the caregiver who logged it across all devices, so that we can tell who did what during hand-offs.

13.6. As a parent, I want the app to keep working with a single caregiver / private sync if I never invite anyone, so that sharing is optional and the app is useful solo.

---

## Proposed (placeholders — no agreed stories yet)

These were discussed but deferred. Stories to be added if/when brought into scope.

- **Epic 14 — Sleep Tracking** *(proposed)* — Start/Stop sleep sessions, "time since last sleep" / awake-window tracking; a Live Activity candidate. TBD.
- **Epic 15 — Medications & Vitamins** *(proposed)* — recurring meds/vitamins (e.g. vitamin D drops) with "last given" tracking and optional reminders. TBD.

_Other lighter ideas raised but not yet scoped: tummy time, milestones, pediatric appointments, notes/photos._
