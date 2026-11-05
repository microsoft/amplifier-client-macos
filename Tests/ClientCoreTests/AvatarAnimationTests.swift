import XCTest
@testable import ClientCore

final class AvatarAnimationTests: XCTestCase {
    private func item(_ kind: String, _ fingerprint: String = "v1") -> AttentionItem {
        AttentionItem(id: "event", fingerprint: fingerprint, sessionId: "chat", title: "Example", kind: kind,
                      summary: "Example", pinned: false, agentCreated: false)
    }
    func testHostAttentionPriorityAndReadingClearsPresentation() {
        var p = AvatarPlayback()
        p.update(connected: false, connecting: true, working: 1, items: [item("completion")], scope: "host", now: 0)
        XCTAssertEqual(p.state, .connecting)
        p.update(connected: true, connecting: false, working: 1, items: [], scope: "host", now: 1)
        XCTAssertEqual(p.state, .working)
        p.update(connected: true, connecting: false, working: 1, items: [item("completion")], scope: "host", now: 2)
        XCTAssertEqual(p.state, .ready)
        p.update(connected: true, connecting: false, working: 1, items: [item("approval"), item("session-error")], scope: "host", now: 3)
        XCTAssertEqual(p.state, .error)
        p.update(connected: true, connecting: false, working: 0, items: [item("approval")], scope: "host", now: 4)
        XCTAssertEqual(p.state, .review)
        p.update(connected: true, connecting: false, working: 0, items: [], scope: "host", now: 5)
        XCTAssertEqual(p.state, .idle)
    }
    func testOneShotDoesNotReplayOnPollingRemovalOrReconnect() {
        for kind in ["completion", "session-error"] {
            var p = AvatarPlayback()
            func update(_ items: [AttentionItem], _ time: Double, _ connected: Bool = true) {
                p.update(connected: connected, connecting: false, working: 0, items: items, scope: "host", now: time)
            }
            update([item(kind)], 10)
            update([item(kind)], 15)
            XCTAssertEqual(p.elapsed(at: 15), 5)
            XCTAssertFalse(p.animates(at: 15, visible: true, reducedMotion: false))
            update([], 16, false)
            update([item(kind)], 20)
            XCTAssertEqual(p.elapsed(at: 20), 4)
            update([item(kind), item(kind, "v2")], 21)
            XCTAssertEqual(p.elapsed(at: 21), 0)
            update([item(kind, "v2")], 22)
            XCTAssertEqual(p.elapsed(at: 22), 1, "Removing an old update is not a new event")
        }
    }
    func testHostScopeAndAnimationSuspension() {
        var p = AvatarPlayback()
        p.update(connected: true, connecting: false, working: 0, items: [item("completion")], scope: "one", now: 0)
        p.update(connected: true, connecting: false, working: 0, items: [item("completion")], scope: "two", now: 10)
        XCTAssertEqual(p.elapsed(at: 10), 0)
        XCTAssertFalse(p.animates(at: 11, visible: false, reducedMotion: false))
        XCTAssertFalse(p.animates(at: 11, visible: true, reducedMotion: true))
        p.update(connected: false, connecting: false, working: 20, items: [], scope: "two", now: 12)
        XCTAssertEqual(p.state, .offline)
        XCTAssertFalse(p.animates(at: 12, visible: true, reducedMotion: false))
    }
    func testUnreadReactionReturnsToOngoingWorkWithoutClearingAttention() {
        for kind in ["completion", "session-error"] {
            var p = AvatarPlayback()
            let attention = item(kind)
            p.update(connected: true, connecting: false, working: 2, items: [], scope: "host", now: 10)
            p.update(connected: true, connecting: false, working: 2, items: [attention], scope: "host", now: 12)
            let attentionState = p.state
            XCTAssertEqual(p.presentation(at: 15.99).state, attentionState)
            XCTAssertEqual(p.presentation(at: 16).state, .working)
            XCTAssertEqual(p.presentation(at: 16).elapsed, 6, "Working clock survives the reaction")
            XCTAssertTrue(p.animates(at: 16, visible: true, reducedMotion: false))
            p.update(connected: true, connecting: false, working: 1, items: [attention], scope: "host", now: 20)
            XCTAssertEqual(p.state, attentionState, "Unread/error meaning is preserved")
            XCTAssertEqual(p.presentation(at: 20).state, .working, "Polling must not replay the reaction")
            XCTAssertEqual(p.presentation(at: 20).elapsed, 10)
            XCTAssertFalse(p.animates(at: 20, visible: false, reducedMotion: false))
            XCTAssertFalse(p.animates(at: 20, visible: true, reducedMotion: true))
            p.update(connected: true, connecting: false, working: 0, items: [attention], scope: "host", now: 21)
            XCTAssertEqual(p.presentation(at: 21).state, attentionState)
            XCTAssertFalse(p.animates(at: 21, visible: true, reducedMotion: false))
            p.update(connected: true, connecting: false, working: 1, items: [attention], scope: "host", now: 30)
            XCTAssertEqual(p.presentation(at: 30).state, .working, "New work must animate with old unread items")
            XCTAssertEqual(p.presentation(at: 30).elapsed, 0)
            p.update(connected: true, connecting: false, working: 1, items: [item(kind, "v2")], scope: "host", now: 31)
            XCTAssertEqual(p.presentation(at: 31).state, attentionState, "A new event still reacts once")
            XCTAssertEqual(p.presentation(at: 35).state, .working)
            XCTAssertEqual(p.presentation(at: 35).elapsed, 5)
            p.update(connected: false, connecting: false, working: 1, items: [attention], scope: "host", now: 36)
            XCTAssertEqual(p.presentation(at: 36).state, .offline)
            XCTAssertFalse(p.animates(at: 36, visible: true, reducedMotion: false))
        }
    }
    func testSavedShapeMigration() {
        XCTAssertEqual(AvatarCatalog.shapes.count, 6)
        XCTAssertEqual(AvatarCatalog.canonical("arc"), "d20")
        XCTAssertEqual(AvatarCatalog.canonical("fold"), "d20")
        XCTAssertEqual(AvatarCatalog.canonical("chord"), "accord")
        XCTAssertEqual(AvatarCatalog.canonical("clippy"), "clippy")
        XCTAssertEqual(AvatarCatalog.canonical("unrecognized"), "relay")
    }
    func testChoreographyStaysBoundedAndSettles() {
        for shape in AvatarCatalog.shapes {
            for state in AvatarState.allCases {
                for tick in 0...360 {
                    let pose = AvatarPose.sample(shape: shape, state: state, elapsed: Double(tick)/30)
                    XCTAssertEqual(pose.weights.reduce(0,+), 1, accuracy: 0.000001)
                    XCTAssertTrue(pose.weights.allSatisfy { $0 >= 0 && $0 <= 1 })
                    XCTAssertLessThanOrEqual(abs(pose.tilt), 4)
                    XCTAssertTrue((0.98...1.03).contains(pose.scaleY))
                }
                let reduced = AvatarPose.sample(shape: shape, state: state, elapsed: 3, reduced: true)
                XCTAssertEqual(reduced.tilt, 0)
                XCTAssertEqual(reduced.scaleY, 1)
            }
            for state in [AvatarState.ready, .error, .offline] {
                let a = AvatarPose.sample(shape: shape, state: state, elapsed: 4)
                let b = AvatarPose.sample(shape: shape, state: state, elapsed: 60)
                XCTAssertEqual(a.weights, b.weights)
                XCTAssertEqual(a.tilt, b.tilt)
            }
        }
    }
}
