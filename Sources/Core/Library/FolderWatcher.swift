import Foundation

/// Watches library folders for changes using FSEvents.
final class FolderWatcher: @unchecked Sendable {
    static let shared = FolderWatcher()
    
    private var stream: FSEventStreamRef?
    private var isRunning = false
    
    private init() {}
    
    deinit {
        stop()
    }
    
    func start(watching paths: [String]) {
        guard !paths.isEmpty else { return }
        stop()
        
        let pathsToWatch = paths as CFArray
        
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        
        let flags: FSEventStreamCreateFlags = UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        
        stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            eventCallback,
            &context,
            pathsToWatch,
            FSEventsGetCurrentEventId(),
            2.0, // latency
            flags
        )
        
        if let stream {
            FSEventStreamSetDispatchQueue(stream, DispatchQueue.global(qos: .background))
            FSEventStreamStart(stream)
            isRunning = true
        }
    }
    
    func stop() {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
        isRunning = false
    }
}

// Global callback for FSEvents
private let eventCallback: FSEventStreamCallback = { (
    streamRef: ConstFSEventStreamRef,
    clientCallBackInfo: UnsafeMutableRawPointer?,
    numEvents: Int,
    eventPaths: UnsafeMutableRawPointer,
    eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    eventIds: UnsafePointer<FSEventStreamEventId>
) in
    // Debounce/Throttle and trigger library scan
    // We notify that something changed. The LibraryScanner should do a diff or partial scan.
    // For M2, we'll just trigger a notification to re-read the folder.
    DispatchQueue.main.async {
        NotificationCenter.default.post(name: .libraryNeedsRescan, object: nil)
    }
}

extension Notification.Name {
    static let libraryNeedsRescan = Notification.Name("libraryNeedsRescan")
}
