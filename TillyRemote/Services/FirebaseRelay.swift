import Foundation
import FirebaseDatabase
import TillyCore

/// iOS reads sessions directly from Firebase persistent storage.
/// Commands (sendMessage, newSession) go through the relay channel.
/// Session data is read from /users/{uid}/sessions/{sid} directly.

@MainActor
@Observable
final class FirebaseRelayIOS {
    var isConnected: Bool = false
    var macOnline: Bool = false
    var sessions: [SessionSummary] = []
    var currentSession: Session?
    var streamingText: String = ""
    var isStreaming: Bool = false
    var errorMessage: String?

    var showAskUser: Bool = false
    var askUserQuestion: String = ""
    var askUserOptions: [String] = []

    private var dbRef: DatabaseReference?
    private var relayHandle: DatabaseHandle?
    private var macStatusHandle: DatabaseHandle?
    private var sessionIndexHandle: DatabaseHandle?
    private var currentSessionHandle: DatabaseHandle?
    private var userID: String?

    func start(userID: String) {
        guard !isConnected || self.userID != userID else { return }
        if isConnected { stop() }

        self.userID = userID
        let db = Database.database().reference()
        self.dbRef = db

        // Watch Mac online status
        macStatusHandle = db.child("users/\(userID)/profile/macOnline").observe(.value) { [weak self] snapshot in
            Task { @MainActor in
                self?.macOnline = snapshot.value as? Bool ?? false
            }
        }

        // Watch session index (auto-updates when Mac syncs)
        sessionIndexHandle = db.child("users/\(userID)/sessionIndex").observe(.value) { [weak self] snapshot in
            Task { @MainActor in
                self?.handleSessionIndex(snapshot)
            }
        }

        // Watch relay notifications from Mac
        relayHandle = db.child("users/\(userID)/relay/mac_to_ios").observe(.childAdded) { [weak self] snapshot in
            Task { @MainActor in
                guard let self else { return }
                self.handleRelayMessage(snapshot)
                snapshot.ref.removeValue()
            }
        }

        isConnected = true
        print("[FirebaseRelayIOS] Started for user \(userID)")
    }

    func stop() {
        guard let userID, let dbRef else { return }

        if let h = relayHandle { dbRef.child("users/\(userID)/relay/mac_to_ios").removeObserver(withHandle: h) }
        if let h = macStatusHandle { dbRef.child("users/\(userID)/profile/macOnline").removeObserver(withHandle: h) }
        if let h = sessionIndexHandle { dbRef.child("users/\(userID)/sessionIndex").removeObserver(withHandle: h) }
        stopWatchingCurrentSession()

        isConnected = false
        self.dbRef = nil
        self.userID = nil
    }

    // MARK: - Read sessions directly from Firebase

    private func handleSessionIndex(_ snapshot: DataSnapshot) {
        guard let list = snapshot.value as? [[String: Any]] else {
            sessions = []
            return
        }

        sessions = list.compactMap { dict -> SessionSummary? in
            guard let idStr = dict["id"] as? String,
                  let id = UUID(uuidString: idStr),
                  let title = dict["title"] as? String else { return nil }
            let count = dict["messageCount"] as? Int ?? 0
            let ts = dict["updatedAt"] as? TimeInterval ?? 0
            let providerID = dict["providerID"] as? String ?? ""
            let modelID = dict["modelID"] as? String ?? ""
            return SessionSummary(
                id: id, title: title, messageCount: count,
                updatedAt: Date(timeIntervalSince1970: ts),
                providerID: providerID, modelID: modelID
            )
        }
        print("[FirebaseRelayIOS] Session index updated: \(sessions.count) sessions")
    }

    /// Load a full session from Firebase persistent storage
    func selectSession(id: UUID) {
        guard let userID, let dbRef else { return }
        let path = "users/\(userID)/sessions/\(id.uuidString)"

        // Start watching this session for real-time updates
        stopWatchingCurrentSession()
        currentSessionHandle = dbRef.child(path).observe(.value) { [weak self] snapshot in
            Task { @MainActor in
                self?.handleSessionData(snapshot)
            }
        }
    }

    private func stopWatchingCurrentSession() {
        guard let userID, let dbRef else { return }
        if let h = currentSessionHandle, let session = currentSession {
            dbRef.child("users/\(userID)/sessions/\(session.id.uuidString)").removeObserver(withHandle: h)
            currentSessionHandle = nil
        }
    }

    private func handleSessionData(_ snapshot: DataSnapshot) {
        guard let dict = snapshot.value as? [String: Any] else {
            print("[FirebaseRelayIOS] Session snapshot is not a dictionary")
            return
        }

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: dict)
            let session = try JSONDecoder.remoteDecoder.decode(Session.self, from: jsonData)
            currentSession = session
            isStreaming = false
            streamingText = ""
            print("[FirebaseRelayIOS] Session loaded: \(session.title) (\(session.messages.count) msgs)")
        } catch {
            print("[FirebaseRelayIOS] Decode error: \(error)")
            // Try to print the raw JSON for debugging
            if let jsonData = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted),
               let raw = String(data: jsonData, encoding: .utf8) {
                print("[FirebaseRelayIOS] Raw JSON (first 500 chars): \(raw.prefix(500))")
            }
        }
    }

    // MARK: - Send commands to Mac

    func sendToMac(_ message: RemoteMessage) {
        guard let userID, let dbRef else { return }
        guard let data = message.encoded(),
              let json = try? JSONSerialization.jsonObject(with: data) else { return }
        print("[FirebaseRelayIOS] Sending: \(message.type.rawValue)")
        dbRef.child("users/\(userID)/relay/ios_to_mac").childByAutoId().setValue(json) { error, _ in
            if let error { print("[FirebaseRelayIOS] Write error: \(error.localizedDescription)") }
        }
    }

    func sendMessage(_ text: String) {
        isStreaming = true
        streamingText = ""
        if var session = currentSession {
            let userMsg = Message(role: .user, content: [.text(text)])
            session.appendMessage(userMsg)
            currentSession = session
        }
        sendToMac(RemoteMessage(type: .sendMessage, text: text))
    }

    func createNewSession() {
        sendToMac(RemoteMessage(type: .newSession))
    }

    func respondToAskUser(choice: String) {
        showAskUser = false
        sendToMac(RemoteMessage(type: .askUserResponse, text: choice))
    }

    // MARK: - Handle relay notifications (small messages only)

    private func handleRelayMessage(_ snapshot: DataSnapshot) {
        guard let dict = snapshot.value as? [String: Any],
              let jsonData = try? JSONSerialization.data(withJSONObject: dict),
              let message = RemoteMessage.decoded(from: jsonData) else { return }

        print("[FirebaseRelayIOS] Relay: \(message.type.rawValue)")

        switch message.type {
        case .streamDelta:
            if let delta = message.text { streamingText += delta }

        case .streamEnd:
            isStreaming = false
            // The session observer will auto-refresh when Mac syncs

        case .sessionCreated:
            if let id = message.sessionID {
                selectSession(id: id)
            }

        case .sessionSelected:
            // Mac confirmed session is synced — observer handles the rest
            break

        case .askUser:
            askUserQuestion = message.text ?? ""
            askUserOptions = message.options ?? []
            showAskUser = true

        case .error:
            errorMessage = message.error
            isStreaming = false

        default:
            break
        }
    }
}
