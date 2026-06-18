# Widget Extension Setup

The app target is wired and runnable on its own — Start/Stop, log, CSV
export, 5-1-1 readout, and CloudKit sync all work in the app. The Live
Activity, however, requires a Widget Extension target, which has to be
added through Xcode's UI.

## Steps

1. **File → New → Target… → Widget Extension**
   - Product name: `OutForDeliveryWidgets`
   - Bundle id: `com.<your-name>.outfordelivery.widgets`
   - **Check** "Include Live Activity".
   - Embed in the app target.

2. **Delete** the boilerplate widget files Xcode adds
   (`OutForDeliveryWidgets.swift`, `OutForDeliveryWidgetsBundle.swift`,
   `OutForDeliveryWidgetsLiveActivity.swift`, the AttributeSet stuff, etc.).

3. **Drag in** the two files from this folder (`Widgets/`) into the new
   target's group:
   - `OutForDeliveryWidgetsBundle.swift`
   - `ContractionLiveActivity.swift`

4. In the project navigator, click **`ContractionActivityAttributes.swift`**
   (in the app group). In the File Inspector → Target Membership, check
   the **widget extension** box (in addition to the app target).

5. Repeat step 4 for **`ToggleContractionIntent.swift`** — also needs
   membership in both the app target and the widget extension target.

6. Make sure both targets' Deployment Target is iOS 26.

7. Build the widget extension scheme once to verify it compiles.

## Why this can't be automated

The `.xcodeproj` file format isn't safe to edit programmatically without
breaking Xcode's project model. Adding a target, configuring its Info.plist,
linking frameworks, and setting target membership all have to go through
Xcode's UI to stay correct.

## After the widget exists

- The app auto-starts the activity on the first Start tap.
- The toolbar menu's "Show on Lock Screen" / "Hide" controls it.
- "Clear all" ends it.
- If the system 8-hour cap lapses, the next foreground open re-requests
  a fresh one and shows the "Live Activity expired" banner if needed.
