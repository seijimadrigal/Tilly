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
        guard let userID, let dbRef else { return }
        guard let data = message.encoded(),
              let json = try? JSONSerialization.jsonObject(with: data) else { return }

        dbRef.child("users/\(userID)/relay/mac_to_ios").childByAutoId().setValue(json)
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
        guard let userID, let dbRef else { return nil }

        do {
            let snapshot = try await dbRef.child("users/\(userID)/settings").getData()
            guard let dict = snapshot.value as? [String: Any] else { return nil }
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
        guard let appState else { return }

        switch message.type {
        case .sendMessage:
            if let text = message.text {
                await appState.sendMessage(text)
            }

        case .listSessions:
            let summaries = appState.sessions.map { SessionSummary(from: $0) }
            sendToiOS(RemoteMessage(type: .sessionList, sessions: summaries))

        case .selectSession:
            if let id = message.sessionID,
               let session = appState.sessions.first(where: { $0.id == id }) {
                appState.selectSession(session)
                sendToiOS(RemoteMessage(type: .fullSession, session: session))
            }

        case .newSession:
            appState.createNewSession()
            if let session = appState.currentSession {
                sendToiOS(RemoteMessage(type: .sessionCreated, session: session))
            }

        case .askUserResponse:
            if let choice = message.text {
                appState.respondToAskUser(choice: choice)
            }

        default:
            break
        }
    }
}
