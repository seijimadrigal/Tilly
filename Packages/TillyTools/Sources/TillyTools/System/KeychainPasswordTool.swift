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
                description: "Manage macOS Keychain passwords. REQUIRES user approval. Actions: 'search' finds accounts, 'autofill' copies password to clipboard, 'list_accounts' shows saved accounts, 'save' adds a new password, 'delete' removes an account.",
                parameters: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "action": .object(["type": .string("string"), "enum": .array([.string("search"), .string("autofill"), .string("list_accounts"), .string("save"), .string("delete")]), "description": .string("Action to perform.")]),
                        "query": .object(["type": .string("string"), "description": .string("Search query — domain, app, or account (for search/autofill/delete).")]),
                        "server": .object(["type": .string("string"), "description": .string("Domain/server for the account (for save). E.g. 'github.com'.")]),
                        "account": .object(["type": .string("string"), "description": .string("Username or email (for save).")]),
                        "password": .object(["type": .string("string"), "description": .string("Password to save (for save). Will be stored securely in Keychain.")]),
                        "label": .object(["type": .string("string"), "description": .string("Display label (for save). E.g. 'GitHub - work account'.")]),
                    ]),
                    "required": .array([.string("action")]),
                ])
            )
        )
    }

    public func execute(arguments: String) async throws -> ToolResult {
        #if os(macOS)
        struct Args: Decodable {
            let action: String; let query: String?
            let server: String?; let account: String?
            let password: String?; let label: String?
        }
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

        case "save":
            guard let server = args.server, !server.isEmpty,
                  let account = args.account, !account.isEmpty,
                  let password = args.password, !password.isEmpty else {
                return ToolResult(content: "server, account, and password are all required for save", isError: true)
            }
            return await savePassword(server: server, account: account, password: password, label: args.label)

        case "delete":
            guard let query = args.query, !query.isEmpty else {
                return ToolResult(content: "Query required for delete", isError: true)
            }
            return await deletePassword(query: query)

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

    // MARK: - Save Password (requires user approval)

    private func savePassword(server: String, account: String, password: String, label: String?) async -> ToolResult {
        guard let handler = approvalHandler else {
            return ToolResult(content: "Cannot save — no approval handler configured", isError: true)
        }

        let displayLabel = label ?? "\(server) — \(account)"
        let question = "Tilly wants to save a new password to your Keychain:\n\nLabel: \(displayLabel)\nServer: \(server)\nAccount: \(account)\n\nAllow this?"
        let answer = await handler(question, [
            "Allow — save to Keychain",
            "Deny — don't save",
            "Allow and copy password to clipboard too",
        ])

        if answer.lowercased().contains("deny") || answer.lowercased().contains("don't") {
            return ToolResult(content: "User denied saving password.")
        }

        guard let passwordData = password.data(using: .utf8) else {
            return ToolResult(content: "Failed to encode password", isError: true)
        }

        // Check if entry already exists
        let existsQuery: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: server,
            kSecAttrAccount as String: account,
        ]

        let existsStatus = SecItemCopyMatching(existsQuery as CFDictionary, nil)

        if existsStatus == errSecSuccess {
            // Update existing
            let updateAttrs: [String: Any] = [
                kSecValueData as String: passwordData,
                kSecAttrLabel as String: displayLabel,
            ]
            let updateStatus = SecItemUpdate(existsQuery as CFDictionary, updateAttrs as CFDictionary)
            if updateStatus != errSecSuccess {
                return ToolResult(content: "Failed to update keychain entry (error \(updateStatus))", isError: true)
            }
        } else {
            // Add new
            var addQuery: [String: Any] = [
                kSecClass as String: kSecClassInternetPassword,
                kSecAttrServer as String: server,
                kSecAttrAccount as String: account,
                kSecAttrLabel as String: displayLabel,
                kSecValueData as String: passwordData,
            ]
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            if addStatus != errSecSuccess {
                return ToolResult(content: "Failed to save to keychain (error \(addStatus))", isError: true)
            }
        }

        var response = "Password saved to Keychain: \(displayLabel)"

        if answer.lowercased().contains("clipboard") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(password, forType: .string)
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
                NSPasteboard.general.clearContents()
            }
            response += "\nAlso copied to clipboard (auto-clears in 30s)."
        }

        return ToolResult(content: response)
    }

    // MARK: - Delete Password (requires user approval)

    private func deletePassword(query: String) async -> ToolResult {
        let accounts = findAccounts(matching: query)
        guard let account = accounts.first else {
            return ToolResult(content: "No account found for '\(query)'", isError: true)
        }

        guard let handler = approvalHandler else {
            return ToolResult(content: "Cannot delete — no approval handler configured", isError: true)
        }

        let question = "Tilly wants to DELETE a password from your Keychain:\n\n\(account.label)\nServer: \(account.server)\nAccount: \(account.account)\n\nThis cannot be undone."
        let answer = await handler(question, [
            "Delete — remove from Keychain",
            "Cancel — keep the password",
            "Delete and show me what's left",
        ])

        if answer.lowercased().contains("cancel") || answer.lowercased().contains("keep") {
            return ToolResult(content: "User cancelled deletion.")
        }

        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: account.server,
            kSecAttrAccount as String: account.account,
        ]

        let status = SecItemDelete(deleteQuery as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            return ToolResult(content: "Failed to delete (error \(status))", isError: true)
        }

        var response = "Deleted: \(account.label) (\(account.account) @ \(account.server))"

        if answer.lowercased().contains("show") {
            let remaining = findAccounts(matching: query)
            if remaining.isEmpty {
                response += "\nNo remaining accounts matching '\(query)'."
            } else {
                response += "\nRemaining accounts matching '\(query)': \(remaining.count)"
            }
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
