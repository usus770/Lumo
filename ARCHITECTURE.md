# Lumo Architecture Document

## Overview
Lumo is a native macOS music player built with Swift and SwiftUI, targeting macOS 14 (Sonoma). It follows MVVM architecture with Swift Concurrency (actors for thread-safe audio and library operations).

## Project Structure
```
Sources/
├── App/                    # Entry point, AppDelegate, WindowManager
├── Core/Audio/             # Audio engine, decoders, EQ, crossfade
├── Core/NowPlaying/        # System now-playing providers (MediaRemote, AppleScript)
├── Core/Library/           # Scanner, metadata parser, file watcher
├── Models/                 # Data models (Track, Album, Artist, etc.)
├── Features/               # Feature-specific views (Library, Player, Settings)
├── UI/Components/          # Reusable SwiftUI views
├── UI/Styles/              # Colors, fonts, button styles
├── UI/Extensions/          # SwiftUI/AppKit extensions
└── Resources/              # Assets, EQ presets, entitlements
```

## Core Components

### 1. Audio Engine (`AudioEngine.swift`)
- **Actor-based** for thread-safe audio graph mutations
- Wraps `AVAudioEngine` with:
  - `AVAudioPlayerNode` for playback
  - `AVAudioUnitEQ` (10 bands) for equalization
  - `AVAudioUnitTimePitch` for playback speed (0.5x-2x)
- Buffer scheduling with generation counter for gapless/crossfade
- Time publisher for UI progress updates

### 2. Decoder Architecture
```
AudioDecoder (protocol)
├── NativeDecoder         # AVFoundation: MP3, AAC, ALAC, FLAC, WAV, AIFF, MP4/MOV
└── FallbackDecoder       # FFmpeg: OGG, OPUS, WMA, APE, WavPack, DSD, MKA, AMR, AC3
```
Selected automatically via `AudioDecoderFactory` based on file extension.

### 3. Persistence (`PersistenceStore.swift`)
- Actor-based JSON file storage in `~/Library/Application Support/Lumo/`
- Generic CRUD for all Codable+Identifiable models
- Files: Track.json, Album.json, Artist.json, Genre.json, LibraryFolder.json, Playlist.json, settings.json

### 4. Library Scanner (`LibraryScanner.swift`)
- Actor-based background scanning
- Security-scoped bookmarks for sandbox access
- Parallel metadata extraction with `MetadataParser`
- Incremental updates with FSEvents watcher (`FolderWatcher`)

### 5. Metadata Parser (`MetadataParser.swift`)
- Primary: AVFoundation `AVURLAsset` metadata loading
- Fallback: FFprobe for non-native formats
- Extracts: title, artist, album, genre, year, track/disc numbers, artwork, duration, sample rate, channels

### 6. Now Playing Providers
```
NowPlayingProvider (protocol)
├── SystemNowPlayingProvider    # MPNowPlayingInfoCenter + MPRemoteCommandCenter (media keys, Control Center)
├── UniversalNowPlayingManager  # Polls external players (AppleScript)
├── AppleScriptPlayer           # Apple Music, Spotify via AppleScript
├── MediaRemoteProvider         # Private API (disabled by default, behind ENABLE_MEDIA_REMOTE flag)
└── FallbackProvider            # Lumo's own playback state
```

### 7. Playback State (`PlaybackState.swift`)
- `@Observable` class shared across UI
- Manages: current track, queue, history, shuffle, repeat, volume, progress
- Bridges to `AudioEngine` and `SystemNowPlayingProvider`
- Handles track transitions, repeat modes, seek

### 8. UI Architecture
- **Main Window**: `NavigationSplitView` with sidebar + content + bottom `NowPlayingBar`
- **Sidebar**: `SidebarSection` enum with grouped sections (Library, Discover, Playlists)
- **Content**: Routed via `ContentView` to feature views
- **Menu Bar**: `NSStatusItem` with `NSPopover` for mini player
- **Components**: Reusable views (ArtworkView, ScrubberView, VolumeSlider, SearchBar, etc.)
- **Styling**: `LumoColors`, `LumoFonts`, `LumoStyles`, custom button styles

## Milestone Status

| Milestone | Status | Description |
|-----------|--------|-------------|
| **M1** | ✅ **Complete** | Project setup, window shell, models, basic audio engine, decoder abstraction, library scanner, now-playing providers, menu bar, UI components |
| M2 | ⏳ Pending | Library scanning + metadata + artwork (incremental, FSEvents, sidecar lyrics) |
| M3 | ⏳ Pending | Playback engine (native formats) + queue + now-playing bar (fully wired) |
| M4 | ⏳ Pending | Extra-format decoders (OGG/OPUS/WMA/APE/WavPack/DSD/MKA) |
| M5 | ⏳ Pending | System now-playing sync (MediaRemote, AppleScript bridges, permission handling) |
| M6 | ⏳ Pending | Menu bar mini player + media keys + Control Center integration |
| M7 | ⏳ Pending | Lyrics, visualizer, EQ UI, crossfade, sleep timer |
| M8 | ⏳ Pending | Settings, onboarding, accessibility, tests, polish |

## Key Design Decisions

1. **JSON over SwiftData**: Avoids Xcode macro plugin dependency; simpler for SPM-only builds
2. **Actor isolation**: `AudioEngine`, `LibraryScanner`, `PersistenceStore` are actors for thread safety
3. **`@Observable` for ViewModels**: Modern SwiftUI state management without Combine
4. **Decoder protocol**: Enables format-agnostic playback engine; easy to add new decoders
5. **Build flag for MediaRemote**: `ENABLE_MEDIA_REMOTE` (debug only) for App Store compliance
6. **Security-scoped bookmarks**: Required for sandboxed folder access
7. **Artwork stored on disk**: Hash-based deduplication, not in JSON

## Entitlements Required
```xml
<!-- For sandbox builds -->
<key>com.apple.security.files.user-selected.read-write</key><true/>
<key>com.apple.security.automation.apple-events</key><true/>
<key>com.apple.security.device.audio-output</key><true/>
```

## Known Limitations
- MediaRemote (private API) restricted on macOS 15.4+; falls back to app-specific providers
- FFmpeg required for extended formats (bundled or Homebrew)
- Gapless/crossfade works for native formats; extended formats need decoder support
- No SwiftData CloudKit sync (offline-first by design)

## Next Steps (M2)
1. Wire `SongsListView` to load actual tracks from `PersistenceStore`
2. Implement `AlbumsView`, `ArtistsView` with grid/list layouts
3. Connect folder watcher (`FolderWatcher`) for auto-sync
4. Add sidecar `.lrc` lyrics detection
5. Implement artwork caching (`ArtworkCache`) with on-disk storage