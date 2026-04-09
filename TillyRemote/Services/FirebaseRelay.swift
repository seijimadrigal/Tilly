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

    // Ask user relay
    var showAskUser: Bool = false
    var askUserQuestion: String = ""
    var askUserOptions: [String] = []

    private var dbRef: DatabaseReference?
    private var incomingHandle: DatabaseHandle?
    private var macStatusHandle: DatabaseHandle?
    private var userID: String?

    func start(userID: String) {
        // Prevent multiple starts
        guard !isConnected || self.userID != userID else { return }
        if isConnected { stop() }

        self.userID = userID
        let db = Database.database().reference()
        self.dbRef = db

        // Watch Mac online status
        let profileRef = db.child("users/\(userID)/profile")
        macStatusHandle = profileRef.child("macOnline").observe(.value) { [weak self] snapshot in
            Task { @MainActor in
                self?.macOnline = snapshot.value as? Bool ?? false
            }
        }

        // Listen for incoming messages from Mac
        let incomingRef = db.child("users/\(userID)/relay/mac_to_ios")
        incomingHandle = incomingRef.observe(.childAdded) { [weak self] snapshot in
            Task { @MainActor in
                guard let self else { return }
                self.handleIncoming(snapshot)
                snapshot.ref.removeValue()
            }
        }

        isConnected = true
        print("[FirebaseRelayIOS] Started for user \(userID)")
    }

    func stop() {
        guard let userID, let dbRef else { return }

        if let handle = incomingHandle {
            dbRef.child("users/\(userID)/relay/mac_to_ios").removeObserver(withHandle: handle)
        }
        if let handle = macStatusHandle {
            dbRef.child("users/\(userID)/profile/macOnline").removeObserver(withHandle: handle)
        }

        isConnected = false
        self.dbRef = nil
        self.userID = nil
    }

    /// Send a message to Mac via Firebase
    func sendToMac(_ message: RemoteMessage) {
        guard let userID, let dbRef else { return }
        guard let data = message.encoded(),
              let json = try? JSONSerialization.jsonObject(with: data) else { return }
        dbRef.child("users/\(userID)/relay/ios_to_mac").childByAutoId().setValue(json)
    }

    func sendMessage(_ text: String) {
        isStreaming = true
        streamingText = ""
        sendToMac(RemoteMessage(type: .sendMessage, text: text))
    }

    func requestSessions() {
        sendToMac(RemoteMessage(type: .listSessions))
    }

    func selectSession(id: UUID) {
        sendToMac(RemoteMessage(type: .selectSession, sessionID: id))
    }

    func createNewSession() {
        sendToMac(RemoteMessage(type: .newSession))
    }

    func respondToAskUser(choice: String) {
        showAskUser = false
        sendToMac(RemoteMessage(type: .askUserResponse, text: choice))
    }

    // MARK: - Handle Incoming

    private func handleIncoming(_ snapshot: DataSnapshot) {
        guard let dict = snapshot.value as? [String: Any],
              let jsonData = try? JSONSerialization.data(withJSONObject: dict),
              let message = RemoteMessage.decoded(from: jsonData) else { return }

        switch message.type {
        case .sessionList:
            sessions = message.sessions ?? []

        case .fullSession:
            currentSession = message.session
            isStreaming = false
            streamingText = ""

        case .sessionCreated:
            currentSession = message.session
            requestSessions()

        case .streamDelta:
            if let delta = message.text {
                streamingText += delta
            }

        case .streamEnd:
            isStreaming = false
            if let session = currentSession {
                sendToMac(RemoteMessage(type: .selectSession, sessionID: session.id))
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
