import Foundation
import TillyCore
import TillyStorage
#if os(macOS)
import Security
#endif

/// Test a skill's prerequisites before running — checks credentials, APIs, commands.
public final class SkillTestTool: ToolExecutable, @unchecked Sendable {
    private let skillService: SkillService
    private let memoryService: MemoryService

    public init(skillService: SkillService, memoryService: MemoryService) {
        self.skillService = skillService
        self.memoryService = memoryService
    }

    public var definition: ToolDefinition {
        ToolDefinition(
            function: ToolDefinition.FunctionDef(
                name: "skill_test",
                description: "Test a skill's prerequisites before running it. Checks credentials (in Keychain and memory), API endpoints, and shell commands. Returns a pass/fail report. Run this before skill_chain to ensure all skills will work.",
                parameters: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "name": .object(["type": .string("string"), "description": .string("Skill name or ID to test.")]),
                    ]),
                    "required": .array([.string("name")]),
                ])
            )
        )
    }

    public func execute(arguments: String) async throws -> ToolResult {
        struct Args: Decodable { let name: String }
        guard let data = arguments.data(using: .utf8) else { throw TillyError.toolExecutionFailed("Invalid args") }
        let args = try JSONDecoder().decode(Args.self, from: data)

        let skill: SkillEntry
        do {
            skill = try skillService.load(name: args.name)
        } catch {
            return ToolResult(content: "Skill not found: \(args.name)", isError: true)
        }

        if skill.tests.isEmpty {
            return ToolResult(content: "Skill '\(skill.name)' has no test prerequisites defined.\nAdd a ## Tests section to the skill's SKILL.md to define checks.")
        }

        var results: [(check: SkillCheck, passed: Bool, detail: String)] = []

        for check in skill.tests {
            let (passed, detail) = await runCheck(check)
            results.append((check, passed, detail))
        }

        let passCount = results.filter(\.passed).count
        let total = results.count

        var report = "# Skill Test: \(skill.name)\n\n"
        for r in results {
            let icon = r.passed ? "PASS" : "FAIL"
            report += "[\(icon)] \(r.check.check): \(r.detail)\n"
        }
        report += "\nResult: \(passCount)/\(total) checks passed."
        if passCount < total {
            let failed = results.filter { !$0.passed }.map(\.check.check)
            report += "\nFailed: \(failed.joined(separator: ", "))"
        }

        return ToolResult(content: report, isError: passCount < total)
    }

    private func runCheck(_ check: SkillCheck) async -> (passed: Bool, detail: String) {
        switch check.check {
        case "credential":
            return await checkCredential(check)
        case "api":
            return await checkAPI(check)
        case "command":
            return await checkCommand(check)
        default:
            return (false, "Unknown check type: \(check.check)")
        }
    }

    // MARK: - Credential Check (Memory + Keychain)

    private func checkCredential(_ check: SkillCheck) async -> (Bool, String) {
        guard let name = check.name, !name.isEmpty else {
            return (false, "No credential name specified")
        }

        let source = check.source ?? "any"

        // Check memory
        if source == "memory" || source == "any" {
            let memoryResults = try? memoryService.search(query: name)
            if let results = memoryResults, !results.isEmpty {
                return (true, "\(name) found in memory")
            }
            if source == "memory" {
                return (false, "\(name) not found in memory")
            }
        }

        // Check Keychain
        #if os(macOS)
        if source == "keychain" || source == "any" {
            let query: [String: Any] = [
                kSecClass as String: kSecClassInternetPassword,
                kSecReturnAttributes as String: true,
                kSecMatchLimit as String: kSecMatchLimitAll,
            ]

            var result: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &result)

            if status == errSecSuccess, let items = result as? [[String: Any]] {
                let lowered = name.lowercased()
                let found = items.contains { item in
                    let server = (item[kSecAttrServer as String] as? String ?? "").lowercased()
                    let account = (item[kSecAttrAccount as String] as? String ?? "").lowercased()
                    let label = (item[kSecAttrLabel as String] as? String ?? "").lowercased()
                    return server.contains(lowered) || account.contains(lowered) || label.contains(lowered)
                }
                if found {
                    return (true, "\(name) found in Keychain")
                }
            }
            if source == "keychain" {
                return (false, "\(name) not found in Keychain")
            }
        }
        #endif

        return (false, "\(name) not found in memory or Keychain")
    }

    // MARK: - API Check

    private func checkAPI(_ check: SkillCheck) async -> (Bool, String) {
        guard let urlString = check.url, let url = URL(string: urlString) else {
            return (false, "No valid URL specified")
        }

        var request = URLRequest(url: url)
        request.httpMethod = check.method ?? "GET"
        request.timeoutInterval = 10

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let http = response as? HTTPURLResponse
            let statusCode = http?.statusCode ?? 0

            if let expected = check.expectStatus {
                let passed = statusCode == expected
                return (passed, "\(urlString) returned HTTP \(statusCode) (expected \(expected))")
            }
            let passed = (200...299).contains(statusCode)
            return (passed, "\(urlString) returned HTTP \(statusCode)")
        } catch {
            return (false, "\(urlString) failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Command Check

    private func checkCommand(_ check: SkillCheck) async -> (Bool, String) {
        #if os(macOS)
        guard let command = check.command, !command.isEmpty else {
            return (false, "No command specified")
        }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

            if let expected = check.expectContains {
                let passed = output.contains(expected)
                return (passed, "'\(command)' → \(passed ? "contains" : "missing") '\(expected)'")
            }
            let passed = process.terminationStatus == 0
            return (passed, "'\(command)' exited with \(process.terminationStatus)")
        } catch {
            return (false, "'\(command)' failed: \(error.localizedDescription)")
        }
        #else
        return (false, "Command checks only available on macOS")
        #endif
    }
}
