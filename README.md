# Befoor

An iOS app that reads your calendar and schedules a gentle alarm a configurable number of minutes before each appointment.

## Features

- **Configurable lead time** — default 7 minutes, adjustable 1–60
- **Calendar filtering** — choose which calendars to monitor (leave all unchecked for all)
- **Keyword ignore list** — skip events whose titles contain words like "lunch"
- **Weekend skip** — optionally suppress alarms on Saturdays and Sundays
- **Smart tracking** — if an event moves, Befoor cancels the old alarm and creates a new one
- **Background sync** — checks for calendar changes periodically; also syncs on every app open
- **Soothing sounds** — choose from bundled chimes or the system default

---

## Xcode Setup

### 1 — Create the project

1. Open Xcode → **File › New › Project**
2. Choose **iOS › App**
3. Product Name: **Befoor**
4. Interface: **SwiftUI** | Language: **Swift**
5. Uncheck "Include Tests" (add later if desired)
6. Save into the folder *above* this `Befoor/` source directory

### 2 — Replace the generated files

1. Delete the auto-generated `ContentView.swift` and `BefoorApp.swift` Xcode created
2. Drag all files from this repository's `Befoor/` folder into Xcode's project navigator (check "Copy items if needed"):
   ```
   BefoorApp.swift
   Views/ContentView.swift
   Views/SettingsView.swift
   Views/CalendarPickerView.swift
   Models/AppSettings.swift
   Models/TrackedAlarm.swift
   Services/CalendarService.swift
   Services/NotificationService.swift
   Services/AlarmScheduler.swift
   Sounds/   (see below)
   ```

### 3 — Merge Info.plist

Open your project's `Info.plist` (or the target's Info tab) and add:

| Key | Type | Value |
|-----|------|-------|
| `NSCalendarsFullAccessUsageDescription` | String | `Befoor reads your calendar to schedule gentle alarms before your appointments.` |
| `NSCalendarsUsageDescription` | String | Same as above |
| `BGTaskSchedulerPermittedIdentifiers` | Array | Item 0: `com.befoor.calendar-refresh` |
| `UIBackgroundModes` | Array | `fetch`, `processing` |

Or replace Info.plist entirely with the one provided in this repo.

### 4 — Enable Capabilities

In the Xcode project target → **Signing & Capabilities**:

- Add **Background Modes** → check:
  - Background fetch
  - Background processing

### 5 — Add soothing sounds (optional but recommended)

Notification sounds must be ≤ 30 seconds, in `.caf`, `.aiff`, or `.wav` format.

Suggested free sources (CC0 / royalty-free):
- [freesound.org](https://freesound.org) — search "gentle chime" or "soft bell"
- [pixabay.com/sound-effects](https://pixabay.com/sound-effects/)

Convert to `.caf` with:
```sh
afconvert -f caff -d LEI16 input.mp3 gentle_chime.caf
```

Expected filenames (matching `BefoorSound` enum):
| File | Sound name in app |
|------|-------------------|
| `gentle_chime.caf` | Gentle Chime |
| `soft_bell.caf` | Soft Bell |
| `morning_dew.caf` | Morning Dew |

Drag the `.caf` files into Xcode's **Sounds** group (ensure "Add to target: Befoor" is checked).

If no sound files are bundled, the app falls back to `System Default`.

### 6 — Build & Run

Select an iPhone simulator or your device and press **⌘R**.
On first launch, the app will request Calendar and Notification permissions.

---

## How it works

```
App opens / background refresh fires
        │
        ▼
AlarmScheduler.sync()
        │
        ├── CalendarService.fetchUpcomingEvents()
        │       EventKit → filtered by selected calendars
        │
        ├── Filter: remove all-day, ignored keywords, weekends
        │
        ├── Diff against TrackedAlarmsStore
        │       • Cancelled notifications for moved/deleted events
        │       • Skip events already scheduled & unchanged
        │
        └── NotificationService.scheduleAlarm()
                UNCalendarNotificationTrigger at (eventStart − leadTime)
                Stored in TrackedAlarmsStore keyed by EKEvent.eventIdentifier
```

Background refresh is registered with `BGTaskScheduler` under identifier
`com.befoor.calendar-refresh`. iOS 17+ requires Full Access calendar permission;
iOS 16 and below uses the standard `requestAccess` path.

---

## Limitations

- iOS caps local notifications at **64 per app**. Befoor schedules the nearest 60 events and reschedules on every sync.
- Background refresh timing is managed by iOS to preserve battery; the system may delay checks by minutes or longer.
- Befoor cannot create native Clock app alarms — it uses local notifications, which require the device to not be in Do Not Disturb / Focus modes that block the notification.
