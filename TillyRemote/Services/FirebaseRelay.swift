import Foundation
import FirebaseDatabase
import TillyCore

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

    // Debounce: don't update UI more than once per second for session data
    private var lastSessionUpdate: Date = .distantPast

    func start(userID: String) {
        guard !isConnected || self.userID != userID else { return }
        if isConnected { stop() }

        self.userID = userID
        let db = Database.database().reference()
        self.dbRef = db

        macStatusHandle = db.child("users/\(userID)/profile/macOnline").observe(.value) { [weak self] snapshot in
            Task { @MainActor in
                self?.macOnline = snapshot.value as? Bool ?? false
            }
        }

        sessionIndexHandle = db.child("users/\(userID)/sessionIndex").observe(.value) { [weak self] snapshot in
            Task { @MainActor in
                self?.handleSessionIndex(snapshot)
            }
        }

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

    // MARK: - Session Index

    private func handleSessionIndex(_ snapshot: DataSnapshot) {
        guard let list = snapshot.value as? [[String: Any]] else {
            sessions = []
            return
        }

        sessions = list.compactMap { dict -> SessionSummary? in
            guard let idStr = dict["id"] as? String,
                  let id = UUID(uuidString: idStr),
                  let title = dict["title"] as? String else { return nil }
            return SessionSummary(
                id: id, title: title,
                messageCount: dict["messageCount"] as? Int ?? 0,
                updatedAt: Date(timeIntervalSince1970: dict["updatedAt"] as? TimeInterval ?? 0),
                providerID: dict["providerID"] as? String ?? "",
                modelID: dict["modelID"] as? String ?? ""
            )
        }
        print("[FirebaseRelayIOS] Session index: \(sessions.count) sessions")
    }

    // MARK: - Session Watching

    func selectSession(id: UUID) {
        guard let userID, let dbRef else { return }
        stopWatchingCurrentSession()
        let path = "users/\(userID)/sessions/\(id.uuidString)"
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
        // Debounce — skip if updated less than 0.5s ago
        let now = Date()
        guard now.timeIntervalSince(lastSessionUpdate) > 0.5 else { return }
        lastSessionUpdate = now

        guard let dict = snapshot.value as? [String: Any] else { return }

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: dict)
            let session = try JSONDecoder.remoteDecoder.decode(Session.self, from: jsonData)

            // Only update if message count changed or this is initial load
            if currentSession?.id != session.id || currentSession?.messages.count != session.messages.count {
                currentSession = session
                print("[FirebaseRelayIOS] Session: \(session.title) (\(session.messages.count) msgs)")
            }
        } catch {
            print("[FirebaseRelayIOS] Decode error: \(error)")
        }
    }

    // MARK: - Send to Mac

    func sendToMac(_ message: RemoteMessage) {
        guard let userID, let dbRef else { return }
        guard let data = message.encoded(),
              let json = try? JSONSerialization.jsonObject(with: data) else { return }
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

    // MARK: - Relay Messages (small notifications only)

    private func handleRelayMessage(_ snapshot: DataSnapshot) {
        guard let dict = snapshot.value as? [String: Any],
              let jsonData = try? JSONSerialization.data(withJSONObject: dict),
              let message = RemoteMessage.decoded(from: jsonData) else { return }

        switch message.type {
        case .streamDelta:
            if let delta = message.text { streamingText += delta }

        case .streamEnd:
            isStreaming = false
            streamingText = ""
            // Reset debounce so the final session update comes through immediately
            lastSessionUpdate = .distantPast

        case .sessionCreated:
            if let id = message.sessionID {
                selectSession(id: id)
            }

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
