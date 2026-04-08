import SwiftUI
import TillyCore

struct RemoteConnectionView: View {
    @Environment(RemoteClient.self) private var client
    @State private var manualHost = ""
    @State private var manualPort = "8742"

    var body: some View {
        List {
            Section("Discovered Macs") {
                if client.discoveredHosts.isEmpty {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Searching local network...")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(client.discoveredHosts, id: \.name) { host in
                        Button {
                            client.connect(to: host.endpoint)
                        } label: {
                            HStack {
                                Image(systemName: "desktopcomputer")
                                    .foregroundStyle(.blue)
                                Text(host.name)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section("Manual Connection") {
                TextField("IP Address", text: $manualHost)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                TextField("Port", text: $manualPort)
                    .keyboardType(.numberPad)

                Button("Connect") {
                    if let port = UInt16(manualPort) {
                        client.connectManual(host: manualHost, port: port)
                    }
                }
                .disabled(manualHost.isEmpty)
            }
        }
        .onAppear {
            client.startBrowsing()
        }
        .onDisappear {
            client.stopBrowsing()
        }
    }
}
