import Testing
@testable import TillyCore

@Test func messageCreation() {
    let msg = Message(role: .user, content: [.text("Hello")])
    #expect(msg.role == .user)
    #expect(msg.textContent == "Hello")
}

@Test func sessionCreation() {
    let session = Session()
    #expect(session.title == "New Chat")
    #expect(session.messages.isEmpty)
}

@Test func sessionForking() {
    var session = Session()
    session.appendMessage(Message(role: .user, content: [.text("msg1")]))
    session.appendMessage(Message(role: .assistant, content: [.text("reply1")]))
    session.appendMessage(Message(role: .user, content: [.text("msg2")]))

    let forked = session.forked(atIndex: 2)
    #expect(forked.messages.count == 2)
    #expect(forked.parentSessionID == session.id)
    #expect(forked.forkPointIndex == 2)
}
