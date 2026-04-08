import Foundation

public protocol TillyPlugin: AnyObject, Sendable {
    static var pluginName: String { get }
    static var pluginVersion: String { get }

    init()

    func activate(context: any PluginContext) async throws
    func deactivate() async
}

public protocol PluginContext: Sendable {
    func registerTool(_ tool: any ToolExecutable)
    func registerProvider(_ provider: any LLMProvider)
}
