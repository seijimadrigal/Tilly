import Testing
@testable import TillyTools

@Test func toolRegistryInitializes() {
    let registry = ToolRegistry()
    #expect(registry.definitions.isEmpty)
}
