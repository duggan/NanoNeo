import XCTest
@testable import NeoKit

final class FakeSource: SlotSource {
    var slots: [Slot]
    var failClear: Set<Int> = []
    private(set) var clearCalls: [Int] = []
    init(_ slots: [Slot]) { self.slots = slots }
    func readSlots() throws -> [Slot] { slots }
    func clear(slot: Int) throws {
        clearCalls.append(slot)
        if failClear.contains(slot) { throw NeoError.protocolError("boom") }
    }
}

final class InboxSyncTests: XCTestCase {
    var root: URL!
    var dest: URL!
    var stateURL: URL!
    let fixed = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("nanoneo-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        dest = root.appendingPathComponent("Inbox")
        stateURL = root.appendingPathComponent("state/state.json")
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func makeSync(clear: Bool = true) -> InboxSync {
        var s = InboxSync(destination: dest, stateURL: stateURL)
        s.clearSlots = clear
        let d = fixed
        s.now = { d }
        return s
    }

    private func prefix() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = .current; f.dateFormat = "yyyy-MM-dd HHmm"
        return f.string(from: fixed)
    }

    private func files() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: dest.path).sorted()
    }

    private func read(_ name: String) throws -> String {
        try String(contentsOf: dest.appendingPathComponent(name), encoding: .utf8)
    }

    func testBasicSync() throws {
        let src = FakeSource([
            Slot(number: 5, text: "Second draft\nmore"),
            Slot(number: 2, text: "First draft\nbody"),
            Slot(number: 3, text: ""),
            Slot(number: 4, text: "  \n\t\n"),
        ])
        let report = try makeSync().run(source: src)
        let p = prefix()
        XCTAssertEqual(try files(), ["\(p) First draft.txt", "\(p) Second draft.txt"])
        XCTAssertEqual(try read("\(p) First draft.txt"), "First draft\nbody")
        XCTAssertEqual(try read("\(p) Second draft.txt"), "Second draft\nmore")
        XCTAssertEqual(report.saved.map(\.slot), [2, 5])
        XCTAssertEqual(report.cleared, [5, 2])
        XCTAssertEqual(src.clearCalls, [5, 2])
        XCTAssertTrue(report.failures.isEmpty)
        XCTAssertTrue(report.alreadySaved.isEmpty)

        let state = try InboxState.load(from: stateURL)
        XCTAssertEqual(Set(state.slots.keys), ["2", "5"])
        let r2 = try XCTUnwrap(state.slots["2"])
        XCTAssertEqual(r2.sha256, InboxState.hash(Data("First draft\nbody".utf8)))
        XCTAssertEqual(r2.sha256.count, 64)
        XCTAssertEqual(URL(fileURLWithPath: r2.savedAs).lastPathComponent, "\(p) First draft.txt")
        XCTAssertNotNil(r2.clearedAt)
        XCTAssertNotNil(state.slots["5"]?.clearedAt)
        XCTAssertNotNil(state.lastSync)
    }

    func testClearSlotsFalse() throws {
        let src = FakeSource([Slot(number: 1, text: "Hi"), Slot(number: 2, text: "There")])
        let report = try makeSync(clear: false).run(source: src)
        XCTAssertEqual(try files().count, 2)
        XCTAssertEqual(src.clearCalls, [])
        XCTAssertEqual(report.saved.count, 2)
        XCTAssertTrue(report.cleared.isEmpty)
        let state = try InboxState.load(from: stateURL)
        XCTAssertNil(state.slots["1"]?.clearedAt)
    }

    func testClearFailureThenRetryDoesNotDuplicate() throws {
        let src = FakeSource([Slot(number: 1, text: "Keep me"), Slot(number: 2, text: "Other")])
        src.failClear = [1]
        let r1 = try makeSync().run(source: src)
        XCTAssertEqual(r1.failures.map(\.slot), [1])
        XCTAssertEqual(r1.saved.map(\.slot), [1, 2])
        XCTAssertEqual(r1.cleared, [2])
        XCTAssertEqual(try files().count, 2)
        var state = try InboxState.load(from: stateURL)
        XCTAssertNotNil(state.slots["1"])
        XCTAssertNil(state.slots["1"]?.clearedAt)
        XCTAssertNotNil(state.slots["2"]?.clearedAt)

        // Second run: slot 1 text still present, clear now works.
        src.failClear = []
        src.slots = [Slot(number: 1, text: "Keep me")]
        let r2 = try makeSync().run(source: src)
        XCTAssertEqual(try files().count, 2, "no new file")
        XCTAssertTrue(r2.saved.isEmpty)
        XCTAssertEqual(r2.alreadySaved, [1])
        XCTAssertEqual(r2.cleared, [1])
        XCTAssertEqual(src.clearCalls.suffix(1), [1])
        state = try InboxState.load(from: stateURL)
        XCTAssertNotNil(state.slots["1"]?.clearedAt)
    }

    func testDeletedSavedFileIsSavedAgain() throws {
        let src = FakeSource([Slot(number: 1, text: "Note")])
        let r1 = try makeSync(clear: false).run(source: src)
        try FileManager.default.removeItem(at: r1.saved[0].url)
        let r2 = try makeSync(clear: false).run(source: src)
        XCTAssertEqual(r2.saved.count, 1)
        XCTAssertTrue(r2.alreadySaved.isEmpty)
        XCTAssertEqual(try read(r2.saved[0].url.lastPathComponent), "Note")
    }

    func testEditedSavedFileIsSavedAgainAsNewFile() throws {
        let src = FakeSource([Slot(number: 1, text: "Note")])
        let r1 = try makeSync(clear: false).run(source: src)
        let edited = "Note edited by user"
        try edited.write(to: r1.saved[0].url, atomically: true, encoding: .utf8)
        let r2 = try makeSync(clear: false).run(source: src)
        XCTAssertEqual(r2.saved.count, 1)
        XCTAssertNotEqual(r2.saved[0].url, r1.saved[0].url)
        XCTAssertEqual(r2.saved[0].url.lastPathComponent, "\(prefix()) Note 2.txt")
        XCTAssertEqual(try String(contentsOf: r1.saved[0].url, encoding: .utf8), edited, "user's edit preserved")
        XCTAssertEqual(try read("\(prefix()) Note 2.txt"), "Note")
    }

    func testNameClashNeverOverwrites() throws {
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let existing = dest.appendingPathComponent("\(prefix()) Idea.txt")
        try "precious".write(to: existing, atomically: true, encoding: .utf8)
        let report = try makeSync().run(source: FakeSource([Slot(number: 1, text: "Idea\nx")]))
        XCTAssertEqual(try String(contentsOf: existing, encoding: .utf8), "precious")
        XCTAssertEqual(report.saved.first?.url.lastPathComponent, "\(prefix()) Idea 2.txt")
        XCTAssertEqual(try read("\(prefix()) Idea 2.txt"), "Idea\nx")
    }

    func testSameFirstLineInOneSync() throws {
        let src = FakeSource([Slot(number: 1, text: "Dup\nA"), Slot(number: 2, text: "Dup\nB")])
        let report = try makeSync().run(source: src)
        let p = prefix()
        XCTAssertEqual(try files(), ["\(p) Dup 2.txt", "\(p) Dup.txt"])
        XCTAssertEqual(try read("\(p) Dup.txt"), "Dup\nA")
        XCTAssertEqual(try read("\(p) Dup 2.txt"), "Dup\nB")
        XCTAssertEqual(report.saved.map(\.slot), [1, 2])
    }

    func testNoTempFilesLeftBehind() throws {
        _ = try makeSync().run(source: FakeSource([Slot(number: 1, text: "a"), Slot(number: 2, text: "b")]))
        XCTAssertTrue(try files().filter { $0.hasPrefix(".nanoneo-") || $0.hasSuffix(".tmp") }.isEmpty)
        XCTAssertEqual(try files().count, 2)
    }

    func testDestinationCreatedIfMissing() throws {
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest.path))
        _ = try makeSync().run(source: FakeSource([]))
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)
    }

    func testStateLastSyncRecordedWithNoSlots() throws {
        _ = try makeSync().run(source: FakeSource([]))
        XCTAssertNotNil(try InboxState.load(from: stateURL).lastSync)
    }
}
