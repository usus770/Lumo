import Foundation
import OSLog

/// Safe background actor for executing AppleScript / osascript calls
/// with strict timeouts to prevent hanging or blocking the main thread.
actor AppleScriptRunner {
    static let shared = AppleScriptRunner()
    
    private init() {}
    
    /// Executes an AppleScript script string in a background process with a strict timeout.
    func run(script: String, timeout: TimeInterval = 2.0) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", script]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                
                let lock = NSLock()
                var hasResumed = false
                
                // Watchdog timer to kill hanging scripts
                let timer = DispatchSource.makeTimerSource(queue: .global())
                timer.schedule(deadline: .now() + timeout)
                timer.setEventHandler {
                    lock.lock()
                    defer { lock.unlock() }
                    if !hasResumed {
                        hasResumed = true
                        LumoLogger.appleScript.warning("AppleScript execution timed out after \(timeout)s, terminating process")
                        process.terminate()
                        continuation.resume(returning: nil)
                    }
                }
                timer.resume()
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    
                    lock.lock()
                    timer.cancel()
                    if !hasResumed {
                        hasResumed = true
                        lock.unlock()
                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                        continuation.resume(returning: output)
                    } else {
                        lock.unlock()
                    }
                } catch {
                    lock.lock()
                    timer.cancel()
                    if !hasResumed {
                        hasResumed = true
                        lock.unlock()
                        LumoLogger.appleScript.error("Failed to run AppleScript: \(error, privacy: .public)")
                        continuation.resume(returning: nil)
                    } else {
                        lock.unlock()
                    }
                }
            }
        }
    }
}
