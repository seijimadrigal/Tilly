import SwiftUI
import TillyCore

struct RemoteConnectionView: View {
    @Environment(RemoteClient.self) private var client
    @State private var manualHost = ""
    @State private var manualPort = "8742"

    var body: some View {
        List {
            // Error banner
            if let error = client.errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            Section("Discovered Macs") {
                if client.discoveredHosts.isEmpty {
                    HStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(0.8)
                        VStack(alignment: .leading) {
                            Text("Searching local network...")
                                .foregroundStyle(.secondary)
                            Text("Make sure Tilly is running on your Mac")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 4)
                } else {
                    ForEach(client.discoveredHosts, id: \.name) { host in
                        Button {
                            client.connect(to: host.endpoint)
                        } label: {
                            HStack {
                                Image(systemName: "desktopcomputer")
                                    .foregroundStyle(.blue)
                                    .font(.title3)
                                VStack(alignment: .leading) {
                                    Text(host.name)
                                        .font(.body)
                                    Text("Tap to connect")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section("Manual Connection") {
                TextField("IP Address (e.g. 192.168.1.100)", text: $manualHost)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.numbersAndPunctuation)

                TextField("Port", text: $manualPort)
                    .keyboardType(.numberPad)

                Button("Connect") {
                    if let port = UInt16(manualPort), !manualHost.isEmpty {
                        client.connectManual(host: manualHost, port: port)
                    }
                }
                .disabled(manualHost.isEmpty)
            }

            Section {
                Button("Refresh") {
                    client.stopBrowsing()
                    client.startBrowsing()
                }
            }
        }
        .navigationTitle("Connect to Mac")
        .onAppear {
            if client.state == .disconnected || client.state == .browsing {
                client.startBrowsing()
            }
        }
    }
}
