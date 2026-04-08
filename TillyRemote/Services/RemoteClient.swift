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

        let params = NWParameters()
        params.includePeerToPeer = true
        browser = NWBrowser(for: .bonjour(type: "_tilly._tcp", domain: nil), using: params)

        browser?.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                self?.discoveredHosts = results.compactMap { result in
                    switch result.endpoint {
                    case .service(let name, _, _, _):
                        return (name: name, endpoint: result.endpoint)
                    default:
                        return nil
                    }
                }
            }
        }

        browser?.stateUpdateHandler = { [weak self] newState in
            Task { @MainActor in
                if case .failed = newState {
                    self?.state = .disconnected
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
        stopBrowsing()

        let params = NWParameters.tcp
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true
        params.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        connection = NWConnection(to: endpoint, using: params)

        connection?.stateUpdateHandler = { [weak self] newState in
            Task { @MainActor in
                switch newState {
                case .ready:
                    self?.state = .connected
                    self?.receiveMessages()
                    self?.send(RemoteMessage(type: .listSessions))
                case .failed, .cancelled:
                    self?.state = .disconnected
                    self?.connection = nil
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
    }

    // MARK: - Send / Receive

    func send(_ message: RemoteMessage) {
        guard let data = message.encoded(), let connection else { return }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "ws", metadata: [metadata])
        connection.send(content: data, contentContext: context, isComplete: true, completion: .idempotent)
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

    private func receiveMessages() {
        connection?.receiveMessage { [weak self] data, context, _, error in
            Task { @MainActor in
                guard let self else { return }

                if let data, let message = RemoteMessage.decoded(from: data) {
                    self.handleMessage(message)
                }

                if error == nil {
                    self.receiveMessages()
                }
            }
        }
    }

    private func handleMessage(_ message: RemoteMessage) {
        switch message.type {
        case .sessionList:
            sessions = message.sessions ?? []

        case .fullSession:
            currentSession = message.session
            isStreaming = false

        case .sessionCreated:
            currentSession = message.session
            send(RemoteMessage(type: .listSessions))

        case .streamDelta:
            if let delta = message.text {
                streamingText += delta
            }

        case .streamEnd:
            isStreaming = false

        case .askUser:
            askUserQuestion = message.text ?? ""
            askUserOptions = message.options ?? []
            showAskUser = true

        case .error:
            print("[RemoteClient] Error: \(message.error ?? "unknown")")
            isStreaming = false

        default:
            break
        }
    }
}
