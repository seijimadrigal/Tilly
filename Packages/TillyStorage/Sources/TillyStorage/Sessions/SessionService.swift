import Foundation
import TillyCore

public final class SessionService: @unchecked Sendable {
    public let sessionsDirectory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        self.sessionsDirectory = appSupport.appendingPathComponent("Tilly/sessions")
        self.encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        ensureDirectoryExists()
    }

    // MARK: - Save / Load

    public func save(_ session: Session) {
        let filePath = sessionsDirectory.appendingPathComponent("\(session.id.uuidString).json")
        do {
            let data = try encoder.encode(session)
            try data.write(to: filePath, options: .atomic)
        } catch {
            print("Failed to save session \(session.id): \(error)")
        }
    }

    public func loadAll() -> [Session] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: sessionsDirectory.path) else { return [] }

        do {
            let files = try fm.contentsOfDirectory(at: sessionsDirectory, includingPropertiesForKeys: [.contentModificationDateKey])
                .filter { $0.pathExtension == "json" }

            var sessions: [Session] = []
            for file in files {
                do {
                    let data = try Data(contentsOf: file)
                    let session = try decoder.decode(Session.self, from: data)
                    sessions.append(session)
                } catch {
                    print("Failed to load session from \(file.lastPathComponent): \(error)")
                }
            }

            // Sort by most recently updated first
            return sessions.sorted { $0.updatedAt > $1.updatedAt }
        } catch {
            print("Failed to list sessions: \(error)")
            return []
        }
    }

    public func delete(_ sessionID: UUID) {
        let filePath = sessionsDirectory.appendingPathComponent("\(sessionID.uuidString).json")
        try? FileManager.default.removeItem(at: filePath)
    }

    // MARK: - Helpers

    private func ensureDirectoryExists() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: sessionsDirectory.path) {
            try? fm.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
        }
    }
}
