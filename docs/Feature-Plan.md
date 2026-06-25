# Out for Delivery — Feature Plan

This document tracks features for **Out for Delivery** as numbered user stories. It complements the implementation spec (`ContractionTracker-Spec.md`), which covers the contraction-timer MVP in technical detail. This document is intentionally implementation-agnostic: it captures *what* users want to accomplish and *why*, not *how* it is built.

## How to read this document

- Stories are grouped into **Epics**. Each epic has a stable number; each story within it is numbered `E.S` (Epic.Story).
- Stories follow the form: *As a [user], I want [capability], so that [benefit].*
- Acceptance criteria are listed where they clarify scope.
- Status of an epic: **Shipped** (in the current MVP), **Planned**, or **Proposed** (under discussion, not yet specced).

### Users (personas)

- **Birthing parent** — the primary user, timing their own contractions, often mid-labor and unable to give the screen full attention.
- **Partner / support person** — may operate the app on the parent's behalf, read numbers aloud to a provider, or take over the newborn-care tracking after birth.
- **Caregiver** — anyone (parent, partner, relative) tracking the newborn's feeds, diapers, sleep, etc. after delivery.

---

## Epic 1 — Contraction Timing (Core Loop) — *Shipped*

The central labor-timing experience.

1.1. As a birthing parent, I want the app to open directly to the contraction log with a large, obvious Start/Stop control, so that I can begin timing immediately without navigating menus mid-contraction.

1.2. As a birthing parent, I want to start timing a contraction with a single tap, so that I capture its start the moment it begins.

1.3. As a birthing parent, I want to stop timing a contraction with a single tap, so that its duration is recorded accurately.

1.4. As a birthing parent, I want to cancel an in-progress contraction I started by mistake, so that a false start does not pollute my timing history.

1.5. As a birthing parent, I want every Start/Stop/Cancel action confirmed with a haptic, so that I know the tap registered without having to look closely at the screen.

1.6. As a birthing parent, I want to see a live count-up of the current contraction's duration while it is happening, so that I know how long this one is lasting.

1.7. As a birthing parent, I want to see a live count-up of the time since my last contraction started while resting, so that I can sense how my contraction frequency is developing.

1.8. As a birthing parent, I want timer digits shown in fixed-width type, so that the numbers don't jitter or reflow the layout as they tick.

## Epic 2 — Contraction Log & History — *Shipped*

2.1. As a birthing parent, I want a chronological log of all my contractions (newest first), so that I can review the session at a glance.

2.2. As a birthing parent, I want each log entry to show its number, start time, duration, and interval since the previous contraction, so that I have the exact figures a provider may ask for.

2.3. As a birthing parent, I want to swipe to delete any logged contraction, so that I can remove mistakes or spurious entries.

2.4. As a birthing parent, I want the interval of the following contraction to recompute automatically when I delete one, so that my frequency figures stay correct.

2.5. As a birthing parent, I want to edit a logged contraction, so that I can correct an inaccurate start or end time.

2.6. As a birthing parent, I want a "Clear all" action (with confirmation), so that I can reset the log when I need a fresh start.

## Epic 3 — Pattern Readout (5-1-1) — *Shipped*

3.1. As a birthing parent, I want a quiet, passive 5-1-1 readout showing my average interval and duration and whether the pattern is met, so that I have an at-a-glance sense of labor progress.

3.2. As a birthing parent, I want the pattern readout to never alarm, notify, or instruct me to act, so that the app stays a calm timing aid and I rely on my provider's guidance for decisions.

3.3. As a birthing parent, I want to optionally choose a different rule (e.g. 4-1-1, 3-1-1, or custom), so that the readout matches my own provider's instructions.

## Epic 4 — Live Activity (Lock Screen & Dynamic Island) — *Shipped*

4.1. As a birthing parent, I want a persistent Live Activity on the Lock Screen and Dynamic Island, so that I can time contractions without unlocking or opening the app.

4.2. As a birthing parent, I want to start/stop a contraction from the Live Activity button, so that I can keep timing while the phone is locked or in use elsewhere.

4.3. As a birthing parent, I want the Live Activity to show the same live counter as the app (current duration when contracting, time-since-last when resting), so that the Lock Screen is a faithful mirror of the app.

4.4. As a birthing parent, I want to show or hide the Live Activity from the app, so that I control when it appears on my Lock Screen.

4.5. As a birthing parent, I want the app to recover gracefully if the Live Activity expires (offering a "tap to restart"), so that a long quiet stretch doesn't silently leave me without the Lock Screen control.

## Epic 5 — Data, Sync & Export — *Shipped*

5.1. As a birthing parent, I want my data stored locally and to work fully offline, so that the app never fails me due to a lost signal during labor.

5.2. As a birthing parent, I want my data backed up and synced through my own private iCloud, so that it is safe and available across my devices without any third party seeing it.

5.3. As a birthing parent, I want the app to keep working when iCloud is unavailable (signed out or offline), with only a quiet indicator, so that sync issues never block the core timing loop.

5.4. As a birthing parent, I want to export my contraction history as a CSV via the share sheet, so that I can save or send my data outside of iCloud if I choose.

## Epic 6 — Onboarding, Safety & Accessibility — *Shipped*

6.1. As a birthing parent, I want a brief, dismissible disclaimer on first launch (and a small Info item), so that I understand this is a timing aid, not a medical device.

6.2. As a birthing parent, I want to be told in one line where my data is stored (private iCloud, can be turned off), so that I understand my privacy from the start.

6.3. As a birthing parent using VoiceOver, I want the primary control and each log row clearly labeled, so that I can operate the app without sight.

6.4. As a birthing parent, I want the app to support Dynamic Type and remain legible with Reduce Transparency on, so that it adapts to my accessibility needs.

6.5. As a birthing parent, I want large tap targets that tolerate imprecise taps, so that I can use the core controls reliably mid-contraction.

---

## Newborn-Care Features

Post-birth newborn tracking (baby profile, feeds, pumping, diapers, dashboard, growth, and multi-caregiver sync) lives in its own companion document: **[`Newborn-Care-Features.md`](./Newborn-Care-Features.md)**. Epic numbering continues there from 7.
