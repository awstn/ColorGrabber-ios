import XCTest
@testable import ColorGrabber

final class ColorConversionTests: XCTestCase {
    func testRed() {
        let color = ColorConversion.oklch(red: 255, green: 0, blue: 0)
        XCTAssertEqual(color.lightness, 0.628, accuracy: 0.001)
        XCTAssertEqual(color.chroma, 0.258, accuracy: 0.001)
        XCTAssertEqual(color.hue, 29.2, accuracy: 0.1)
    }

    func testGreen() {
        let color = ColorConversion.oklch(red: 0, green: 255, blue: 0)
        XCTAssertEqual(color.lightness, 0.866, accuracy: 0.001)
        XCTAssertEqual(color.chroma, 0.295, accuracy: 0.001)
        XCTAssertEqual(color.hue, 142.5, accuracy: 0.1)
    }

    func testBlueHueStaysPositive() {
        let color = ColorConversion.oklch(red: 0, green: 0, blue: 255)
        XCTAssertEqual(color.lightness, 0.452, accuracy: 0.001)
        XCTAssertEqual(color.chroma, 0.313, accuracy: 0.001)
        XCTAssertEqual(color.hue, 264.1, accuracy: 0.1)
    }

    func testGrayHasNoChroma() {
        let color = ColorConversion.oklch(red: 128, green: 128, blue: 128)
        XCTAssertEqual(color.lightness, 0.600, accuracy: 0.001)
        XCTAssertEqual(color.chroma, 0, accuracy: 0.001)
    }
}
