import Foundation
import TillyCore

/// Control Safari browser via AppleScript — navigate, read pages, click, fill forms, run JavaScript.
public final class BrowserTool: ToolExecutable, @unchecked Sendable {
    public init() {}

    public var definition: ToolDefinition {
        ToolDefinition(
            function: ToolDefinition.FunctionDef(
                name: "browser",
                description: "Control Safari browser on macOS. Can navigate to URLs, read page content, get the current URL/title, execute JavaScript, fill form fields, and click elements. Use for web automation, form filling, data extraction from JavaScript-heavy sites.",
                parameters: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "action": .object([
                            "type": .string("string"),
                            "enum": .array([
                                .string("navigate"), .string("read_page"), .string("get_url"),
                                .string("run_javascript"), .string("list_tabs"), .string("new_tab"),
                                .string("close_tab"), .string("click"), .string("type_text"),
                            ]),
                            "description": .string("The browser action to perform."),
                        ]),
                        "url": .object(["type": .string("string"), "description": .string("URL to navigate to (for 'navigate' action).")]),
                        "javascript": .object(["type": .string("string"), "description": .string("JavaScript code to execute in the current page (for 'run_javascript' action).")]),
                        "selector": .object(["type": .string("string"), "description": .string("CSS selector for click/type_text actions.")]),
                        "text": .object(["type": .string("string"), "description": .string("Text to type (for 'type_text' action).")]),
                    ]),
                    "required": .array([.string("action")]),
                ])
            )
        )
    }

    public func execute(arguments: String) async throws -> ToolResult {
        #if os(macOS)
        struct Args: Decodable {
            let action: String
            let url: String?
            let javascript: String?
            let selector: String?
            let text: String?
        }

        guard let data = arguments.data(using: .utf8) else { throw TillyError.toolExecutionFailed("Invalid args") }
        let args = try JSONDecoder().decode(Args.self, from: data)

        switch args.action {
        case "navigate":
            guard let url = args.url else { return ToolResult(content: "URL required for navigate", isError: true) }
            return await runAppleScript("""
                tell application "Safari"
                    activate
                    if (count of windows) = 0 then make new document
                    set URL of current tab of front window to "\(escapeAS(url))"
                    delay 2
                    set pageTitle to name of current tab of front window
                    return "Navigated to: " & pageTitle
                end tell
            """)

        case "read_page":
            return await runAppleScript("""
                tell application "Safari"
                    set pageText to do JavaScript "document.body.innerText.substring(0, 10000)" in current tab of front window
                    return pageText
                end tell
            """)

        case "get_url":
            return await runAppleScript("""
                tell application "Safari"
                    set currentURL to URL of current tab of front window
                    set pageTitle to name of current tab of front window
                    return "Title: " & pageTitle & "\\nURL: " & currentURL
                end tell
            """)

        case "run_javascript":
            guard let js = args.javascript else { return ToolResult(content: "JavaScript code required", isError: true) }
            return await runAppleScript("""
                tell application "Safari"
                    set result to do JavaScript "\(escapeAS(js))" in current tab of front window
                    return result as text
                end tell
            """)

        case "list_tabs":
            return await runAppleScript("""
                tell application "Safari"
                    set tabList to ""
                    repeat with w in windows
                        repeat with t in tabs of w
                            set tabList to tabList & name of t & " | " & URL of t & "\\n"
                        end repeat
                    end repeat
                    return tabList
                end tell
            """)

        case "new_tab":
            let url = args.url ?? "about:blank"
            return await runAppleScript("""
                tell application "Safari"
                    activate
                    if (count of windows) = 0 then make new document
                    tell front window to set current tab to (make new tab with properties {URL:"\(escapeAS(url))"})
                    return "New tab opened"
                end tell
            """)

        case "close_tab":
            return await runAppleScript("""
                tell application "Safari"
                    close current tab of front window
                    return "Tab closed"
                end tell
            """)

        case "click":
            guard let selector = args.selector else { return ToolResult(content: "CSS selector required", isError: true) }
            return await runAppleScript("""
                tell application "Safari"
                    do JavaScript "document.querySelector('\(escapeAS(selector))').click()" in current tab of front window
                    return "Clicked: \(escapeAS(selector))"
                end tell
            """)

        case "type_text":
            guard let selector = args.selector, let text = args.text else {
                return ToolResult(content: "Both selector and text required", isError: true)
            }
            return await runAppleScript("""
                tell application "Safari"
                    do JavaScript "var el = document.querySelector('\(escapeAS(selector))'); el.value = '\(escapeAS(text))'; el.dispatchEvent(new Event('input', {bubbles: true}))" in current tab of front window
                    return "Typed text into \(escapeAS(selector))"
                end tell
            """)

        default:
            return ToolResult(content: "Unknown action: \(args.action)", isError: true)
        }
        #else
        return ToolResult(content: "This tool is only available on macOS.", isError: true)
        #endif
    }

    #if os(macOS)
    private func runAppleScript(_ script: String) async -> ToolResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
            process.waitUntilExit()

            let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

            if process.terminationStatus != 0 {
                return ToolResult(content: "AppleScript error: \(stderr)", isError: true)
            }

            let output = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            let maxLen = 10000
            return ToolResult(content: output.count > maxLen ? String(output.prefix(maxLen)) + "...[truncated]" : output)
        } catch {
            return ToolResult(content: "Failed: \(error.localizedDescription)", isError: true)
        }
    }

    private func escapeAS(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "'", with: "\\'")
    }
    #endif  // os(macOS)
}

