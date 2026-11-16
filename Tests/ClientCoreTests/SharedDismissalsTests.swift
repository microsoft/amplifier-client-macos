import XCTest
@testable import ClientCore

final class SharedDismissalsTests: XCTestCase {
    func testDurableExactStateAndServiceIsolation() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("dismissals.json")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        var service = try RegisteredService(address: "https://a.example"); service.hostIdentity = "same-cloned-id"
        var other = try RegisteredService(address: "https://b.example"); other.hostIdentity = service.hostIdentity
        let state = DismissalDescriptor(id: "update", fingerprint: "one", dismissed: false)
        let next = DismissalDescriptor(id: "update", fingerprint: "two", dismissed: false)
        var journal = SharedDismissals()
        let intent = try journal.enqueue(state, service: service)
        XCTAssertEqual(try journal.enqueue(state, service: service).requestID, intent.requestID)
        try journal.save(to: file); journal = try SharedDismissals.load(from: file)
        XCTAssertTrue(journal.hidden(state, service: service))
        XCTAssertFalse(journal.hidden(next, service: service))
        XCTAssertFalse(journal.hidden(state, service: other))
        let second = try journal.enqueue(state, service: other)
        journal.accepted(intent.requestID)
        journal.reconcile([state], service: service)
        XCTAssertTrue(journal.hidden(state, service: service))
        let confirmed = DismissalDescriptor(id: "update", fingerprint: "one", dismissed: true)
        journal.reconcile([confirmed], service: service)
        XCTAssertEqual(journal.entries.map(\.requestID), [second.requestID])
        XCTAssertTrue(journal.hidden(confirmed, service: service))
        journal.reconcile([next], service: other); XCTAssertTrue(journal.entries.isEmpty)
    }
    func testCorruptJournalIsPreservedAndNeverSilentlyReset() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let data = Data("damaged".utf8); try data.write(to: file)
        XCTAssertThrowsError(try SharedDismissals.load(from: file))
        XCTAssertEqual(try Data(contentsOf: file), data)
    }
}
