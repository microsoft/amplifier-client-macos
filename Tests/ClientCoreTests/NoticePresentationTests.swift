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
    func testMarkdownPreviewsArePlainAndBounded() {
        XCTAssertEqual(NoticeText.plain("## **Ready** — [release notes](https://example.org)\n- `file_name.swift`"), "Ready — release notes file_name.swift")
        XCTAssertEqual(NoticeText.plain("**Completed in this chat’s browser…"), "Completed in this chat’s browser…")
        XCTAssertEqual(NoticeText.plain("a\u{202E}b\n\t c"), "a b c")
        XCTAssertEqual(NoticeText.plain("abcdefgh", limit: 5), "abcd…")
        XCTAssertEqual(NoticeText.plain("```swift\nlet answer = 42\n```"), "let answer = 42")
    }
    func testProjectedActionHintsWithoutRawPayloads() {
        let base: [String: Any] = ["id":"t1", "kind":"tool", "phase":"running", "label":"app_control",
            "input":["operation":"secret raw operation"], "inputPreview":"private command", "output":"private output"]
        var row = base
        row["actionPath"] = "dispatch → window.focus"
        row["inputSummary"] = ["operation":"dispatch", "prompt":"secret prompt", "command":"secret command"]
        XCTAssertEqual(WorkPreview.from(nodes:[row])?.text, "App · window focus")
        row["actionPath"] = nil
        XCTAssertEqual(WorkPreview.from(nodes:[row])?.text, "App · dispatch")
        XCTAssertEqual(WorkPreview.from(nodes:[base])?.text, "Using app controls…")
        row["label"] = "read_file"; row["inputSummary"] = ["file_path":"/private/project/README.md"]
        XCTAssertEqual(WorkPreview.from(nodes:[row])?.text, "Reading README.md")
        row["label"] = "bash"; row["inputSummary"] = ["command":"curl --header secret"]
        XCTAssertEqual(WorkPreview.from(nodes:[row])?.text, "Running a command…")
        row["label"] = "custom_tool"; row["inputSummary"] = ["operation":"credential=secret"]
        XCTAssertEqual(WorkPreview.from(nodes:[row])?.text, "Using custom tool…")
        row["tool"] = "bash"; row["label"] = "Running unit tests"
        XCTAssertEqual(WorkPreview.from(nodes:[row])?.text, "Running unit tests")
    }
    func testConcurrentToolsRemainVisibleThroughModelUpdates() {
        let first: [String:Any] = ["id":"t1","kind":"tool","phase":"running","label":"read_file"]
        var second: [String:Any] = ["id":"t2","kind":"tool","phase":"running","label":"web_search"]
        let model: [String:Any] = ["id":"m1","kind":"llm","phase":"running","label":"Model call"]
        XCTAssertEqual(WorkPreview.from(nodes:[first,second,model])?.text, "Searching the web… · +1 tool")
        second["endedAt"] = 1
        XCTAssertEqual(WorkPreview.from(nodes:[first,second,model])?.text, "Reading a file…")
        XCTAssertEqual(WorkPreview.from(nodes:[second,model])?.text, "Thinking…")
    }

}
