import Foundation
import TillyCore

extension ModelRouter.ModelProfile {
    public static let defaults: [ModelRouter.ModelProfile] = [
        // Flash tier — cheapest, for routing/classification
        ModelRouter.ModelProfile(
            providerID: .zai,
            modelID: "glm-4-flash",
            tier: .flash,
            costPer1KTokens: 0.0001,
            maxContext: 128_000
        ),

        // Standard tier — good balance for most tasks
        ModelRouter.ModelProfile(
            providerID: .moonshot,
            modelID: "moonshot-v1-8k",
            tier: .standard,
            costPer1KTokens: 0.001,
            maxContext: 8_000
        ),
        ModelRouter.ModelProfile(
            providerID: .deepSeek,
            modelID: "deepseek-chat",
            tier: .standard,
            costPer1KTokens: 0.0014,
            maxContext: 64_000
        ),

        // Premium tier — best quality, for complex orchestration
        ModelRouter.ModelProfile(
            providerID: .zaiCoding,
            modelID: "glm-5.1",
            tier: .premium,
            costPer1KTokens: 0.005,
            maxContext: 128_000
        ),
        ModelRouter.ModelProfile(
            providerID: .openRouter,
            modelID: "anthropic/claude-sonnet-4",
            tier: .premium,
            costPer1KTokens: 0.003,
            maxContext: 200_000
        ),
    ]
}
