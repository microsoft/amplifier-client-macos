import XCTest
@testable import ClientCore
final class NoticePresentationTests: XCTestCase {
    func testResizeFitsThenReturnsToRememberedCap() {
        var size = NoticeListSize()
        XCTAssertEqual(size.height(content: 600, available: 900),178)
        size.resize(to: 900, content:600, available:900)
        XCTAssertTrue(size.fitsContents)
        XCTAssertEqual(size.height(content: 800, available:900),800)
        XCTAssertEqual(size.height(content:1200, available:900),900)
        size.resize(to: 400, content:1200, available:900)
        XCTAssertFalse(size.fitsContents)
        XCTAssertEqual(size.height(content:100,available:900),100)
        XCTAssertEqual(size.height(content:800,available:900),400)
        XCTAssertEqual(size.height(content:800,available:200),200)
    }
    func testDismissalSurvivesDetailButNotStateChange() {
        XCTAssertEqual(NoticeDismissal.reconcile(["work:a":"tool-1", "b":"old"],current:["work:a":"tool-1"]),["work:a":"tool-1"])
        XCTAssertTrue(NoticeDismissal.reconcile(["work:a":"tool-1"],current:["work:a":"model-2"]).isEmpty)
    }
    func testDismissalWaitsForKnownActivityAfterRestart() {
        let known = ["a":"work|working|node-1|llm|running"]
        XCTAssertEqual(NoticeDismissal.reconcile(known, current:["a":"work|working|"]), known)
        XCTAssertEqual(NoticeDismissal.reconcile(["a":"work|working|"], current:known), known)
        XCTAssertTrue(NoticeDismissal.reconcile(known, current:["a":"work|working|node-2|tool|running"]).isEmpty)
        XCTAssertTrue(NoticeDismissal.reconcile(known, current:["a":"work|stopping|"]).isEmpty)
    }
    func testSidebarStatusMeanings() {
        XCTAssertEqual(NoticeStatus.attention(kind:"manual-unread"), .unread)
        XCTAssertEqual(NoticeStatus.attention(kind:"completion", working:true), .working)
        XCTAssertEqual(NoticeStatus.attention(kind:"approval"), .question)
        XCTAssertEqual(NoticeStatus.attention(kind:"session-error"), .error)
        XCTAssertEqual(NoticeStatus.attention(kind:"blocked"), .blocked)
    }
    func testActivityUsesPublicSummaryAndModelCopy() {
        let llm:[String:Any] = ["id":"m1","kind":"llm","phase":"running","label":"Model call","input":"private input"]
        XCTAssertEqual(WorkPreview.from(nodes:[llm])?.text,"Thinking…")
        let tool:[String:Any] = ["id":"t1","kind":"tool","phase":"running","label":"Read file","summary":"Checking the release notes", "input":["secret":"never display"]]
        let result=WorkPreview.from(nodes:[llm,tool])!
        XCTAssertEqual(result.text,"Read file · Checking the release notes")
        var progress=tool; progress["summary"]="Checking another section"
        XCTAssertEqual(WorkPreview.from(nodes:[progress])?.stateID,result.stateID)
        var done=tool; done["endedAt"]=123
        XCTAssertNil(WorkPreview.from(nodes:[done]))
        XCTAssertEqual(WorkPreview.fallback(status:"working"),"Thinking…")
        XCTAssertEqual(WorkPreview.fallback(status:"stopping"),"Stopping…")
    }
}
