import Foundation
import TillyCore
#if os(macOS)
import Security
import AppKit
#endif

/// Access macOS Keychain passwords with explicit user approval.
/// NEVER exposes raw passwords to the LLM — only confirms actions or copies to clipboard.
public final class KeychainPasswordTool: ToolExecutable, @unchecked Sendable {
    /// Handler for user approval — set by AppState (uses ask_user flow).
    public var approvalHandler: (@MainActor (String, [String]) async -> String)?

    public init() {}

    public var definition: ToolDefinition {
        ToolDefinition(
            function: ToolDefinition.FunctionDef(
                name: "keychain",
                description: "Access macOS Keychain passwords. REQUIRES user approval for every action. Actions: 'search' finds accounts matching a query, 'autofill' copies a password to clipboard for pasting (password is NEVER shown to the agent), 'list_accounts' shows saved account names/URLs.",
                parameters: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "action": .object(["type": .string("string"), "enum": .array([.string("search"), .string("autofill"), .string("list_accounts")]), "description": .string("Action to perform.")]),
                        "query": .object(["type": .string("string"), "description": .string("Search query — domain name, app name, or account (for search/autofill).")]),
                    ]),
                    "required": .array([.string("action")]),
                ])
            )
        )
    }

    public func execute(arguments: String) async throws -> ToolResult {
        #if os(macOS)
        struct Args: Decodable { let action: String; let query: String? }
        guard let data = arguments.data(using: .utf8) else { throw TillyError.toolExecutionFailed("Invalid args") }
        let args = try JSONDecoder().decode(Args.self, from: data)

        switch args.action {
        case "search":
            guard let query = args.query, !query.isEmpty else {
                return ToolResult(content: "Query required for search", isError: true)
            }
            return searchKeychain(query: query)

        case "list_accounts":
            return listAccounts(query: args.query)

        case "autofill":
            guard let query = args.query, !query.isEmpty else {
                return ToolResult(content: "Query required for autofill", isError: true)
            }
            return await autofillPassword(query: query)

        default:
            return ToolResult(content: "Unknown action: \(args.action)", isError: true)
        }
        #else
        return ToolResult(content: "Keychain is only available on macOS.", isError: true)
        #endif
    }

    #if os(macOS)
    // MARK: - Search

    private func searchKeychain(query: String) -> ToolResult {
        let accounts = findAccounts(matching: query)
        if accounts.isEmpty {
            return ToolResult(content: "No keychain entries found for '\(query)'")
        }

        var result = "Found \(accounts.count) keychain entries for '\(query)':\n\n"
        for (i, account) in accounts.enumerated() {
            result += "\(i + 1). \(account.label)\n"
            if !account.server.isEmpty { result += "   Server: \(account.server)\n" }
            if !account.account.isEmpty { result += "   Account: \(account.account)\n" }
            result += "\n"
        }
        result += "Use autofill to copy a password to clipboard (requires user approval)."
        return ToolResult(content: result)
    }

    // MARK: - List Accounts

    private func listAccounts(query: String?) -> ToolResult {
        let accounts = findAccounts(matching: query ?? "")
        if accounts.isEmpty {
            return ToolResult(content: query != nil ? "No accounts matching '\(query!)'" : "No saved accounts found")
        }

        var result = "Saved accounts (\(accounts.count)):\n\n"
        for account in accounts.prefix(30) {
            result += "• \(account.label)"
            if !account.account.isEmpty { result += " (\(account.account))" }
            result += "\n"
        }
        if accounts.count > 30 { result += "... and \(accounts.count - 30) more\n" }
        return ToolResult(content: result)
    }

    // MARK: - Autofill (requires user approval)

    private func autofillPassword(query: String) async -> ToolResult {
        let accounts = findAccounts(matching: query)
        guard let account = accounts.first else {
            return ToolResult(content: "No account found for '\(query)'", isError: true)
        }

        // Request user approval
        guard let handler = approvalHandler else {
            return ToolResult(content: "Cannot autofill — no approval handler configured", isError: true)
        }

        let question = "Tilly wants to use the password for:\n\n\(account.label)\nAccount: \(account.account)\nServer: \(account.server)\n\nThis will copy the password to your clipboard."
        let answer = await handler(question, [
            "Allow — copy password to clipboard",
            "Deny — don't share this password",
            "Allow and open \(account.server) in browser",
        ])

        if answer.lowercased().contains("deny") || answer.lowercased().contains("don't") {
            return ToolResult(content: "User denied password access.")
        }

        // Fetch the actual password
        let fetchQuery: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: account.server,
            kSecAttrAccount as String: account.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(fetchQuery as CFDictionary, &result)

        guard status == errSecSuccess, let passwordData = result as? Data,
              let password = String(data: passwordData, encoding: .utf8) else {
            return ToolResult(content: "Failed to retrieve password (keychain error \(status))", isError: true)
        }

        // Copy to clipboard — NEVER expose to the LLM
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(password, forType: .string)

        // Auto-clear clipboard after 30 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            if NSPasteboard.general.string(forType: .string) == password {
                NSPasteboard.general.clearContents()
            }
        }

        var response = "Password copied to clipboard for \(account.label). It will auto-clear in 30 seconds."

        // Open browser if requested
        if answer.lowercased().contains("open") && !account.server.isEmpty {
            let url = account.server.hasPrefix("http") ? account.server : "https://\(account.server)"
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = [url]
            try? process.run()
            response += "\nOpened \(url) in browser."
        }

        return ToolResult(content: response)
    }

    // MARK: - Keychain Query Helpers

    private struct KeychainAccount {
        let label: String
        let server: String
        let account: String
    }

    private func findAccounts(matching query: String) -> [KeychainAccount] {
        var accounts: [KeychainAccount] = []

        // Search internet passwords
        let searchQuery: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(searchQuery as CFDictionary, &result)

        guard status == errSecSuccess, let items = result as? [[String: Any]] else {
            return accounts
        }

        let loweredQuery = query.lowercased()

        for item in items {
            let server = item[kSecAttrServer as String] as? String ?? ""
            let account = item[kSecAttrAccount as String] as? String ?? ""
            let label = item[kSecAttrLabel as String] as? String ?? server

            // Filter by query
            if loweredQuery.isEmpty ||
               server.lowercased().contains(loweredQuery) ||
               account.lowercased().contains(loweredQuery) ||
               label.lowercased().contains(loweredQuery) {
                accounts.append(KeychainAccount(label: label, server: server, account: account))
            }
        }

        return accounts.sorted { $0.label < $1.label }
    }
    #endif
}
