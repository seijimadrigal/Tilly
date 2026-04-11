import Foundation
import TillyCore

/// Runs an independent agent loop for a sub-task.
/// No UI, no AppState, no session persistence — just LLM + tools → result.
public final class SubAgentRunner: @unchecked Sendable {
    private let provider: any LLMProvider
    private let model: String
    private let tools: [any ToolExecutable]
    private let maxRounds: Int
    private let systemPrompt: String

    public init(
        provider: any LLMProvider,
        model: String,
        tools: [any ToolExecutable],
        maxRounds: Int = 15,
        systemPrompt: String
    ) {
        self.provider = provider
        self.model = model
        self.tools = tools
        self.maxRounds = maxRounds
        self.systemPrompt = systemPrompt
    }

    /// Run the sub-agent and return the final text response.
    public func run(task: String) async throws -> String {
        var messages: [ChatCompletionRequest.ChatMessage] = [
            ChatCompletionRequest.ChatMessage(role: "system", content: systemPrompt),
            ChatCompletionRequest.ChatMessage(role: "user", content: task),
        ]

        let toolDefinitions = tools.map(\.definition)
        let toolMap = Dictionary(uniqueKeysWithValues: tools.map { ($0.definition.function.name, $0) })

        // Accumulate ALL assistant text across rounds (not just the last message)
        var accumulatedText = ""
        var toolResultsSummary: [String] = []

        for round in 0..<maxRounds {
            let request = ChatCompletionRequest(
                model: model,
                messages: messages,
                stream: false,
                streamOptions: nil,
                tools: toolDefinitions.isEmpty ? nil : toolDefinitions
            )

            let response: ChatCompletionResponse
            do {
                response = try await provider.complete(request)
            } catch {
                let errMsg = error.localizedDescription.lowercased()
                let isToolError = errMsg.contains("tool") || errMsg.contains("function")
                    || errMsg.contains("not supported") || errMsg.contains("400")
                    || errMsg.contains("422") || errMsg.contains("404")

                // If tools caused the error, retry once without tools (pure text mode)
                if isToolError && !toolDefinitions.isEmpty && round == 0 {
                    let noToolRequest = ChatCompletionRequest(
                        model: model,
                        messages: messages,
                        stream: false,
                        streamOptions: nil,
                        tools: nil
                    )
                    if let fallback = try? await provider.complete(noToolRequest),
                       let text = fallback.choices.first?.message.content, !text.isEmpty {
                        return text
                    }
                }

                // Return whatever we have so far
                if !accumulatedText.isEmpty { return accumulatedText }
                if !toolResultsSummary.isEmpty {
                    return "Sub-agent completed \(round) rounds. Tool results:\n" + toolResultsSummary.joined(separator: "\n")
                }
                return "Sub-agent LLM error: \(error.localizedDescription)"
            }

            guard let choice = response.choices.first else {
                break
            }

            let assistantContent = choice.message.content ?? ""
            let assistantToolCalls = choice.message.toolCalls ?? []

            // Accumulate any text the assistant produces (even alongside tool calls)
            if !assistantContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                accumulatedText += (accumulatedText.isEmpty ? "" : "\n\n") + assistantContent
            }

            // Add assistant message to history
            messages.append(ChatCompletionRequest.ChatMessage(
                role: "assistant",
                content: assistantContent.isEmpty ? nil : assistantContent,
                toolCalls: assistantToolCalls.isEmpty ? nil : assistantToolCalls
            ))

            // If there are tool calls, execute them
            if !assistantToolCalls.isEmpty {
                let results: [(ToolCall, ToolResult)] = await withTaskGroup(
                    of: (ToolCall, ToolResult).self,
                    returning: [(ToolCall, ToolResult)].self
                ) { group in
                    for tc in assistantToolCalls {
                        group.addTask {
                            let result: ToolResult
                            if let tool = toolMap[tc.function.name] {
                                do {
                                    result = try await tool.execute(arguments: tc.function.arguments)
                                } catch {
                                    result = ToolResult(content: "Error: \(error.localizedDescription)", isError: true)
                                }
                            } else {
                                result = ToolResult(content: "Unknown tool: \(tc.function.name)", isError: true)
                            }
                            return (tc, result)
                        }
                    }
                    var r: [(ToolCall, ToolResult)] = []
                    for await pair in group { r.append(pair) }
                    return r
                }

                // Add tool results to history and track summaries
                for tc in assistantToolCalls {
                    if let (_, toolResult) = results.first(where: { $0.0.id == tc.id }) {
                        messages.append(ChatCompletionRequest.ChatMessage(
                            role: "tool",
                            content: String(toolResult.content.prefix(3000)),
                            toolCallID: tc.id
                        ))
                        toolResultsSummary.append("[\(tc.function.name)] \(String(toolResult.content.prefix(200)))")
                    }
                }

                continue
            }

            // No tool calls — agent is done
            break
        }

        // Return accumulated text, or synthesize from tool results if text is empty
        if !accumulatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return accumulatedText
        }
        if !toolResultsSummary.isEmpty {
            return "Sub-agent findings:\n" + toolResultsSummary.joined(separator: "\n")
        }
        return "(Sub-agent produced no output)"
    }
}
