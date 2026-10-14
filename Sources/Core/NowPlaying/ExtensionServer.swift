import Foundation
import Darwin
import CommonCrypto
import OSLog

/// Lightweight loopback server (WebSocket & HTTP) inside Lumo Mac app.
/// Binds strictly to 127.0.0.1:19847 to receive metadata from the browser extension
/// and send control commands (play/pause/next/previous/seek/like).
@Observable
final class ExtensionServer: @unchecked Sendable {
    static let shared = ExtensionServer()
    
    // Server Configuration
    static let defaultPort: UInt16 = 19847
    static let loopbackAddress = "127.0.0.1"
    
    // Observable State
    var isConnected: Bool = false
    var clientCount: Int = 0
    var lastReceivedState: ExternalPlayerState?
    
    // Artwork Cache
    private var lastArtworkUrl: String?
    private var cachedArtworkData: Data?
    
    // Internal State
    private var serverSocket: Int32 = -1
    private var listenSource: DispatchSourceRead?
    private let serverQueue = DispatchQueue(label: "com.lumo.extension.server", qos: .userInitiated)
    private var clientSockets: Set<Int32> = []
    private var clientBuffers: [Int32: Data] = [:]
    private var clientIsWebSocket: [Int32: Bool] = [:]
    private let clientLock = NSLock()
    
    private var stateCallback: (@Sendable (ExternalPlayerState) -> Void)?
    
    private init() {
        start()
    }
    
    deinit {
        stop()
    }
    
    func onStateUpdate(_ callback: @escaping @Sendable (ExternalPlayerState) -> Void) {
        self.stateCallback = callback
    }
    
    // MARK: - Lifecycle
    
    func start() {
        serverQueue.async { [weak self] in
            self?.setupServer()
        }
    }
    
    func stop() {
        serverQueue.async { [weak self] in
            guard let self = self else { return }
            self.listenSource?.cancel()
            self.listenSource = nil
            
            self.clientLock.lock()
            for fd in self.clientSockets {
                Darwin.close(fd)
            }
            self.clientSockets.removeAll()
            self.clientBuffers.removeAll()
            self.clientIsWebSocket.removeAll()
            self.clientLock.unlock()
            
            if self.serverSocket >= 0 {
                Darwin.close(self.serverSocket)
                self.serverSocket = -1
            }
            
            Task { @MainActor in
                self.isConnected = false
                self.clientCount = 0
            }
            LumoLogger.browserExtension.info("Extension server stopped")
        }
    }
    
    // MARK: - Socket Setup
    
    private func setupServer() {
        if serverSocket >= 0 {
            Darwin.close(serverSocket)
            serverSocket = -1
        }
        
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            LumoLogger.browserExtension.error("socket() creation failed: \(errno)")
            return
        }
        
        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        
        // Bind strictly to 127.0.0.1
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(Self.defaultPort).bigEndian
        addr.sin_addr.s_addr = inet_addr(Self.loopbackAddress)
        
        let bindRes = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.bind(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        
        guard bindRes == 0 else {
            LumoLogger.browserExtension.error("bind() failed on 127.0.0.1:\(Self.defaultPort): \(errno)")
            Darwin.close(fd)
            return
        }
        
        guard Darwin.listen(fd, 8) == 0 else {
            LumoLogger.browserExtension.error("listen() failed: \(errno)")
            Darwin.close(fd)
            return
        }
        
        self.serverSocket = fd
        
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: serverQueue)
        source.setEventHandler { [weak self] in
            self?.acceptIncomingConnections()
        }
        source.setCancelHandler {
            Darwin.close(fd)
        }
        source.resume()
        self.listenSource = source
        
        LumoLogger.browserExtension.info("Extension server listening on 127.0.0.1:\(Self.defaultPort)")
    }
    
    private func acceptIncomingConnections() {
        var clientAddr = sockaddr_in()
        var clientLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        
        let clientFd = withUnsafeMutablePointer(to: &clientAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.accept(serverSocket, sa, &clientLen)
            }
        }
        
        guard clientFd >= 0 else { return }
        
        // Strict Security: Verify incoming peer address is 127.0.0.1
        let clientIP = String(cString: inet_ntoa(clientAddr.sin_addr))
        guard clientIP == Self.loopbackAddress || clientIP.hasPrefix("127.") else {
            LumoLogger.browserExtension.warning("Rejected non-loopback connection from: \(clientIP, privacy: .public)")
            Darwin.close(clientFd)
            return
        }
        
        clientLock.lock()
        clientSockets.insert(clientFd)
        clientBuffers[clientFd] = Data()
        clientIsWebSocket[clientFd] = false
        let totalCount = clientSockets.count
        clientLock.unlock()
        
        Task { @MainActor in
            self.isConnected = true
            self.clientCount = totalCount
        }
        
        setupClientReader(fd: clientFd)
    }
    
    private func setupClientReader(fd: Int32) {
        let readSource = DispatchSource.makeReadSource(fileDescriptor: fd, queue: serverQueue)
        
        readSource.setEventHandler { [weak self] in
            guard let self = self else { return }
            var buffer = [UInt8](repeating: 0, count: 4096)
            let bytesRead = Darwin.read(fd, &buffer, buffer.count)
            
            if bytesRead > 0 {
                let data = Data(buffer[0..<bytesRead])
                self.handleClientData(fd: fd, data: data)
            } else if bytesRead <= 0 {
                self.closeClient(fd: fd)
                readSource.cancel()
            }
        }
        
        readSource.setCancelHandler {
            Darwin.close(fd)
        }
        
        readSource.resume()
    }
    
    private func closeClient(fd: Int32) {
        clientLock.lock()
        clientSockets.remove(fd)
        clientBuffers.removeValue(forKey: fd)
        clientIsWebSocket.removeValue(forKey: fd)
        let totalCount = clientSockets.count
        clientLock.unlock()
        
        Darwin.close(fd)
        
        Task { @MainActor in
            self.clientCount = totalCount
            self.isConnected = totalCount > 0
        }
        LumoLogger.browserExtension.info("Extension client disconnected (remaining: \(totalCount))")
    }
    
    // MARK: - Data & Protocol Handling
    
    private func handleClientData(fd: Int32, data: Data) {
        clientLock.lock()
        guard var buf = clientBuffers[fd] else {
            clientLock.unlock()
            return
        }
        buf.append(data)
        let isWS = clientIsWebSocket[fd] ?? false
        clientBuffers[fd] = buf
        clientLock.unlock()
        
        if !isWS {
            // Check if initial HTTP request (WebSocket Upgrade or HTTP POST)
            if let str = String(data: buf, encoding: .utf8), str.contains("\r\n\r\n") {
                if str.contains("Upgrade: websocket") || str.contains("Upgrade: WebSocket") {
                    handleWebSocketHandshake(fd: fd, requestString: str)
                } else {
                    handleHttpRequest(fd: fd, requestString: str, fullData: buf)
                }
            }
        } else {
            // Parse WebSocket Frame
            parseWebSocketFrames(fd: fd)
        }
    }
    
    private func handleWebSocketHandshake(fd: Int32, requestString: String) {
        // Extract Sec-WebSocket-Key
        guard let key = extractHeader(from: requestString, name: "Sec-WebSocket-Key") else {
            closeClient(fd: fd)
            return
        }
        
        // Compute RFC 6455 Accept Key
        let acceptKey = computeSecWebSocketAccept(clientKey: key)
        let response =
            "HTTP/1.1 101 Switching Protocols\r\n" +
            "Upgrade: websocket\r\n" +
            "Connection: Upgrade\r\n" +
            "Sec-WebSocket-Accept: \(acceptKey)\r\n\r\n"
        
        if let respData = response.data(using: .utf8) {
            _ = respData.withUnsafeBytes { ptr in
                Darwin.write(fd, ptr.baseAddress, respData.count)
            }
        }
        
        clientLock.lock()
        clientIsWebSocket[fd] = true
        // Strip handshake from buffer
        if let range = requestString.range(of: "\r\n\r\n") {
            let offset = requestString.distance(from: requestString.startIndex, to: range.upperBound)
            if let buf = clientBuffers[fd], buf.count > offset {
                clientBuffers[fd] = buf.subdata(in: offset..<buf.count)
            } else {
                clientBuffers[fd] = Data()
            }
        }
        clientLock.unlock()
        
        LumoLogger.browserExtension.info("WebSocket handshake established with browser extension")
        
        // If there were trailing frames, process them
        parseWebSocketFrames(fd: fd)
    }
    
    private func handleHttpRequest(fd: Int32, requestString: String, fullData: Data) {
        // Simple HTTP POST /api/now-playing support
        let corsHeaders =
            "Access-Control-Allow-Origin: *\r\n" +
            "Access-Control-Allow-Headers: Content-Type, Authorization\r\n" +
            "Access-Control-Allow-Methods: POST, GET, OPTIONS\r\n"
        
        if requestString.hasPrefix("OPTIONS") {
            let resp = "HTTP/1.1 204 No Content\r\n\(corsHeaders)\r\n"
            sendRaw(fd: fd, string: resp)
            closeClient(fd: fd)
            return
        }
        
        if requestString.hasPrefix("POST /api/now-playing") || requestString.hasPrefix("POST /") {
            if let bodyRange = requestString.range(of: "\r\n\r\n") {
                let body = String(requestString[bodyRange.upperBound...])
                if let jsonData = body.data(using: .utf8),
                   let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                    processIncomingPayload(dict)
                }
            }
            let resp = "HTTP/1.1 200 OK\r\n\(corsHeaders)Content-Type: application/json\r\nContent-Length: 15\r\n\r\n{\"status\":\"ok\"}"
            sendRaw(fd: fd, string: resp)
            closeClient(fd: fd)
            return
        }
        
        // Fallback 404
        let resp = "HTTP/1.1 404 Not Found\r\n\(corsHeaders)Content-Length: 0\r\n\r\n"
        sendRaw(fd: fd, string: resp)
        closeClient(fd: fd)
    }
    
    private func sendRaw(fd: Int32, string: String) {
        guard let data = string.data(using: .utf8) else { return }
        _ = data.withUnsafeBytes { ptr in
            Darwin.write(fd, ptr.baseAddress, data.count)
        }
    }
    
    // MARK: - WebSocket Framing (RFC 6455)
    
    private func parseWebSocketFrames(fd: Int32) {
        clientLock.lock()
        guard var buf = clientBuffers[fd] else {
            clientLock.unlock()
            return
        }
        clientLock.unlock()
        
        while buf.count >= 2 {
            let b0 = buf[0]
            let b1 = buf[1]
            
            let opcode = b0 & 0x0F
            let isMasked = (b1 & 0x80) != 0
            var payloadLen = UInt64(b1 & 0x7F)
            
            var headerSize = 2
            if payloadLen == 126 {
                guard buf.count >= 4 else { break }
                payloadLen = UInt64(buf[2]) << 8 | UInt64(buf[3])
                headerSize = 4
            } else if payloadLen == 127 {
                guard buf.count >= 10 else { break }
                payloadLen = 0
                for i in 2..<10 {
                    payloadLen = (payloadLen << 8) | UInt64(buf[i])
                }
                headerSize = 10
            }
            
            var maskKey: [UInt8] = []
            if isMasked {
                guard buf.count >= headerSize + 4 else { break }
                maskKey = [buf[headerSize], buf[headerSize + 1], buf[headerSize + 2], buf[headerSize + 3]]
                headerSize += 4
            }
            
            let totalFrameSize = headerSize + Int(payloadLen)
            guard buf.count >= totalFrameSize else { break }
            
            // Extract and unmask payload
            var payloadData = [UInt8](repeating: 0, count: Int(payloadLen))
            for i in 0..<Int(payloadLen) {
                let byte = buf[headerSize + i]
                if isMasked {
                    payloadData[i] = byte ^ maskKey[i % 4]
                } else {
                    payloadData[i] = byte
                }
            }
            
            // Remove frame from buffer
            buf = buf.subdata(in: totalFrameSize..<buf.count)
            
            // Handle Opcode
            if opcode == 0x01 { // Text Frame
                if let jsonStr = String(bytes: payloadData, encoding: .utf8),
                   let jsonData = jsonStr.data(using: .utf8),
                   let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                    processIncomingPayload(dict)
                }
            } else if opcode == 0x08 { // Close Frame
                closeClient(fd: fd)
                return
            } else if opcode == 0x09 { // Ping -> reply Pong
                sendWebSocketFrame(fd: fd, opcode: 0x0A, payload: Data(payloadData))
            }
        }
        
        clientLock.lock()
        clientBuffers[fd] = buf
        clientLock.unlock()
    }
    
    private func computeSecWebSocketAccept(clientKey: String) -> String {
        let magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        let full = clientKey.trimmingCharacters(in: .whitespacesAndNewlines) + magic
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        let data = Array(full.utf8)
        _ = CC_SHA1(data, CC_LONG(data.count), &digest)
        return Data(digest).base64EncodedString()
    }
    
    private func extractHeader(from request: String, name: String) -> String? {
        let lines = request.components(separatedBy: "\r\n")
        let prefix = "\(name.lowercased()):"
        for line in lines {
            if line.lowercased().hasPrefix(prefix) {
                let parts = line.split(separator: ":", maxSplits: 1)
                if parts.count == 2 {
                    return parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        return nil
    }
    
    // MARK: - Sending Commands to Extension
    
    func sendControlCommand(action: String, time: TimeInterval? = nil) {
        var payload: [String: Any] = [
            "type": "CONTROL",
            "action": action,
            "timestamp": Date().timeIntervalSince1970
        ]
        if let time = time {
            payload["time"] = time
        }
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else { return }
        
        clientLock.lock()
        let activeFds = Array(clientSockets)
        clientLock.unlock()
        
        LumoLogger.browserExtension.info("Dispatching command '\(action, privacy: .public)' to \(activeFds.count) extension client(s)")
        
        for fd in activeFds {
            sendWebSocketFrame(fd: fd, opcode: 0x01, payload: jsonData)
        }
    }
    
    private func sendWebSocketFrame(fd: Int32, opcode: UInt8, payload: Data) {
        var frame = Data()
        frame.append(0x80 | opcode) // FIN + opcode
        
        let count = payload.count
        if count < 126 {
            frame.append(UInt8(count))
        } else if count <= 65535 {
            frame.append(126)
            frame.append(UInt8((count >> 8) & 0xFF))
            frame.append(UInt8(count & 0xFF))
        } else {
            frame.append(127)
            for i in (0..<8).reversed() {
                frame.append(UInt8((count >> (i * 8)) & 0xFF))
            }
        }
        frame.append(payload)
        
        _ = frame.withUnsafeBytes { ptr in
            Darwin.write(fd, ptr.baseAddress, frame.count)
        }
    }
    
    // MARK: - Processing Playback Payload
    
    private func processIncomingPayload(_ dict: [String: Any]) {
        let msgType = dict["type"] as? String ?? ""
        if msgType == "HANDSHAKE" || msgType == "PONG" {
            return
        }
        
        let isPlaying = dict["isPlaying"] as? Bool ?? false
        let title = dict["trackName"] as? String ?? "Unknown Title"
        let artist = dict["artistName"] as? String ?? "YouTube Music"
        let album = dict["albumName"] as? String ?? ""
        let duration = dict["duration"] as? Double ?? 0
        let currentTime = dict["currentTime"] as? Double ?? 0
        let artworkUrl = dict["artworkUrl"] as? String
        let pageUrl = dict["url"] as? String
        let videoId = dict["videoId"] as? String
        let rate = dict["playbackRate"] as? Double ?? 1.0
        let timestampMs = dict["timestamp"] as? Double
        let timestampSec = timestampMs != nil ? (timestampMs! / 1000.0) : Date().timeIntervalSince1970
        
        let state = ExternalPlayerState(
            isPlaying: isPlaying,
            trackName: title,
            artistName: artist,
            albumName: album,
            duration: duration,
            currentTime: currentTime,
            artworkData: nil,
            appName: "YouTube Music",
            sourceBundleIdentifier: "com.google.Chrome",
            sourceURL: pageUrl,
            videoId: videoId,
            playbackRate: rate,
            lastUpdated: Date(),
            timestamp: timestampSec,
            hostTime: ProcessInfo.processInfo.systemUptime
        )
        
        // Check if we have cached artwork
        if let artStr = artworkUrl {
            if artStr == self.lastArtworkUrl, let cached = self.cachedArtworkData {
                var artState = state
                artState.artworkData = cached
                Task { @MainActor in
                    self.lastReceivedState = artState
                    self.stateCallback?(artState)
                }
                return
            } else {
                self.lastArtworkUrl = artStr
                self.cachedArtworkData = nil // clear old cache
                
                let rewrittenUrlStr = ArtworkPipeline.rewriteArtworkURL(artStr)
                if let artURL = URL(string: rewrittenUrlStr) {
                    var artState = state
                    Task {
                        if let (rawArtData, _) = try? await URLSession.shared.data(from: artURL) {
                            let artData = ArtworkPipeline.squareCropIfNeeded(data: rawArtData)
                            artState.artworkData = artData
                            let finalState = artState
                            
                            self.serverQueue.async {
                                if self.lastArtworkUrl == artStr {
                                    self.cachedArtworkData = artData
                                }
                            }
                            
                            await MainActor.run {
                                self.lastReceivedState = finalState
                                self.stateCallback?(finalState)
                            }
                        }
                    }
                }
            }
        }
        
        let initialState = state
        Task { @MainActor in
            self.lastReceivedState = initialState
            self.stateCallback?(initialState)
        }
    }
}
