# Lumo Safari Web Extension Scaffold

This folder contains the scaffold for the **Lumo Safari Web Extension** target.

## Setup in Xcode
1. Open `Lumo.xcodeproj` (or generate project via Xcode).
2. Go to **File > New > Target...**
3. Select **macOS > Safari Extension**.
4. Set Target Name to `LumoSafariExtension`.
5. Point the extension resources to `SafariExtension/`.
6. Embed the extension in the main `Lumo.app` bundle.

## Native Messaging Architecture
- In Safari, the content script reads `navigator.mediaSession.metadata` and `<video>` on `music.youtube.com`.
- Updates are posted via `browser.runtime.sendNativeMessage(...)` or direct WebSocket loopback to `127.0.0.1:19847`.
- The native extension handler `SafariExtensionHandler` implements `NSExtensionRequestHandling` to relay to Lumo.

## Critical Limitation: Safari Web Apps (PWAs)
> [!IMPORTANT]
> **Safari Web Apps (added to Dock via File > Add to Dock) run under isolated system host processes (`Safari Web App Host` / `com.apple.Safari.WebApp.*`) and DO NOT load standard Safari extensions.**
> 
> For Safari Web Apps, Lumo uses **SystemNowPlayingProvider** (Phase 2), which captures macOS `MediaRemote` system notifications published directly by the WebKit media session. This ensures seamless sync with zero browser extensions or manual settings required.
