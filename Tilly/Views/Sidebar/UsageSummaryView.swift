import SwiftUI
import TillyCore

struct UsageSummaryView: View {
    let summary: UsageSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .font(.caption)
                    .foregroundStyle(.blue)
                Text("Session Usage")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if summary.totalRequests == 0 {
                Text("No usage yet")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                HStack(spacing: 12) {
                    StatPill(label: "Tokens", value: formatNumber(summary.totalTokens))
                    StatPill(label: "Cost", value: "$\(String(format: "%.4f", summary.totalCost))")
                    StatPill(label: "Calls", value: "\(summary.totalRequests)")
                }

                if !summary.byModel.isEmpty {
                    ForEach(Array(summary.byModel.keys.sorted()), id: \.self) { model in
                        if let info = summary.byModel[model] {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(.blue.opacity(0.3))
                                    .frame(width: 6, height: 6)
                                Text(model)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(formatNumber(info.tokens)) tok")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func formatNumber(_ n: Int) -> String {
        if n >= 1_000_000 { return "\(n / 1_000_000)M" }
        if n >= 1_000 { return "\(n / 1_000)K" }
        return "\(n)"
    }
}

struct StatPill: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
