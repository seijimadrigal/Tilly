import Foundation
import FirebaseDatabase
import TillyCore

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

        // Set offline hook — when Mac disconnects, mark offline
        profileRef.child("macOnline").onDisconnectSetValue(false)
        profileRef.child("lastSeen").onDisconnectSetValue(ServerValue.timestamp())

        // Listen for incoming messages from iOS
        let incomingRef = db.child("users/\(userID)/relay/ios_to_mac")
        incomingHandle = incomingRef.observe(.childAdded) { [weak self] snapshot in
            Task { @MainActor in
                guard let self else { return }
                self.handleIncoming(snapshot)
                // Clean up processed message
                snapshot.ref.removeValue()
            }
        }

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

    /// Send a message to iOS via Firebase
    func sendToiOS(_ message: RemoteMessage) {
        guard let userID, let dbRef else {
            print("[FirebaseRelay] sendToiOS failed: no userID or dbRef")
            return
        }
        guard let data = message.encoded(),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            print("[FirebaseRelay] sendToiOS failed: encoding error for type \(message.type.rawValue)")
            return
        }

        let size = data.count
        print("[FirebaseRelay] Sending \(message.type.rawValue) (\(size) bytes)")

        // Firebase has a ~16MB limit per write but large payloads are slow
        // For session data, strip image content to keep payloads small
        dbRef.child("users/\(userID)/relay/mac_to_ios").childByAutoId().setValue(json) { error, _ in
            if let error {
                print("[FirebaseRelay] Write error: \(error.localizedDescription)")
            }
        }
    }

    /// Sync settings to Firebase
    func syncSettings(providerID: String, modelID: String) {
        guard let userID, let dbRef else { return }
        dbRef.child("users/\(userID)/settings").setValue([
            "selectedProviderID": providerID,
            "selectedModelID": modelID,
        ])
    }

    /// Load settings from Firebase
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

    /// Nonisolated helper to avoid sending DatabaseReference across isolation boundaries
    nonisolated private func fetchDictionary(at path: String) async throws -> [String: Any]? {
        let ref = Database.database().reference().child(path)
        let snapshot = try await ref.getData()
        return snapshot.value as? [String: Any]
    }

    // MARK: - Handle Incoming

    private func handleIncoming(_ snapshot: DataSnapshot) {
        guard let dict = snapshot.value as? [String: Any],
              let jsonData = try? JSONSerialization.data(withJSONObject: dict),
              let message = RemoteMessage.decoded(from: jsonData) else {
            return
        }

        Task { @MainActor in
            await processMessage(message)
        }
    }

    private func processMessage(_ message: RemoteMessage) async {
        guard let appState else {
            print("[FirebaseRelay] processMessage: appState is nil")
            return
        }

        print("[FirebaseRelay] Processing: \(message.type.rawValue)")

        switch message.type {
        case .sendMessage:
            if let text = message.text {
                print("[FirebaseRelay] Executing sendMessage: \(text.prefix(50))")
                await appState.sendMessage(text)
            }

        case .listSessions:
            let summaries = appState.sessions.map { SessionSummary(from: $0) }
            print("[FirebaseRelay] Sending \(summaries.count) sessions to iOS")
            sendToiOS(RemoteMessage(type: .sessionList, sessions: summaries))

        case .selectSession:
            // Don't change Mac's active session — just return the data
            if let id = message.sessionID,
               let session = appState.sessions.first(where: { $0.id == id }) {
                // Strip image data from messages to keep payload small
                let lightSession = stripHeavyContent(from: session)
                print("[FirebaseRelay] Sending session '\(session.title)' (\(session.messages.count) msgs)")
                sendToiOS(RemoteMessage(type: .fullSession, session: lightSession))
            } else {
                print("[FirebaseRelay] Session not found for id: \(message.sessionID?.uuidString ?? "nil")")
            }

        case .newSession:
            appState.createNewSession()
            if let session = appState.currentSession {
                sendToiOS(RemoteMessage(type: .sessionCreated, session: stripHeavyContent(from: session)))
            }

        case .askUserResponse:
            if let choice = message.text {
                appState.respondToAskUser(choice: choice)
            }

        default:
            break
        }
    }

    /// Strip heavy content and limit messages for Firebase transfer.
    /// Firebase drops connection on large writes (~100KB+).
    private func stripHeavyContent(from session: Session) -> Session {
        var light = session
        // Only send last 30 messages to keep payload under 20KB
        let recentMessages = Array(session.messages.suffix(30))
        light.messages = recentMessages.map { msg in
            var m = msg
            m.content = msg.content.compactMap { block in
                switch block {
                case .text(let text):
                    // Truncate very long text blocks
                    if text.count > 2000 {
                        return .text(String(text.prefix(2000)) + "\n... [truncated]")
                    }
                    return block
                case .image(_, let mimeType):
                    return .text("[Image: \(mimeType)]")
                case .fileReference:
                    return block
                }
            }
            // Strip tool call arguments if very long
            if let toolCalls = m.toolCalls {
                m.toolCalls = toolCalls.map { tc in
                    let args = tc.function.arguments
                    if args.count > 500 {
                        return ToolCall(id: tc.id, function: ToolCall.FunctionCall(
                            name: tc.function.name,
                            arguments: String(args.prefix(500)) + "..."
                        ))
                    }
                    return tc
                }
            }
            return m
        }
        return light
    }
}
