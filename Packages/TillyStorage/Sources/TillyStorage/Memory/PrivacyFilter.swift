import Foundation

/// Detects sensitive data in memory content and classifies privacy level.
/// Prevents secrets (API keys, passwords, tokens) from being synced to cloud.
public final class PrivacyFilter: @unchecked Sendable {

    public enum PrivacyLevel: String, Sendable {
        case `public` = "public"
        case project = "project"
        case `private` = "private"
        case sensitive = "sensitive"
    }

    private static let sensitivePatterns: [(pattern: String, label: String)] = [
        (#"sk-[a-zA-Z0-9]{20,}"#, "OpenAI API key"),
        (#"ghp_[a-zA-Z0-9]{36}"#, "GitHub PAT"),
        (#"gho_[a-zA-Z0-9]{36}"#, "GitHub OAuth token"),
        (#"github_pat_[a-zA-Z0-9_]{82}"#, "GitHub fine-grained PAT"),
        (#"AKIA[A-Z0-9]{16}"#, "AWS Access Key"),
        (#"mc_[a-f0-9]{40,}"#, "Memcloud API key"),
        (#"xoxb-[0-9]{10,}-[a-zA-Z0-9]+"#, "Slack Bot token"),
        (#"xoxp-[0-9]{10,}-[a-zA-Z0-9]+"#, "Slack User token"),
        (#"-----BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----"#, "Private key"),
        (#"Bearer\s+[a-zA-Z0-9\-._~+/]{20,}=*"#, "Bearer token"),
        (#"(?i)password\s*[:=]\s*['"][^'"]{4,}['"]"#, "Password assignment"),
        (#"(?i)secret\s*[:=]\s*['"][^'"]{4,}['"]"#, "Secret assignment"),
        (#"(?i)api_key\s*[:=]\s*['"][^'"]{8,}['"]"#, "API key assignment"),
        (#"(?i)token\s*[:=]\s*['"][^'"]{8,}['"]"#, "Token assignment"),
    ]

    private static let compiledPatterns: [(regex: NSRegularExpression, label: String)] = {
        sensitivePatterns.compactMap { item in
            guard let regex = try? NSRegularExpression(pattern: item.pattern) else { return nil }
            return (regex, item.label)
        }
    }()

    /// Classify content by privacy level.
    public static func classify(_ content: String) -> PrivacyLevel {
        if containsSensitiveData(content) { return .sensitive }
        let lower = content.lowercased()
        if lower.contains("password") || lower.contains("credential") || lower.contains("ssn") || lower.contains("social security") {
            return .private
        }
        return .public
    }

    /// Check if content contains any sensitive patterns.
    public static func containsSensitiveData(_ content: String) -> Bool {
        let range = NSRange(content.startIndex..., in: content)
        return compiledPatterns.contains { item in
            item.regex.firstMatch(in: content, range: range) != nil
        }
    }

    /// Redact sensitive patterns from content, replacing with [REDACTED:<label>].
    public static func redact(_ content: String) -> String {
        var result = content
        for item in compiledPatterns {
            let range = NSRange(result.startIndex..., in: result)
            result = item.regex.stringByReplacingMatches(
                in: result, range: range,
                withTemplate: "[REDACTED:\(item.label)]"
            )
        }
        return result
    }
}
