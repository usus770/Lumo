import Foundation

/// Lightweight JSON-file-based persistence layer.
/// Replaces SwiftData for environments without Xcode's macro plugins.
/// Data is stored as JSON files in the app's Application Support directory.
actor PersistenceStore {
    
    /// Shared singleton instance.
    static let shared = PersistenceStore()
    
    private let baseURL: URL
    
    private init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        baseURL = appSupport.appendingPathComponent("Lumo", isDirectory: true)
        
        // Ensure directory exists
        try? FileManager.default.createDirectory(
            at: baseURL,
            withIntermediateDirectories: true
        )
    }
    
    // MARK: - Generic CRUD
    
    /// Load all items of a given type.
    func loadAll<T: Codable & Identifiable>(_ type: T.Type) -> [T] {
        let fileURL = fileURL(for: T.self)
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([T].self, from: data)) ?? []
    }
    
    /// Save all items of a given type.
    func saveAll<T: Codable & Identifiable>(_ items: [T]) throws {
        let fileURL = fileURL(for: T.self)
        let data = try JSONEncoder().encode(items)
        try data.write(to: fileURL, options: .atomic)
    }
    
    /// Insert or update a single item.
    func upsert<T: Codable & Identifiable>(_ item: T) throws where T.ID: Equatable {
        var items = loadAll(T.self)
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.append(item)
        }
        try saveAll(items)
    }
    
    /// Delete a single item by ID.
    func delete<T: Codable & Identifiable>(_ type: T.Type, id: T.ID) throws where T.ID: Equatable {
        var items = loadAll(T.self)
        items.removeAll { $0.id == id }
        try saveAll(items)
    }
    
    // MARK: - Helpers
    
    private func fileURL<T>(for type: T.Type) -> URL {
        let name = String(describing: type)
        return baseURL.appendingPathComponent("\(name).json")
    }
    
    /// Returns the base storage URL (for debugging/testing).
    var storageURL: URL { baseURL }
}
