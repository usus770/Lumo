# Lumo for iOS 📱

A native iOS music player and reactive kinetic visualizer crafted with Swift and SwiftUI, matching the high-contrast dark theme of Lumo for Mac.

- **Developer**: **Ujjwal Singh**
- **GitHub**: [https://github.com/usus770](https://github.com/usus770)
- **Bundle ID**: `com.ujjwal.lumo`
- **Target OS**: iOS 17.0+ (iPhone & iPad)

---

## ✨ Key Features

1. **Native Background Audio**:
   - Background audio capability (`UIBackgroundModes: audio`) keeps your music playing seamlessly when your iPhone is locked or when switching apps.
2. **Lock Screen & Dynamic Island Integration**:
   - `MPNowPlayingInfoCenter` displays high-resolution artwork, track title, artist, and live scrubber on your iPhone Lock Screen, Control Center, Dynamic Island, and Apple Watch.
   - `MPRemoteCommandCenter` enables play/pause, next/previous, and scrubbing from Lock Screen or AirPods controls.
3. **Playing Queue & Reordering**:
   - Full "Up Next" queue drawer with intuitive drag-and-drop reordering (drag one song over another to change the play order).
   - Swipe-to-delete, double-tap to play, and shuffle toggle with canonical order restoration.
4. **Music Import via Files App**:
   - Tap the `+` button in the Library tab to import `.mp3`, `.flac`, `.m4a`, and `.wav` audio files directly from your iPhone Files app or iCloud Drive.
5. **Kinetic Reactive Visualizer**:
   - Real-time animated frequency bars and ambient pulse aura tuned to the Lumo brand gradient (`Amber` → `Pink` → `Violet`).
6. **Synchronized LRC Lyrics & Romanization**:
   - Scrolling karaoke-style lyrics with Devanagari and non-Latin script Romanization via CoreFoundation.
7. **Developer Attribution**:
   - Settings tab features the official About Lumo card with **Ujjwal Singh** and an interactive link to `https://github.com/usus770`.

---

## 🚀 How to Install on Your iPhone

### Step 1: Install Xcode on your Mac
If you don't already have Xcode:
1. Open the **App Store** on your Mac.
2. Search for **Xcode** and click **Get / Install** (Free).

### Step 2: Open the Project in Xcode
Double-click the project file located at:
```bash
Lumo-iOS/Lumo.xcodeproj
```
or run in Terminal:
```bash
open Lumo-iOS/Lumo.xcodeproj
```

### Step 3: Configure Free Apple ID Signing
1. In Xcode's left sidebar, click the blue **Lumo** project at the top.
2. In the center pane, select the **Lumo** target under *Targets*.
3. Click the **Signing & Capabilities** tab.
4. Check **Automatically manage signing**.
5. Under **Team**, select your Personal Apple ID account (e.g. `Ujjwal Singh (Personal Team)`). If you haven't added your Apple ID yet, click *Add Account...* and sign in with your regular Apple ID (no paid developer account is needed).

### Step 4: Connect Your iPhone
1. Connect your iPhone to your Mac using a USB-C or Lightning cable.
2. On your iPhone, tap **Trust This Computer** and enter your passcode.
3. In Xcode's top toolbar, click the device selector (next to the Play/Stop buttons) and select your **physical iPhone** (e.g., `Ujjwal's iPhone`).

### Step 5: Enable Developer Mode on iPhone (iOS 17+)
If you haven't run your own apps on this iPhone before:
1. On your iPhone, open **Settings** → **Privacy & Security**.
2. Scroll to the bottom and tap **Developer Mode**.
3. Toggle it **ON** and restart your iPhone when prompted.

### Step 6: Click Run (`⌘ R`)
1. In Xcode, click the **Play** button (or press `Command + R`).
2. Xcode will compile, code-sign, and install **Lumo** directly onto your iPhone home screen!
3. Tap the **Lumo** app icon on your iPhone to start listening.
