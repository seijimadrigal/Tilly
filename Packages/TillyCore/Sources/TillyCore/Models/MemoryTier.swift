import Foundation

/// Four-tier memory hierarchy inspired by cognitive architecture.
public enum MemoryTier: String, Codable, Sendable, CaseIterable {
    /// In-session working memory. Not persisted across sessions.
    /// Used for active plans, sub-task coordination, routing decisions.
    case working

    /// Timestamped session history. Stored as session summaries in Memcloud.
    /// "What happened and when" — interaction history with temporal context.
    case episodic

    /// Facts, knowledge, user preferences, extracted triples.
    /// Stored in Memcloud's knowledge graph for semantic retrieval.
    case semantic

    /// Learned workflows, skill patterns, tool chains.
    /// Stored locally in SkillService files.
    case procedural
}
