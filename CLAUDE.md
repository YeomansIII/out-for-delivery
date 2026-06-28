# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

**Out for Delivery** is a single-purpose iOS app (iOS 26+, Swift 6 strict concurrency) that started as a labor **contraction timer** with a Lock Screen / Dynamic Island Live Activity, and is growing a second **newborn-care tracking** mode for after the birth. It is themed as a package-delivery tracker but keeps all medical numbers exact and literal. It is explicitly **not a medical device**.

In **labor mode**, the contraction experience stays calm and passive — never add alarms, notifications, or instructions to act; the pattern readout only informs. **Newborn mode** has one deliberate, scoped exception: the per-baby, opt-in **feed-on-demand reminder** (AlarmKit), which fires an alarm-style alert that can wake a caregiver because going too long without a newborn feed matters clinically. It is off by default and fully caregiver-controlled (toggle + adjustable interval). Outside that one feature, newborn mode stays passive too — don't add other alarms or nagging notifications.

## Build, run, test

Prefer the `xcode-tools` MCP commands over the command line.

- **Build**: `BuildProject` (active scheme is `Out for Delivery`). The second scheme `LiveActivityExtension` builds the widget alone.
- **Run**: `RunProject` — must be a **physical device** for Live Activities and Liquid Glass; the Simulator does not fully render either.
- **Tests**: `RunAllTests`, or `RunSomeTests` for a subset. Tests use the **Swift Testing** framework (`Out for DeliveryTests`); UI tests use XCUIAutomation (`Out for DeliveryUITests`).
- **Fast checks**: `XcodeRefreshCodeIssuesInFile` for live diagnostics on a single Swift file; `RunCodeSnippet` to try logic in-context — both far faster than a full build.

CloudKit note: before any TestFlight/release build, promote the CloudKit schema from Development → Production in the CloudKit Console or synced data won't appear.

## Architecture

### Two modes, one router
`RootView` is the top-level router. It switches between `ContentView` (labor / contraction timer) and `NewbornModeView` (baby tracking) based on `AppState.mode`. **With zero non-archived babies the app always forces labor mode**, regardless of the stored preference (`RootView.effectiveMode`). Creating the first baby flips to newborn mode (`AppState.onBabyCreated`). `RootView` also owns the baby sheets and keeps `activeBabyID` pointed at a real baby via `reconcileActiveBaby()`.

Newborn mode (`NewbornModeView`) is a native Liquid Glass `TabView` bottom nav: **Home** (`BabyDashboardView`), **Timeline** (`BabyTimelineView` in `TimelineView.swift` — the unified cross-type log of feeds/diapers/pumps), and **Growth** (a stub until Epic 12). Each tab has its own `NavigationStack` and shares the top toolbar (baby picker + "More" menu with mode switch / Family / manage babies). Family is still a sheet from that menu, not yet a tab. (The view type is `BabyTimelineView`, not `TimelineView`, to avoid shadowing SwiftUI's `TimelineView`.)

### State singletons (not environment-injected)
Three `@MainActor` singletons are referenced directly as `.shared` rather than injected through the SwiftUI environment — this is deliberate, because sheets do not reliably inherit a custom `@Observable` from the environment:
- **`AppData.shared`** — owns the one CloudKit-backed `ModelContainer` (`Schema([Contraction, Baby])`, `cloudKitDatabase: .automatic`). Falls back to a local-only store if CloudKit discovery fails, so the app always works offline.
- **`ContractionService.shared`** — the **single source of truth** for all contraction mutations (start/stop/cancel/delete/edit/clear). Uses `container.mainContext` (the *same* context SwiftUI injects for `@Query`) — do **not** introduce a second context, or edits/deletes will desync and deleted rows can be resurrected on save. Every mutation calls `recompute()` then refreshes the Live Activity.
- **`AppState.shared`** — app mode + active baby + top-level sheet, persisted to `UserDefaults`.

### Contraction timing model
- `Contraction` and `Baby` are CloudKit-compatible `@Model`s: **no `@Attribute(.unique)`**, and **every stored property must be optional or have a default** (CloudKit mirroring requires this). Uniqueness of `id` is enforced in app logic, not the schema.
- **Duration** = `endDate − startDate` (one contraction). **Interval/frequency** = start-of-one to start-of-next (includes rest). An in-progress contraction has `endDate == nil` (`isInProgress`).
- `SessionGrouper` derives **sessions** (never persisted, recomputed on every change) from the chronological log: a new session begins on the first contraction, on a start-to-start gap > 2h (`autoBreakSeconds`), or on a manual `startsNewSession` flag. `currentSession(from:)` returns `[]` when between sessions, which is how stats reset cleanly.
- `PatternAnalyzer.evaluate` computes the passive **5-1-1 readout** (avg interval/duration + whether the pattern is met) over the *current session only*.
- `ContractionService.Snapshot` is the immutable value that both the app UI and the Live Activity render from.

### Live Activity & Lock Screen control
- `LiveActivityManager` owns the single `Activity<ContractionActivityAttributes>` lifecycle (start/update/end). The widget UI lives in the `LiveActivity/` target.
- `ToggleContractionIntent` is a `LiveActivityIntent` **shared between the app and widget targets** (check Target Membership for both). Its `perform()` runs *in the app's process* and calls `IntentDispatcher.toggle`, a closure the app registers at launch in `Out_for_DeliveryApp.init()`. This keeps `ContractionService` out of the widget target.
- **Known platform limit**: the Lock Screen card always requires device unlock for a non-media `LiveActivityIntent`, even with `authenticationPolicy = .alwaysAllowed`. This is by-design in iOS, not a bug — do not try to "fix" it in code.

## Conventions

- SwiftUI + Observation (`@Observable`); **no Combine** — use async/await.
- Liquid Glass is functional layer only; medical numbers and primary controls stay solid, literal, and legible (monospaced digits for timers). Use `DocumentationSearch` for Liquid Glass / new SwiftUI / FoundationModels APIs rather than assuming.
- Keep changes scoped to the request; don't refactor unrelated areas.

## Docs

`docs/` holds the design specs and the numbered user-story feature plan. `docs/Feature-Plan.md` (Epics 1–6, labor) and `docs/Newborn-Care-Features.md` (Epic 7+, newborn) describe *what/why*; `docs/ContractionTracker-Spec.md` is the technical MVP spec; `docs/Design-Map.md` maps the "Poops Pumps Feeds" design frames to the code. Newborn-care tracking is substantially built: feeds (plus the feed-on-demand reminder), diapers, and pumps each have a model / service / editor / log, surfaced through the newborn dashboard and the unified Timeline. The main unbuilt newborn epics are **Growth** (Epic 12 — the Growth tab is a stub) and **multi-caregiver sharing** (Epic 13).
