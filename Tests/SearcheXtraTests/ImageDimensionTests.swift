import Foundation
import ImageIO
import XCTest
@testable import SearcheXtra

final class ImageDimensionTests: XCTestCase {
    func testImageHeaderDimensionsCannotOverflowPixelLimit() throws {
        let data = tiff(width: .max, height: .max)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        // Verify this fixture reaches the size check, rather than merely
        // passing because ImageIO rejected a malformed image beforehand.
        XCTAssertEqual((properties[kCGImagePropertyPixelWidth] as? NSNumber)?.uint64Value, UInt64(UInt32.max))
        XCTAssertEqual((properties[kCGImagePropertyPixelHeight] as? NSNumber)?.uint64Value, UInt64(UInt32.max))
        XCTAssertFalse(Browser.reasonable(data))
    }

    func testSmallImageAcceptedAndOversizedHeadersRejected() {
        XCTAssertTrue(Browser.reasonable(tiff(width: 8, height: 8)))
        XCTAssertFalse(Browser.reasonable(tiff(width: 100_000_001, height: 1)))
        XCTAssertFalse(Browser.reasonable(tiff(width: 1, height: 100_000_001)))
        XCTAssertFalse(Browser.reasonable(tiff(width: 0, height: 8)))
        XCTAssertFalse(Browser.reasonable(Data()))
    }

    /// An uncompressed, one-strip greyscale TIFF. Only the header changes;
    /// no test attempts to allocate or decode the declared huge bitmap.
    private func tiff(width: UInt32, height: UInt32) -> Data {
        var data = Data([0x49, 0x49, 42, 0, 8, 0, 0, 0])
        func short(_ value: UInt16) {
            data.append(UInt8(truncatingIfNeeded: value))
            data.append(UInt8(truncatingIfNeeded: value >> 8))
        }
        func long(_ value: UInt32) {
            for shift in stride(from: 0, to: 32, by: 8) {
                data.append(UInt8(truncatingIfNeeded: value >> shift))
            }
        }
        let entries: [(UInt16, UInt16, UInt32)] = [
            (256, 4, width), (257, 4, height), (258, 3, 8),
            (259, 3, 1), (262, 3, 1), (273, 4, 122),
            (277, 3, 1), (278, 4, height), (279, 4, 64),
        ]
        short(UInt16(entries.count))
        for (tag, type, value) in entries {
            short(tag); short(type); long(1); long(value)
        }
        long(0)
        data.append(Data(repeating: 128, count: 64))
        return data
    }
}
