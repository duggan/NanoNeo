import XCTest
@testable import NeoKit

final class FileAttributesTests: XCTestCase {
    private func sample() -> [UInt8] {
        var b = [UInt8](repeating: 0, count: 40)
        for (i, c) in "File 3".utf8.enumerated() { b[i] = c }
        b[0x18...0x1B] = [0, 0, 0x02, 0x00]      // 512
        b[0x1C...0x1F] = [0, 0, 0x04, 0x81]      // 1153
        b[0x20...0x23] = [0, 0, 0, 4]
        b[0x25] = 0x04
        return b
    }

    func testParse() throws {
        let a = try FileAttributes(index: 7, raw: sample())
        XCTAssertEqual(a.index, 7)
        XCTAssertEqual(a.name, "File 3")
        XCTAssertEqual(a.password, "")
        XCTAssertEqual(a.minSize, 512)
        XCTAssertEqual(a.allocSize, 1153)
        XCTAssertEqual(a.flags, 4)
        XCTAssertEqual(a.space, 3)
    }

    func testRawRoundTrip() throws {
        var src = sample()
        src[0x24] = 0xAA; src[0x26] = 0xBB; src[0x27] = 0xCC
        let a = try FileAttributes(index: 1, raw: src)
        var expected = src
        expected[0x24] = 0; expected[0x26] = 0; expected[0x27] = 0
        XCTAssertEqual(a.raw, expected)
        XCTAssertEqual(try FileAttributes(index: 1, raw: a.raw), a)
    }

    func testPasswordParsed() throws {
        var b = sample()
        for (i, c) in "secret".utf8.enumerated() { b[0x10 + i] = c }
        let a = try FileAttributes(index: 1, raw: b)
        XCTAssertEqual(a.password, "secret")
        XCTAssertEqual(a.raw, b)
    }

    func testAllSpaceCodes() throws {
        for (space, code) in FileAttributes.spaceCodes.enumerated() {
            var b = sample(); b[0x25] = code
            XCTAssertEqual(try FileAttributes(index: 0, raw: b).space, space)
        }
    }

    func testUnknownSpaceCodeThrows() {
        var b = sample(); b[0x25] = 0x55
        XCTAssertThrowsError(try FileAttributes(index: 1, raw: b))
    }

    func testWrongLengthThrows() {
        XCTAssertThrowsError(try FileAttributes(index: 1, raw: Array(sample().dropLast())))
        XCTAssertThrowsError(try FileAttributes(index: 1, raw: sample() + [0]))
        XCTAssertThrowsError(try FileAttributes(index: 1, raw: []))
    }
}
