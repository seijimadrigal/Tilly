import Foundation
import Network
import TillyCore

@MainActor
@Observable
final class RemoteServer {
    var isRunning: Bool = false
    var connectedClients: Int = 0
    var port: UInt16 = 8742

    private var listener: NWListener?
    private var connections: [NWConnection] = []
    weak var appState: AppState?

    func start() {
        guard listener == nil else { return }

        let params = NWParameters.tcp
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true
        params.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        do {
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        } catch {
            print("[RemoteServer] Failed to create listener: \(error)")
            return
        }

        // Bonjour advertisement
        listener?.service = NWListener.Service(name: "Tilly", type: "_tilly._tcp")

        listener?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    self?.isRunning = true
                    print("[RemoteServer] Listening on port \(self?.port ?? 0)")
                case .failed(let error):
                    self?.isRunning = false
                    print("[RemoteServer] Listener failed: \(error)")
                case .cancelled:
                    self?.isRunning = false
                default:
                    break
                }
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                self?.handleNewConnection(connection)
            }
        }

        listener?.start(queue: .main)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        for conn in connections {
            conn.cancel()
        }
        connections.removeAll()
        connectedClients = 0
        isRunning = false
    }

    func broadcast(_ message: RemoteMessage) {
        guard let data = message.encoded() else { return }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "ws", metadata: [metadata])

        for conn in connections {
            conn.send(content: data, contentContext: context, isComplete: true, completion: .idempotent)
        }
    }

    // MARK: - Connection Handling

    private func handleNewConnection(_ connection: NWConnection) {
        connections.append(connection)
        connectedClients = connections.count
        print("[RemoteServer] Client connected (\(connectedClients) total)")

        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                if case .failed = state {
                    self?.removeConnection(connection)
                } else if case .cancelled = state {
                    self?.removeConnection(connection)
                }
            }
        }

        connection.start(queue: .main)
        receiveMessage(from: connection)
    }

    private func removeConnection(_ connection: NWConnection) {
        connections.removeAll { $0 === connection }
        connectedClients = connections.count
        print("[RemoteServer] Client disconnected (\(connectedClients) total)")
    }

    private func receiveMessage(from connection: NWConnection) {
        connection.receiveMessage { [weak self] data, context, _, error in
            Task { @MainActor in
                guard let self else { return }

                if let error {
                    print("[RemoteServer] Receive error: \(error)")
                    self.removeConnection(connection)
                    return
                }

                if let data, let message = RemoteMessage.decoded(from: data) {
                    await self.handleMessage(message, from: connection)
                }

                // Continue receiving
                self.receiveMessage(from: connection)
            }
        }
    }

    // MARK: - Message Dispatch

    private func handleMessage(_ message: RemoteMessage, from connection: NWConnection) async {
        guard let appState else { return }

        switch message.type {
        case .sendMessage:
            if let text = message.text {
                await appState.sendMessage(text)
            }

        case .listSessions:
            let summaries = appState.sessions.map { SessionSummary(from: $0) }
            send(RemoteMessage(type: .sessionList, sessions: summaries), to: connection)

        case .selectSession:
            if let id = message.sessionID,
               let session = appState.sessions.first(where: { $0.id == id }) {
                appState.selectSession(session)
                send(RemoteMessage(type: .fullSession, session: session), to: connection)
            } else {
                send(RemoteMessage(type: .error, error: "Session not found"), to: connection)
            }

        case .newSession:
            appState.createNewSession()
            if let session = appState.currentSession {
                send(RemoteMessage(type: .sessionCreated, session: session), to: connection)
            }

        case .askUserResponse:
            if let choice = message.text {
                appState.respondToAskUser(choice: choice)
            }

        default:
            break
        }
    }

    private func send(_ message: RemoteMessage, to connection: NWConnection) {
        guard let data = message.encoded() else { return }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "ws", metadata: [metadata])
        connection.send(content: data, contentContext: context, isComplete: true, completion: .idempotent)
    }
}
