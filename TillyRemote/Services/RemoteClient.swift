import Foundation
import Network
import TillyCore

@MainActor
@Observable
final class RemoteClient {
    enum ConnectionState: String {
        case disconnected = "Disconnected"
        case browsing = "Searching..."
        case connecting = "Connecting..."
        case connected = "Connected"
    }

    var state: ConnectionState = .disconnected
    var discoveredHosts: [(name: String, endpoint: NWEndpoint)] = []
    var sessions: [SessionSummary] = []
    var currentSession: Session?
    var streamingText: String = ""
    var isStreaming: Bool = false
    var errorMessage: String?

    // Ask user dialog relay
    var showAskUser: Bool = false
    var askUserQuestion: String = ""
    var askUserOptions: [String] = []

    private var browser: NWBrowser?
    private var connection: NWConnection?

    // MARK: - Bonjour Discovery

    func startBrowsing() {
        state = .browsing
        discoveredHosts = []
        errorMessage = nil

        let descriptor = NWBrowser.Descriptor.bonjour(type: "_tilly._tcp", domain: "local.")
        let params = NWParameters()
        params.includePeerToPeer = true

        browser = NWBrowser(for: descriptor, using: params)

        browser?.browseResultsChangedHandler = { [weak self] results, changes in
            Task { @MainActor in
                guard let self else { return }
                self.discoveredHosts = results.compactMap { result in
                    switch result.endpoint {
                    case .service(let name, let type, let domain, let interface):
                        print("[RemoteClient] Found: \(name) (\(type).\(domain))")
                        return (name: name, endpoint: result.endpoint)
                    default:
                        return nil
                    }
                }
            }
        }

        browser?.stateUpdateHandler = { [weak self] newState in
            Task { @MainActor in
                guard let self else { return }
                switch newState {
                case .ready:
                    print("[RemoteClient] Browser ready, searching...")
                case .failed(let error):
                    print("[RemoteClient] Browser failed: \(error)")
                    self.errorMessage = "Network browsing failed: \(error.localizedDescription)"
                    self.state = .disconnected
                case .cancelled:
                    print("[RemoteClient] Browser cancelled")
                default:
                    break
                }
            }
        }

        browser?.start(queue: .main)
    }

    func stopBrowsing() {
        browser?.cancel()
        browser = nil
    }

    // MARK: - Connection

    func connect(to endpoint: NWEndpoint) {
        state = .connecting
        errorMessage = nil

        // Create TCP params with WebSocket
        let params = NWParameters.tcp
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true
        params.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        connection = NWConnection(to: endpoint, using: params)

        connection?.stateUpdateHandler = { [weak self] newState in
            Task { @MainActor in
                guard let self else { return }
                switch newState {
                case .ready:
                    print("[RemoteClient] Connected!")
                    self.state = .connected
                    self.stopBrowsing()
                    self.receiveMessages()
                    // Request session list immediately
                    self.send(RemoteMessage(type: .listSessions))
                case .waiting(let error):
                    print("[RemoteClient] Waiting: \(error)")
                case .failed(let error):
                    print("[RemoteClient] Connection failed: \(error)")
                    self.errorMessage = "Connection failed: \(error.localizedDescription)"
                    self.state = .disconnected
                    self.connection = nil
                case .cancelled:
                    self.state = .disconnected
                    self.connection = nil
                default:
                    break
                }
            }
        }

        connection?.start(queue: .main)
    }

    func connectManual(host: String, port: UInt16) {
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!
        )
        connect(to: endpoint)
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        state = .disconnected
        sessions = []
        currentSession = nil
        streamingText = ""
        isStreaming = false
    }

    // MARK: - Send / Receive

    func send(_ message: RemoteMessage) {
        guard let data = message.encoded(), let connection else {
            print("[RemoteClient] Cannot send - no connection or encoding failed")
            return
        }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "ws", metadata: [metadata])
        connection.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed { error in
            if let error {
                print("[RemoteClient] Send error: \(error)")
            }
        })
    }

    func sendMessage(_ text: String) {
        isStreaming = true
        streamingText = ""
        send(RemoteMessage(type: .sendMessage, text: text))
    }

    func selectSession(id: UUID) {
        send(RemoteMessage(type: .selectSession, sessionID: id))
    }

    func createNewSession() {
        send(RemoteMessage(type: .newSession))
    }

    func respondToAskUser(choice: String) {
        showAskUser = false
        send(RemoteMessage(type: .askUserResponse, text: choice))
    }

    func refreshSessions() {
        send(RemoteMessage(type: .listSessions))
    }

    private func receiveMessages() {
        guard let connection else { return }
        connection.receiveMessage { [weak self] data, context, isComplete, error in
            Task { @MainActor in
                guard let self else { return }

                if let error {
                    print("[RemoteClient] Receive error: \(error)")
                    if self.state == .connected {
                        self.disconnect()
                    }
                    return
                }

                if let data {
                    if let message = RemoteMessage.decoded(from: data) {
                        self.handleMessage(message)
                    } else {
                        // Try to see what we got
                        let raw = String(data: data, encoding: .utf8) ?? "(binary)"
                        print("[RemoteClient] Could not decode message: \(raw.prefix(200))")
                    }
                }

                // Continue receiving if still connected
                if self.state == .connected {
                    self.receiveMessages()
                }
            }
        }
    }

    private func handleMessage(_ message: RemoteMessage) {
        switch message.type {
        case .sessionList:
            sessions = message.sessions ?? []
            print("[RemoteClient] Got \(sessions.count) sessions")

        case .fullSession:
            currentSession = message.session
            isStreaming = false
            streamingText = ""
            print("[RemoteClient] Got full session: \(message.session?.title ?? "nil")")

        case .sessionCreated:
            currentSession = message.session
            send(RemoteMessage(type: .listSessions))

        case .streamDelta:
            if let delta = message.text {
                streamingText += delta
            }

        case .streamEnd:
            isStreaming = false
            // Request the full updated session
            if let session = currentSession {
                send(RemoteMessage(type: .selectSession, sessionID: session.id))
            }

        case .askUser:
            askUserQuestion = message.text ?? ""
            askUserOptions = message.options ?? []
            showAskUser = true

        case .error:
            errorMessage = message.error
            print("[RemoteClient] Server error: \(message.error ?? "unknown")")
            isStreaming = false

        default:
            print("[RemoteClient] Unhandled message type: \(message.type.rawValue)")
        }
    }
}
