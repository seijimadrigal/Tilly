import Foundation
import FirebaseDatabase
import TillyCore

/// Firebase structure:
/// /users/{uid}/
///   profile/          — macOnline, lastSeen
///   settings/         — selectedProviderID, selectedModelID
///   sessions/{sid}/   — full session JSON (persistent, both devices read)
///   relay/
///     ios_to_mac/     — commands from iOS (ephemeral)
///     mac_to_ios/     — small notifications (ephemeral)

@MainActor
@Observable
final class FirebaseRelay {
    var isConnected: Bool = false
    weak var appState: AppState?

    private var dbRef: DatabaseReference?
    private var incomingHandle: DatabaseHandle?
    private var userID: String?

    func start(userID: String) {
        guard !isConnected || self.userID != userID else { return }
        if isConnected { stop() }

        self.userID = userID
        let db = Database.database().reference()
        self.dbRef = db

        // Mark Mac as online
        let profileRef = db.child("users/\(userID)/profile")
        profileRef.child("macOnline").setValue(true)
        profileRef.child("lastSeen").setValue(ServerValue.timestamp())
        profileRef.child("macOnline").onDisconnectSetValue(false)
        profileRef.child("lastSeen").onDisconnectSetValue(ServerValue.timestamp())

        // Listen for commands from iOS
        let incomingRef = db.child("users/\(userID)/relay/ios_to_mac")
        incomingHandle = incomingRef.observe(.childAdded) { [weak self] snapshot in
            Task { @MainActor in
                guard let self else { return }
                self.handleIncoming(snapshot)
                snapshot.ref.removeValue()
            }
        }

        // Sync all existing sessions to Firebase
        syncAllSessions()

        isConnected = true
        print("[FirebaseRelay] Started for user \(userID)")
    }

    func stop() {
        guard let userID, let dbRef else { return }

        if let handle = incomingHandle {
            dbRef.child("users/\(userID)/relay/ios_to_mac").removeObserver(withHandle: handle)
        }

        dbRef.child("users/\(userID)/profile/macOnline").setValue(false)
        dbRef.child("users/\(userID)/profile/lastSeen").setValue(ServerValue.timestamp())

        isConnected = false
        self.dbRef = nil
        self.userID = nil
        print("[FirebaseRelay] Stopped")
    }

    // MARK: - Session Sync (persistent storage, not relay)

    /// Write a single session to Firebase. Called on every session update.
    func syncSession(_ session: Session) {
        guard let userID, let dbRef else { return }
        let path = "users/\(userID)/sessions/\(session.id.uuidString)"

        // Convert to lightweight dict — strip binary image data
        let lightSession = stripImages(from: session)
        guard let data = try? JSONEncoder.remoteEncoder.encode(lightSession),
              let json = try? JSONSerialization.jsonObject(with: data) else { return }

        dbRef.child(path).setValue(json) { error, _ in
            if let error {
                print("[FirebaseRelay] Session sync error: \(error.localizedDescription)")
            }
        }
    }

    /// Sync all sessions on startup
    func syncAllSessions() {
        guard let appState else { return }
        for session in appState.sessions {
            syncSession(session)
        }
        // Also write session index (lightweight list)
        syncSessionIndex()
    }

    /// Write a lightweight session index for fast listing
    func syncSessionIndex() {
        guard let userID, let dbRef, let appState else { return }
        let index = appState.sessions.map { session -> [String: Any] in
            [
                "id": session.id.uuidString,
                "title": session.title,
                "messageCount": session.messages.count,
                "updatedAt": session.updatedAt.timeIntervalSince1970,
                "providerID": session.providerID,
                "modelID": session.modelID,
            ]
        }
        dbRef.child("users/\(userID)/sessionIndex").setValue(index)
    }

    /// Delete a session from Firebase
    func deleteSession(_ sessionID: UUID) {
        guard let userID, let dbRef else { return }
        dbRef.child("users/\(userID)/sessions/\(sessionID.uuidString)").removeValue()
        syncSessionIndex()
    }

    // MARK: - Small relay messages (commands + notifications)

    func sendToiOS(_ message: RemoteMessage) {
        guard let userID, let dbRef else { return }
        guard let data = message.encoded(),
              let json = try? JSONSerialization.jsonObject(with: data) else { return }

        let size = data.count
        print("[FirebaseRelay] Sending \(message.type.rawValue) (\(size) bytes)")

        dbRef.child("users/\(userID)/relay/mac_to_ios").childByAutoId().setValue(json) { error, _ in
            if let error {
                print("[FirebaseRelay] Write error: \(error.localizedDescription)")
            }
        }
    }

    func syncSettings(providerID: String, modelID: String) {
        guard let userID, let dbRef else { return }
        dbRef.child("users/\(userID)/settings").setValue([
            "selectedProviderID": providerID,
            "selectedModelID": modelID,
        ])
    }

    func loadSettings() async -> (providerID: String, modelID: String)? {
        guard let userID else { return nil }
        let path = "users/\(userID)/settings"
        do {
            let dict = try await fetchDictionary(at: path)
            guard let dict else { return nil }
            let providerID = dict["selectedProviderID"] as? String ?? ""
            let modelID = dict["selectedModelID"] as? String ?? ""
            if !providerID.isEmpty && !modelID.isEmpty {
                return (providerID, modelID)
            }
            return nil
        } catch {
            print("[FirebaseRelay] Failed to load settings: \(error)")
            return nil
        }
    }

    nonisolated private func fetchDictionary(at path: String) async throws -> [String: Any]? {
        let ref = Database.database().reference().child(path)
        let snapshot = try await ref.getData()
        return snapshot.value as? [String: Any]
    }

    // MARK: - Handle Incoming Commands

    private func handleIncoming(_ snapshot: DataSnapshot) {
        guard let dict = snapshot.value as? [String: Any],
              let jsonData = try? JSONSerialization.data(withJSONObject: dict),
              let message = RemoteMessage.decoded(from: jsonData) else { return }

        Task { @MainActor in
            await processMessage(message)
        }
    }

    private func processMessage(_ message: RemoteMessage) async {
        guard let appState else { return }
        print("[FirebaseRelay] Processing: \(message.type.rawValue)")

        switch message.type {
        case .sendMessage:
            if let text = message.text {
                await appState.sendMessage(text)
            }

        case .listSessions:
            // Sync index instead of sending via relay
            syncSessionIndex()
            // Also send a small notification
            sendToiOS(RemoteMessage(type: .sessionList))

        case .selectSession:
            // Re-sync the requested session to Firebase persistent storage
            if let id = message.sessionID,
               let session = appState.sessions.first(where: { $0.id == id }) {
                syncSession(session)
                sendToiOS(RemoteMessage(type: .sessionSelected, sessionID: id))
            }

        case .newSession:
            appState.createNewSession()
            if let session = appState.currentSession {
                syncSession(session)
                syncSessionIndex()
                sendToiOS(RemoteMessage(type: .sessionCreated, sessionID: session.id))
            }

        case .askUserResponse:
            if let choice = message.text {
                appState.respondToAskUser(choice: choice)
            }

        default:
            break
        }
    }

    // MARK: - Helpers

    private func stripImages(from session: Session) -> Session {
        var light = session
        light.messages = session.messages.map { msg in
            var m = msg
            m.content = msg.content.map { block in
                switch block {
                case .image(_, let mimeType):
                    return .text("[Image: \(mimeType)]")
                default:
                    return block
                }
            }
            return m
        }
        return light
    }
}
