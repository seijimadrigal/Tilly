import Foundation
import TillyCore

public final class OpenRouterProvider: OpenAICompatibleProvider {
    override public func additionalHeaders() -> [String: String] {
        [
            "HTTP-Referer": "https://tilly.app",
            "X-Title": "Tilly",
        ]
    }
}
