import SwiftUI
import TillyCore

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var showDiagnosticLog = false

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            if appState.currentSession != nil {
                ChatView()
            } else {
                ContentUnavailableView(
                    "No Chat Selected",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Create a new chat or select an existing one.")
                )
            }
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 400)
        .frame(minWidth: 800, minHeight: 500)
        .sheet(isPresented: Binding(
            get: { appState.showAskUserDialog },
            set: { _ in }
        )) {
            AskUserDialogView()
                .environment(appState)
        }
        .sheet(isPresented: $showDiagnosticLog) {
            LogViewerView()
        }
        .onChange(of: showDiagnosticLog) {
            Task { @MainActor in
                DiagnosticLogger.shared.showLogViewer = showDiagnosticLog
            }
        }
        .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
            if DiagnosticLogger.shared.showLogViewer != showDiagnosticLog {
                showDiagnosticLog = DiagnosticLogger.shared.showLogViewer
            }
        }
    }
}

// MARK: - Ask User Dialog

struct AskUserDialogView: View {
    @Environment(AppState.self) private var appState
    @State private var customInput = ""

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "questionmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
                Text("Tilly needs your input")
                    .font(.headline)
            }

            Text(appState.askUserQuestion)
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Divider()

            // 3 preset options
            VStack(spacing: 8) {
                ForEach(Array(appState.askUserOptions.enumerated()), id: \.offset) { index, option in
                    Button {
                        appState.respondToAskUser(choice: option)
                    } label: {
                        HStack {
                            Text("\(index + 1)")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .frame(width: 24, height: 24)
                                .background(Circle().fill(colorForIndex(index)))

                            Text(option)
                                .font(.body)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.controlBackgroundColor)))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)

            Divider()

            // Custom input (4th option)
            VStack(spacing: 8) {
                Text("Or type your own response:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    TextField("Type here...", text: $customInput)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            if !customInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                appState.respondToAskUser(choice: customInput)
                            }
                        }

                    Button {
                        appState.respondToAskUser(choice: customInput)
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                    .disabled(customInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(.horizontal)
        }
        .padding(24)
        .frame(width: 460)
        .interactiveDismissDisabled()
    }

    private func colorForIndex(_ index: Int) -> Color {
        switch index {
        case 0: return .blue
        case 1: return .orange
        case 2: return .green
        default: return .gray
        }
    }
}
