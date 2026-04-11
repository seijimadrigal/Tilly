import Foundation

public actor WorkingMemory {
    private var entries: [String: String] = [:]
    private let maxEntries = 50

    public init() {}

    public func set(key: String, value: String) {
        if entries.count >= maxEntries {
            // Remove oldest entry (first key)
            if let first = entries.keys.sorted().first {
                entries.removeValue(forKey: first)
            }
        }
        entries[key] = value
    }

    public func get(key: String) -> String? {
        entries[key]
    }

    public func getAll() -> [String: String] {
        entries
    }

    public func clear() {
        entries.removeAll()
    }

    public func remove(key: String) {
        entries.removeValue(forKey: key)
    }

    public func summary(maxChars: Int = 800) -> String {
        if entries.isEmpty { return "(empty)" }
        var result = ""
        for (key, value) in entries.sorted(by: { $0.key < $1.key }) {
            let line = "- \(key): \(String(value.prefix(200)))\n"
            if result.count + line.count > maxChars { break }
            result += line
        }
        return result
    }
}
