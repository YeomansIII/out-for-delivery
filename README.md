# Out for Delivery

A single-purpose iOS app for timing labor contractions, with a persistent Live Activity you can operate straight from the Lock Screen and Dynamic Island. It wraps the experience in the friendly visual language of a package-delivery tracker — while keeping every medical number exact and plainly labeled.

Built for one job, done well: open the app, hit a big **Start** / **Stop** button, and read back interval and duration to your provider without fumbling.

> ⚠️ **Not a medical device.** Out for Delivery is a timing aid only. It gives no medical advice, alarms, or instructions to act. Always follow your provider's guidance, and in an emergency call your provider or emergency services.

---

## Features

- **One-tap timing.** A large, unmissable Start/Stop control opens directly on launch, with haptic confirmation on every action so you don't have to look.
- **Live Activity + Dynamic Island.** Start or stop a contraction from the Lock Screen without unlocking or opening the app. A self-updating counter shows the current contraction's duration while contracting, and time since the last contraction started while resting.
- **The numbers, always exact.** Duration and start-to-start interval shown in `mm:ss` with monospaced digits, alongside a quiet, passive **5-1-1 readout** (configurable to 4-1-1 / 3-1-1) — a glanceable status, never an alarm.
- **Session-aware log.** Contractions are grouped into implicit sessions, with average stats and pattern analysis. Edit, delete, cancel an in-progress contraction, or clear all.
- **Local-first with private iCloud sync.** Works fully offline; the on-device SwiftData store is the source of truth and mirrors to your **private CloudKit database** for backup and cross-device access. No third-party servers, accounts, analytics, or ads.
- **CSV export.** Share your full timing history via the system share sheet — the only path that moves data outside your own iCloud.
- **Themed, but legible.** Package-tracker flavor on ambient status text ("In transit", "Out for delivery", "Arriving soon"); the critical controls and medical numbers stay literal and plain.

## Requirements

- **iOS 26.0+** (iPhone 14 Pro or newer recommended for Dynamic Island + interactive Live Activity buttons)
- **Xcode 26+**, Swift 6 (strict concurrency)
- An Apple Developer account and an iCloud-enabled CloudKit container for sync

## Tech stack

- **SwiftUI** with the Liquid Glass design system (functional layer only; content stays solid and legible)
- **SwiftData** backed by **CloudKit** (`ModelConfiguration` with CloudKit mirroring to the private database)
- **Observation** (`@Observable`) for state — no Combine
- **ActivityKit** Live Activity hosted in a **WidgetKit** extension
- **App Intents** (`LiveActivityIntent`) for Lock Screen buttons that run in-process and write directly to the shared store

## Project structure

| Path | Purpose |
|---|---|
| `Out for Delivery/` | Main app target (SwiftUI views, services, model) |
| `Out for Delivery/Contraction.swift` | SwiftData `@Model` (CloudKit-compatible) |
| `Out for Delivery/ContractionService.swift` | Single source of truth for Start/Stop/Cancel/Delete |
| `Out for Delivery/AppData.swift` | Shared CloudKit-backed `ModelContainer` |
| `Out for Delivery/ToggleContractionIntent.swift` | `LiveActivityIntent` for Lock Screen / Dynamic Island |
| `Out for Delivery/ContractionActivityAttributes.swift` | Live Activity data contract (shared with the extension) |
| `Out for Delivery/PatternAnalyzer.swift` · `SessionGrouper.swift` | 5-1-1 readout and session grouping |
| `LiveActivity/` · `Widgets/` | Widget extension hosting the Live Activity UI |
| `ContractionTracker-Spec.md` | Full implementation spec |

## Building

1. Open `Out for Delivery.xcodeproj` in Xcode 26 or newer.
2. Set your development team and a unique bundle identifier for both the app and the widget extension targets.
3. Configure the **iCloud → CloudKit** capability with a container (e.g. `iCloud.com.yourname.outfordelivery`), and ensure **Background Modes → Remote notifications** is enabled.
4. Build and run on a physical device (Liquid Glass specular highlights and Live Activities don't fully render in the Simulator).

> Before a TestFlight or release build, promote the CloudKit schema from Development to **Production** in the CloudKit Console, or synced data won't appear.

## How the timing works

- **Duration** — length of a single contraction (`endDate − startDate`).
- **Interval / frequency** — time from the **start of one contraction to the start of the next** (includes the rest period). This is the "time since last contraction" the app surfaces.
- **5-1-1** — contractions ~5 minutes apart (start-to-start), each lasting ≥1 minute, sustained for ≥1 hour. Shown as a passive readout only; your provider's guidance always overrides.

## Privacy

Contraction data is stored on-device and synced only to **your** private iCloud account via CloudKit — no app-operated servers, no third parties. iCloud can be turned off in Settings to keep data on-device only; the app remains fully functional offline. The CSV export is the only feature that moves data outside iCloud, and only when you choose to share it.

## License

See [LICENSE](LICENSE).
