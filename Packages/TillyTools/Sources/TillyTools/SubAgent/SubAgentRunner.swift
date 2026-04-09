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

        var finalText = ""

        for _ in 0..<maxRounds {
            let request = ChatCompletionRequest(
                model: model,
                messages: messages,
                stream: false,
                streamOptions: nil,
                tools: toolDefinitions.isEmpty ? nil : toolDefinitions
            )

            let response = try await provider.complete(request)

            guard let choice = response.choices.first else {
                break
            }

            let assistantContent = choice.message.content ?? ""
            let assistantToolCalls = choice.message.toolCalls ?? []

            // Add assistant message to history
            messages.append(ChatCompletionRequest.ChatMessage(
                role: "assistant",
                content: assistantContent.isEmpty ? nil : assistantContent,
                toolCalls: assistantToolCalls.isEmpty ? nil : assistantToolCalls
            ))

            // If there are tool calls, execute them
            if !assistantToolCalls.isEmpty {
                // Execute tools in parallel
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

                // Add tool results to history
                for tc in assistantToolCalls {
                    if let (_, toolResult) = results.first(where: { $0.0.id == tc.id }) {
                        messages.append(ChatCompletionRequest.ChatMessage(
                            role: "tool",
                            content: toolResult.content,
                            toolCallID: tc.id
                        ))
                    }
                }

                continue  // Let LLM see the results
            }

            // No tool calls — agent is done
            finalText = assistantContent
            break
        }

        return finalText.isEmpty ? "(Sub-agent produced no output)" : finalText
    }
}
