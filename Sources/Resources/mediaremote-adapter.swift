import Foundation
import AppKit

// mediaremote-adapter.swift
// Native macOS MediaRemote adapter executed via Apple-signed /usr/bin/swift.
// Bridges macOS MediaRemote private framework to Lumo with zero sandbox/audit token limitations.

let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
guard let handle = dlopen(path, RTLD_NOW) else {
    fputs("dlopen MediaRemote failed\n", stderr)
    exit(1)
}

typealias MRGetInfoFn = @convention(c) (DispatchQueue, @escaping @Sendable (NSDictionary?) -> Void) -> Void
typealias MRPidFn = @convention(c) (DispatchQueue, @escaping @Sendable (pid_t) -> Void) -> Void
typealias MRSendCommandFn = @convention(c) (UInt32, UnsafeMutableRawPointer?) -> Bool

guard let getInfoSym = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo"),
      let getPIDSym = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationPID"),
      let sendCmdSym = dlsym(handle, "MRMediaRemoteSendCommand") else {
    fputs("dlsym failed for core MediaRemote functions\n", stderr)
    exit(1)
}

let getInfo = unsafeBitCast(getInfoSym, to: MRGetInfoFn.self)
let getPID = unsafeBitCast(getPIDSym, to: MRPidFn.self)
let sendCommand = unsafeBitCast(sendCmdSym, to: MRSendCommandFn.self)

// Background Thread: Listen for stdin commands
DispatchQueue.global(qos: .userInitiated).async {
    let stdinHandle = FileHandle.standardInput
    while true {
        let data = stdinHandle.availableData
        if data.isEmpty {
            // EOF reached, parent process terminated
            exit(0)
        }
        guard let line = String(data: data, encoding: .utf8) else { continue }
        let commands = line.components(separatedBy: .newlines)
        for cmd in commands {
            let trimmed = cmd.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("COMMAND:") {
                let cmdStr = trimmed.replacingOccurrences(of: "COMMAND:", with: "")
                if let cmdCode = UInt32(cmdStr) {
                    _ = sendCommand(cmdCode, nil)
                }
            } else if trimmed == "QUIT" || trimmed == "EXIT" {
                exit(0)
            }
        }
    }
}

// Initial Handshake
print("{\"type\":\"READY\",\"pid\":\(getpid())}")
fflush(stdout)

// Polling loop
var lastTitle: String? = nil
var lastArtist: String? = nil
var lastRate: Double? = nil
var lastElapsedTime: Double = -10.0

while true {
    let sema = DispatchSemaphore(value: 0)
    var fetchedDict: [String: Any]? = nil
    
    getInfo(DispatchQueue.global()) { dict in
        if let d = dict as? [String: Any] {
            fetchedDict = d
        }
        sema.signal()
    }
    _ = sema.wait(timeout: .now() + 0.4)
    
    if let dict = fetchedDict {
        let pidSema = DispatchSemaphore(value: 0)
        var sourcePID: pid_t = 0
        getPID(DispatchQueue.global()) { pid in
            sourcePID = pid
            pidSema.signal()
        }
        _ = pidSema.wait(timeout: .now() + 0.2)
        
        let title = (dict["kMRMediaRemoteNowPlayingInfoTitle"] as? String) ?? ""
        let artist = (dict["kMRMediaRemoteNowPlayingInfoArtist"] as? String) ?? ""
        let album = (dict["kMRMediaRemoteNowPlayingInfoAlbum"] as? String) ?? ""
        let duration = (dict["kMRMediaRemoteNowPlayingInfoDuration"] as? NSNumber)?.doubleValue ?? 0.0
        let elapsedTime = (dict["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? NSNumber)?.doubleValue ?? 0.0
        let playbackRate = (dict["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? NSNumber)?.doubleValue ?? 0.0
        
        var bundleID = dict["kMRMediaRemoteNowPlayingInfoBundleIdentifier"] as? String ?? ""
        var appName = ""
        
        if sourcePID > 0, let app = NSRunningApplication(processIdentifier: sourcePID) {
            if bundleID.isEmpty {
                bundleID = app.bundleIdentifier ?? ""
            }
            appName = app.localizedName ?? ""
        }
        
        var artworkBase64: String? = nil
        if let artData = dict["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data {
            artworkBase64 = artData.base64EncodedString()
        }
        
        var payload: [String: Any] = [
            "type": "NOW_PLAYING",
            "title": title,
            "artist": artist,
            "album": album,
            "duration": duration,
            "elapsedTime": elapsedTime,
            "playbackRate": playbackRate,
            "bundleIdentifier": bundleID,
            "appName": appName
        ]
        if let artworkBase64 = artworkBase64 {
            payload["artworkData"] = artworkBase64
        }
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: payload),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            print(jsonString)
            fflush(stdout)
        }
    } else {
        if lastTitle != nil {
            print("{\"type\":\"EMPTY\"}")
            fflush(stdout)
            lastTitle = nil
        }
    }
    
    Thread.sleep(forTimeInterval: 0.8)
}
