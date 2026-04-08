import Foundation
import TillyCore

public final class ZAIProvider: OpenAICompatibleProvider {
    // ZAI (Zhipu AI) base URL already includes /api/paas/v4
    // The /chat/completions path is appended by the base class
}
