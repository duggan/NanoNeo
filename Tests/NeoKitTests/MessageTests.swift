import XCTest
@testable import NeoKit

final class MessageTests: XCTestCase {
    func testNoArgsChecksum() {
        XCTAssertEqual(Message(0x1a).bytes, [0x1a, 0, 0, 0, 0, 0, 0, 0x1a])
    }

    func testChecksumIsLowByteOfSum() {
        let m = Message(0xF0, [(0xFF, 1, 1), (0xFF, 2, 1), (0xFF, 3, 1)])
        // 0xF0 + 3*0xFF = 0x3ED -> 0xED
        XCTAssertEqual(m.bytes[7], 0xED)
        XCTAssertEqual(m.bytes[7], m.checksum)
    }

    func testBigEndianPacking() {
        let m = Message(0x13, [(0x01020304, 1, 4), (0xA000, 5, 2)])
        XCTAssertEqual(Array(m.bytes[1...4]), [1, 2, 3, 4])
        XCTAssertEqual(Array(m.bytes[5...6]), [0xA0, 0x00])
        XCTAssertEqual(m.argument(1, 4), 0x01020304)
        XCTAssertEqual(m.argument(5, 2), 0xA000)
        XCTAssertEqual(m.bytes[7], 0xBD)
    }

    func testSingleByteAtOffset() {
        let m = Message(0x10, [(0x7F, 3, 1)])
        XCTAssertEqual(m.bytes, [0x10, 0, 0, 0x7F, 0, 0, 0, 0x8F])
        XCTAssertEqual(m.argument(3, 1), 0x7F)
    }

    func testRawResponseArguments() {
        let m = Message(raw: [0x58, 0x00, 0x0e, 0xac, 0x34, 0x05, 0x8f, 0xda])
        XCTAssertEqual(m.command, 0x58)
        XCTAssertEqual(m.argument(1, 4), 0x000eac34)
        XCTAssertEqual(m.argument(5, 2), 0x058f)
        XCTAssertEqual(m.checksum, 0xda)
    }

    func testDescription() {
        XCTAssertEqual(Message(0x1a).description, "1a 00 00 00 00 00 00 1a")
    }

    func testDataChecksumWrapsAt16Bits() {
        XCTAssertEqual(dataChecksum([UInt8]()), 0)
        XCTAssertEqual(dataChecksum([1, 2, 3] as [UInt8]), 6)
        XCTAssertEqual(dataChecksum([UInt8](repeating: 0xFF, count: 257)), (255 * 257) & 0xFFFF)
        XCTAssertEqual(dataChecksum([UInt8](repeating: 0xFF, count: 258)), (255 * 258) & 0xFFFF)
        XCTAssertLessThan(dataChecksum([UInt8](repeating: 0xFF, count: 1000)), 0x10000)
    }
}
