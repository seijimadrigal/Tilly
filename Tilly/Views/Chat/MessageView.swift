import SwiftUI
import TillyCore

// MARK: - Metadata Bar (used by AssistantTurnView)

struct MetadataBar: View {
    let metadata: MessageMetadata

    var body: some View {
        HStack(spacing: 10) {
            if let model = metadata.model {
                Label(model, systemImage: "cpu")
            }
            if let tokens = metadata.totalTokens {
                Label("\(tokens) tok", systemImage: "number")
            }
            if let latency = metadata.latencyMs {
                Label(latency < 1000 ? "\(latency)ms" : String(format: "%.1fs", Double(latency) / 1000.0), systemImage: "clock")
            }
        }
        .font(.caption2)
        .foregroundStyle(.quaternary)
        .padding(.top, 2)
    }
}
