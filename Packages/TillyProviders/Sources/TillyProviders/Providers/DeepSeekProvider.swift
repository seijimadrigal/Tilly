import Foundation
import TillyCore

public final class DeepSeekProvider: OpenAICompatibleProvider {
    // DeepSeek is fully OpenAI-compatible.
    // The `reasoning_content` field in StreamDelta.Delta
    // is already handled by the base StreamDelta decoder.
}
