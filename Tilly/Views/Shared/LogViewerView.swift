import SwiftUI

/// Hidden diagnostic log viewer — accessible via Cmd+Shift+L.
struct LogViewerView: View {
    @State private var entries: [DiagnosticLogger.LogEntry] = []
    @State private var filterCategory: DiagnosticLogger.LogEntry.Category?
    @State private var searchText = ""

    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Diagnostic Log")
                    .font(.headline)

                Spacer()

                Picker("Filter", selection: $filterCategory) {
                    Text("All").tag(nil as DiagnosticLogger.LogEntry.Category?)
                    Text("Tool").tag(DiagnosticLogger.LogEntry.Category.tool as DiagnosticLogger.LogEntry.Category?)
                    Text("LLM").tag(DiagnosticLogger.LogEntry.Category.llm as DiagnosticLogger.LogEntry.Category?)
                    Text("Error").tag(DiagnosticLogger.LogEntry.Category.error as DiagnosticLogger.LogEntry.Category?)
                    Text("Agent").tag(DiagnosticLogger.LogEntry.Category.agent as DiagnosticLogger.LogEntry.Category?)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 300)

                Button {
                    let log = DiagnosticLogger.shared.exportLog()
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(log, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }

                Button {
                    let log = DiagnosticLogger.shared.exportLog()
                    let panel = NSSavePanel()
                    panel.allowedContentTypes = [.plainText]
                    panel.nameFieldStringValue = "tilly-diagnostic-\(Int(Date().timeIntervalSince1970)).log"
                    panel.begin { response in
                        if response == .OK, let url = panel.url {
                            try? log.write(to: url, atomically: true, encoding: .utf8)
                        }
                    }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }

                Button(role: .destructive) {
                    DiagnosticLogger.shared.clear()
                    entries = []
                } label: {
                    Label("Clear", systemImage: "trash")
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            TextField("Search logs...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .padding(.vertical, 4)

            List(filteredEntries) { entry in
                LogEntryRow(entry: entry)
            }
            .listStyle(.plain)

            HStack {
                Text("\(entries.count) entries")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("Cmd+Shift+L to toggle")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
        }
        .frame(minWidth: 600, minHeight: 400)
        .onAppear { entries = DiagnosticLogger.shared.entries }
        .onReceive(refreshTimer) { _ in
            entries = DiagnosticLogger.shared.entries
        }
    }

    private var filteredEntries: [DiagnosticLogger.LogEntry] {
        entries.reversed().filter { entry in
            let matchesCategory = filterCategory == nil || entry.category == filterCategory
            let matchesSearch = searchText.isEmpty ||
                entry.message.localizedCaseInsensitiveContains(searchText) ||
                (entry.detail?.localizedCaseInsensitiveContains(searchText) ?? false)
            return matchesCategory && matchesSearch
        }
    }
}

struct LogEntryRow: View {
    let entry: DiagnosticLogger.LogEntry
    @State private var showDetail = false

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(Self.formatter.string(from: entry.timestamp))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)

                Text(entry.category.rawValue)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(colorForCategory(entry.category))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(colorForCategory(entry.category).opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 3))

                Text(entry.message)
                    .font(.system(size: 11))
                    .lineLimit(showDetail ? nil : 1)
            }

            if showDetail, let detail = entry.detail {
                Text(detail)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(.leading, 70)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { showDetail.toggle() }
    }

    private func colorForCategory(_ cat: DiagnosticLogger.LogEntry.Category) -> Color {
        switch cat {
        case .tool: return .orange
        case .llm: return .blue
        case .error: return .red
        case .agent: return .purple
        case .firebase: return .green
        case .system: return .gray
        }
    }
}
