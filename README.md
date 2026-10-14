# Lumo — Universal Music Player & Kinetic Visualizer

A modern native macOS music player and reactive kinetic visualizer with unified brand identity and system-wide YouTube Music synchronization.

---

## 🎨 Brand Identity

Lumo is crafted with a curated, high-contrast dark theme:
- **Backgrounds**: `bg0` (`#07040D`), `bg1` (`#0B0710`), `surface` (`#150D22`), `surfaceRaised` (`#1E1330`), `stroke` (white 10% opacity)
- **Text & Contrast**: Primary (`#FFFFFF`, > 14:1 contrast ratio), Secondary (`white 65%`, > 7:1), Tertiary (`white 40%`, > 4.5:1)
- **Brand Accents**: Amber (`#FFC857`), Pink (`#FF3D9A`), Violet (`#7C5CFF`)
- **Brand Gradient**: Diagonal linear gradient (Amber → Pink → Violet) used for playback accents, scrubbers, glow aura, and branding.

---

## 🚀 How to Build & Package

### Requirements
- macOS Sonoma 14.0 or newer
- Swift 6.0 toolchain (`xcode-select --install` or Xcode 16+)
- *Optional*: `ffmpeg` (`brew install ffmpeg`) for lossless audio format conversions

### 1. Build the Release `.app` Bundle
Run the automated build and packaging script:
```bash
bash scripts/build_app.sh
```
This script:
1. Compiles Lumo with optimizations in release mode (`swift build -c release`).
2. Assembles the standalone `build/Lumo.app` bundle with `Info.plist`, resource bundles, and 1024x1024 `AppIcon.icns`.
3. Ad-hoc signs the application bundle using `codesign --force --deep -s -`.
4. Validates disk integrity and bundle signatures.

### 2. Create the Installable DMG
To package `Lumo.app` into a disk image with an `/Applications` drag-and-drop shortcut:
```bash
bash scripts/make_dmg.sh
```
The resulting disk image is generated at:
```
build/Lumo-1.0.0.dmg
```

---

## 💿 Installation & First-Time Launch (Gatekeeper)

### Installing
1. Double-click `build/Lumo-1.0.0.dmg`.
2. Drag `Lumo.app` into the **Applications** folder shortcut.
3. Eject the DMG.

### ⚠️ First-Time Opening (Unnotarized / Ad-hoc Signed App)
Because this application is built for personal use and signed ad-hoc (without an Apple Developer paid notarization profile), macOS Gatekeeper will protect you on first launch with:
> *"Lumo" cannot be opened because Apple cannot check it for malicious software.*

**To open it the first time:**
1. In Finder, navigate to your `/Applications` folder (or `build/`).
2. **Right-click** (or Control-click) `Lumo.app` and choose **Open**.
3. In the warning dialog that appears, click the **Open** button.
4. *Alternatively*:
   - Open **System Settings** > **Privacy & Security**.
   - Scroll down to the **Security** section.
   - Click **Open Anyway** next to the notification for Lumo.

*Note: You only need to perform this step once. Subsequent launches open instantly.*

---

## 🏃 Running in Development Mode

You can also run Lumo directly from source:
```bash
swift run Lumo
```
Or run the complete automated test suite (51 unit tests):
```bash
swift run Lumo --run-tests
```

---

## 📂 Data Storage Locations

Lumo stores its local persistent data in standard macOS Application Support and Cache directories:

| Component | Path | Description |
|-----------|------|-------------|
| **Database & Folders** | `~/Library/Application Support/Lumo/` | Watched folders, track index, playlists, and settings |
| **Artwork Cache** | `~/Library/Caches/com.lumo.music/Artwork/`<br>`~/Library/Application Support/Lumo/ArtworkCache/` | High-resolution cropped square album covers |
| **Lyrics Cache** | `~/Library/Application Support/Lumo/LyricsCache/` | Synced LRC lyrics files & Romanized transliterations |
| **App Preferences** | `~/Library/Preferences/com.lumo.music.plist` | User preferences, equalizer bands, and onboarding flag |

---

## 🔄 How to Reset Lumo

To reset Lumo to a clean factory state (wiping library database, artwork cache, and preferences):
```bash
# 1. Terminate running instances
pkill -x Lumo || true

# 2. Remove application data and caches
rm -rf ~/Library/Application\ Support/Lumo
rm -rf ~/Library/Caches/com.lumo.music
defaults delete com.lumo.music 2>/dev/null || true

echo "Lumo has been successfully reset."
```

---

## 🗑️ How to Uninstall

1. Move `/Applications/Lumo.app` to the Trash.
2. Run the reset commands above to delete cached artwork and library databases.

---

## ⌨️ Visualizer & Playback Shortcuts

| Shortcut | Action |
|----------|--------|
| `⌘ ⇧ V` | Open Full-Screen Kinetic Visualizer |
| `Esc` or `⌘ W` | Exit Full-Screen Visualizer |
| `Space` | Play / Pause |
| `⌘ →` / `⌘ ←` | Next Track / Previous Track |
| `⌘ ↑` / `⌘ ↓` | Volume Up / Volume Down |
| `⌘ ⇧ S` | Toggle Shuffle |
| `⌘ ⇧ R` | Cycle Repeat Mode |

---

## 🛡️ External Synchronization & Permissions
Lumo features universal music sync:
- **Safari & Safari Web Apps (PWAs)**: Zero configuration required via macOS `MediaRemote`.
- **Chrome / Brave / Edge / Arc**: Works out of the box via MediaRemote or optional companion extension.
- **Spotify / Apple Music**: Apple Events bridge (triggers permission consent only when enabled).

---

## 👨‍💻 Author & Credits

- **Developer**: **Ujjwal Singh**
- **GitHub**: [https://github.com/usus770](https://github.com/usus770)
- **License**: Personal / Open Project