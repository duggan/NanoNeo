import XCTest
@testable import NeoKit

final class InboxNamingTests: XCTestCase {
    let utc = TimeZone(identifier: "UTC")!
    let date = Date(timeIntervalSince1970: 1_700_000_000)  // 2023-11-14 22:13:20 UTC

    func testBaseName() {
        XCTAssertEqual(InboxNaming.baseName(for: "Hello\nworld", date: date, timeZone: utc), "2023-11-14 2213 Hello")
    }

    func testBaseNameRespectsTimeZone() {
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        XCTAssertEqual(InboxNaming.baseName(for: "x", date: date, timeZone: tokyo), "2023-11-15 0713 x")
    }

    func testFirstNonBlankLine() {
        XCTAssertEqual(InboxNaming.title(for: "\n  \n\t\nReal title\nsecond"), "Real title")
    }

    func testSlashColonReplacedAndWhitespaceCollapsed() {
        XCTAssertEqual(InboxNaming.title(for: "a/b:c    d\te"), "a b c d e")
        XCTAssertEqual(InboxNaming.title(for: "Re: 1/2"), "Re 1 2")
    }

    func testLeadingDotsRemoved() {
        XCTAssertEqual(InboxNaming.title(for: "...hidden"), "hidden")
        XCTAssertEqual(InboxNaming.title(for: "..."), "Untitled")
    }

    func testLongTitleTruncatesAtWordBoundary() {
        let t = InboxNaming.title(for: "The quick brown fox jumps over the lazy dog again and again and again")
        XCTAssertEqual(t, "The quick brown fox jumps over the lazy dog again")
        XCTAssertLessThanOrEqual(t.count, 50)
    }

    func testLongTitleWithEarlySpaceHardCuts() {
        let text = "short " + String(repeating: "x", count: 70)
        let t = InboxNaming.title(for: text)
        XCTAssertEqual(t, String(text.prefix(50)))
        XCTAssertEqual(t.count, 50)
    }

    func testWordBoundaryExactlyAt20Qualifies() {
        // space at index 20 -> allowed
        let text = String(repeating: "a", count: 20) + " " + String(repeating: "b", count: 60)
        XCTAssertEqual(InboxNaming.title(for: text), String(repeating: "a", count: 20))
    }

    func testWordBoundaryAt19HardCuts() {
        let text = String(repeating: "a", count: 19) + " " + String(repeating: "b", count: 60)
        XCTAssertEqual(InboxNaming.title(for: text).count, 50)
    }

    func testExactly50NotTruncated() {
        let text = String(repeating: "a", count: 50)
        XCTAssertEqual(InboxNaming.title(for: text), text)
    }

    func testTrailingPunctuationTrimmed() {
        XCTAssertEqual(InboxNaming.title(for: "Hello world,;.- – — "), "Hello world")
        XCTAssertEqual(InboxNaming.title(for: String(repeating: "x", count: 49) + "." + "yyyy"), String(repeating: "x", count: 49))
    }

    func testBlankTextIsUntitled() {
        XCTAssertEqual(InboxNaming.title(for: ""), "Untitled")
        XCTAssertEqual(InboxNaming.title(for: " \n\t \n"), "Untitled")
        XCTAssertEqual(InboxNaming.baseName(for: "  ", date: date, timeZone: utc), "2023-11-14 2213 Untitled")
    }

    func testCandidates() {
        XCTAssertEqual(Array(InboxNaming.candidates(base: "x").prefix(3)), ["x.txt", "x 2.txt", "x 3.txt"])
    }
}
