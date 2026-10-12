import XCTest
@testable import NeoKit

final class AlphaWordTextTests: XCTestCase {
    private func d(_ b: [UInt8]) -> String { AlphaWordText.decode(b) }

    func testPaddingDropped() {
        XCTAssertEqual(d([UInt8](repeating: 0xA7, count: 512)), "")
        XCTAssertEqual(d([0xA4, 0x41, 0xA7, 0x42]), "AB")
    }

    func testCarriageReturnBecomesNewline() { XCTAssertEqual(d([0x41, 0x0D, 0x42]), "A\nB") }
    func testLineBreakingSpace() {
        XCTAssertEqual(d([0x41, 0x81, 0x42]), "A B")
        XCTAssertEqual(d([0x41, 0xA1, 0x42]), "A B")
    }
    func testLineBreakingTab() {
        XCTAssertEqual(d([0x41, 0x8D, 0x42]), "A\tB")
        XCTAssertEqual(d([0x41, 0xA3, 0x42]), "A\tB")
    }
    func testHardBreakDropped() { XCTAssertEqual(d([0x41, 0x8F, 0x42]), "AB") }
    func testLineBreakingHyphen() { XCTAssertEqual(d([0x41, 0xAD, 0x42]), "A-B") }

    func testEscapeYieldsMapGlyph() {
        XCTAssertEqual(d([0xB0, 0x0D, 0xB0]), "\u{21B5}")
        XCTAssertEqual(d([0xB0, 0x41, 0xB0, 0x42]), "AB")
        XCTAssertEqual(d([0xB0, 0x09, 0xB0]), "\u{21E5}")
    }

    func testTruncatedEscapeDoesNotCrash() {
        XCTAssertEqual(d([0x41, 0xB0]), "A")
        XCTAssertEqual(d([0x41, 0xB0, 0x42]), "AB")
        XCTAssertEqual(d([0xB0]), "")
    }

    func testPlainASCII() { XCTAssertEqual(d(Array("Hello, World!".utf8)), "Hello, World!") }

    func testHighBytesViaMap() {
        XCTAssertEqual(d([0x80]), "€")
        XCTAssertEqual(d([0xE9]), "é")
        XCTAssertEqual(d([0x41, 0xE9, 0xFF]), "Aéÿ")
    }

    func testUntrappedEscapeRangeDropped() {
        XCTAssertEqual(d([0xA2, 0xBF, 0x41]), "A")
    }

    func testCustomMapAndCollection() {
        var map = CharacterMap.enUS
        map[0x41] = 0x5A
        XCTAssertEqual(AlphaWordText.decode(Data([0x41]), map: map), "Z")
    }

    func testMapShape() { XCTAssertEqual(CharacterMap.enUS.count, 256) }
}
