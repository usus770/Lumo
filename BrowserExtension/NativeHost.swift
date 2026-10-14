import Foundation
import AppKit
import os.log

/// Native messaging host for Lumo browser extension communication
/// Communicates via stdin/stdout with JSON messages
final class NativeMessagingHost: @unchecked Sendable {
    
    private let logger = OSLog(subsystem: "com.lumo.native", category: "NativeHost")
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    
    private var isRunning = true
    private var continuation: CheckedContinuation<Void, Never>?
    
    static let shared = NativeMessagingHost()
    
    private init() {
        encoder.outputFormatting = [.sortedKeys]
    }
    
    func run() async {
        os_log(.info, log: logger, "Lumo Native Host starting")
        
        // Set up signal handling
        signal(SIGTERM) { _ in
            NativeMessagingHost.shared.stop()
        }
        signal(SIGINT) { _ in
            NativeMessagingHost.shared.stop()
        }
        
        // Start reading from stdin
        await readLoop()
        
        // Wait for stop signal
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        
        os_log(.info, log: logger, "Lumo Native Host stopped")
    }
    
    func stop() {
        isRunning = false
        continuation?.resume()
    }
    
    private func readLoop() async {
        let stdin = FileHandle.standardInput
        
        while isRunning {
            do {
                // Read message length (4 bytes, little-endian)
                let lengthData = try stdin.read(upToCount: 4)
                guard let lengthData = lengthData, lengthData.count == 4 else {
                    if !isRunning { break }
                    try await Task.sleep(nanoseconds: 10_000_000)
                    continue
                }
                
                let length = lengthData.withUnsafeBytes { $0.load(as: UInt32.self) }.littleEndian
                
                // Read message body
                guard let messageData = try stdin.read(upToCount: Int(length)) else {
                    continue
                }
                
                // Parse message
                if let message = try? decoder.decode(NativeMessage.self, from: messageData) {
                    await handleMessage(message)
                }
            } catch {
                os_log(.error, log: logger, "Read error: %{public}s", "\(error)")
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }
    
    private func handleMessage(_ message: NativeMessage) async {
        os_log(.info, log: logger, "Received: %{public}s", message.type)
        
        switch message.type {
        case "HANDSHAKE":
            await sendResponse(NativeMessage(
                type: "HANDSHAKE_ACK",
                payload: [
                    "status": "connected",
                    "version": "1.0.0",
                    "capabilities": ["playback_state", "controls", "notifications"]
                ],
                timestamp: Date().timeIntervalSince1970
            ))
            
        case "PLAYBACK_STATE":
            await handlePlaybackState(message.payload ?? [:])
            
        case "CONTROL":
            await handleControl(message.payload ?? [:])
            
        case "PING":
            await sendResponse(NativeMessage(
                type: "PONG",
                payload: [:],
                timestamp: Date().timeIntervalSince1970
            ))
            
        case "PONG":
            // Ignore pong responses
            break
            
        default:
            os_log(.info, log: logger, "Unknown message type: %{public}s", message.type)
        }
    }
    
    private func handlePlaybackState(_ payload: [String: Any]) async {
        os_log(.info, log: logger, "Forwarding playback state to Lumo app on 127.0.0.1:19847")
        guard let url = URL(string: "http://127.0.0.1:19847/api/now-playing") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let jsonData = try? JSONSerialization.data(withJSONObject: payload) {
            request.httpBody = jsonData
            _ = try? await URLSession.shared.data(for: request)
        }
    }
    
    private func handleControl(_ payload: [String: Any]) async {
        guard let action = payload["action"] as? String else { return }
        os_log(.info, log: logger, "Control action: %{public}s", action)
    }
    
    private func sendResponse(_ message: NativeMessage) async {
        do {
            let data = try encoder.encode(message)
            let length = UInt32(data.count).littleEndian
            let lengthData = withUnsafeBytes(of: length) { Data($0) }
            
            let stdout = FileHandle.standardOutput
            try stdout.write(contentsOf: lengthData)
            try stdout.write(contentsOf: data)
            
            os_log(.info, log: logger, "Sent: %{public}s", "\(message.type)")
        } catch {
            os_log(.error, log: logger, "Write error: %{public}s", "\(error)")
        }
    }
}

// MARK: - Message Types

struct NativeMessage: Codable {
    let type: String
    let payload: [String: AnyCodable]?
    let timestamp: TimeInterval
    
    init(type: String, payload: [String: Any]? = nil, timestamp: TimeInterval) {
        self.type = type
        self.payload = payload?.mapValues { AnyCodable($0) }
        self.timestamp = timestamp
    }
}

struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let bool as Bool: try container.encode(bool)
        case let int as Int: try container.encode(int)
        case let double as Double: try container.encode(double)
        case let string as String: try container.encode(string)
        case let array as [Any]: try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]: try container.encode(dict.mapValues { AnyCodable($0) })
        default: try container.encodeNil()
        }
    }
}

// MARK: - Main

@main
struct LumoNativeHost {
    static func main() async {
        await NativeMessagingHost.shared.run()
    }
}