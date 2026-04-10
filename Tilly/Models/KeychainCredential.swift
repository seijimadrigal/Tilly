import Foundation

struct KeychainCredential: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let label: String
    let server: String
    let account: String

    init(label: String, server: String, account: String) {
        self.id = "\(server)_\(account)"
        self.label = label
        self.server = server
        self.account = account
    }
}
