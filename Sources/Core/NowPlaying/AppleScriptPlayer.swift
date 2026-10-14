import Foundation
import AppKit

/// A generic external player that uses AppleScript to communicate with macOS media apps.
final class AppleScriptPlayer: ExternalPlayer, @unchecked Sendable {
    
    let appName: String
    private let appScriptName: String
    
    init(appName: String, appScriptName: String) {
        self.appName = appName
        self.appScriptName = appScriptName
    }
    
    var isRunning: Bool {
        let runningApps = NSWorkspace.shared.runningApplications
        return runningApps.contains { $0.localizedName == appName }
    }
    
    func fetchState() async -> ExternalPlayerState? {
        guard isRunning else { return nil }
        
        // This AppleScript gets all the metadata in a single call, separated by "|!|"
        let script = """
        if application "\(appScriptName)" is running then
            tell application "\(appScriptName)"
                try
                    set pState to player state as string
                    set tName to name of current track as string
                    set tArtist to artist of current track as string
                    set tAlbum to album of current track as string
                    set tDuration to duration of current track as string
                    set tTime to player position as string
                    return pState & "|!|" & tName & "|!|" & tArtist & "|!|" & tAlbum & "|!|" & tDuration & "|!|" & tTime
                on error
                    return "error"
                end try
            end tell
        else
            return "not running"
        end if
        """
        
        let output = await runAppleScript(script)
        guard let output = output, output != "error", output != "not running" else {
            return nil
        }
        
        let components = output.components(separatedBy: "|!|")
        guard components.count >= 6 else { return nil }
        
        let isPlaying = components[0].lowercased() == "playing"
        let trackName = components[1]
        let artistName = components[2]
        let albumName = components[3]
        
        // Spotify returns duration in milliseconds (sometimes) or seconds. Music is seconds.
        let rawDuration = Double(components[4]) ?? 0
        let duration = appScriptName == "Spotify" ? (rawDuration > 1000 ? rawDuration / 1000 : rawDuration) : rawDuration
        let currentTime = Double(components[5]) ?? 0
        
        // Fetch artwork if it's playing or we don't have it
        var artworkData: Data? = nil
        if appScriptName == "Music" {
            let artScript = """
            tell application "Music"
                try
                    set artData to raw data of artwork 1 of current track
                    return artData
                on error
                    return ""
                end try
            end tell
            """
            // NSAppleScript is better for raw data (images).
            if let scriptObj = NSAppleScript(source: artScript) {
                var error: NSDictionary?
                let desc = scriptObj.executeAndReturnError(&error)
                if error == nil {
                    artworkData = desc.data
                }
            }
        }
        
        return ExternalPlayerState(
            isPlaying: isPlaying,
            trackName: trackName,
            artistName: artistName,
            albumName: albumName,
            duration: duration,
            currentTime: currentTime,
            artworkData: artworkData,
            appName: appName
        )
    }
    
    func playPause() async {
        await runAppleScript("tell application \"\(appScriptName)\" to playpause")
    }
    
    func nextTrack() async {
        await runAppleScript("tell application \"\(appScriptName)\" to next track")
    }
    
    func previousTrack() async {
        await runAppleScript("tell application \"\(appScriptName)\" to previous track")
    }
    
    func seek(to time: TimeInterval) async {
        await runAppleScript("tell application \"\(appScriptName)\" to set player position to \(time)")
    }
    
    @discardableResult
    private func runAppleScript(_ script: String) async -> String? {
        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            
            do {
                try process.run()
                process.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(returning: nil)
                }
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }
}
