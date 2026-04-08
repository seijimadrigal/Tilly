import Testing
@testable import TillyStorage

@Test func keychainServiceInitializes() {
    let service = KeychainService(serviceName: "com.tilly.test")
    #expect(service != nil)
}
