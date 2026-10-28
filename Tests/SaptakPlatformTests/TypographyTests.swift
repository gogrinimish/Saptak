import XCTest
import SwiftUI
import CoreText
@testable import SaptakPlatform

final class TypographyTests: XCTestCase {
    func testBundledFontRegistersItsRealFaceAndIncludesLicense() throws {
        let url = try XCTUnwrap(SaptakTypography.fontURL)
        XCTAssertGreaterThan(try Data(contentsOf: url).count, 1000)
        XCTAssertTrue(SaptakTypography.isAvailable)
        let font = CTFontCreateWithName(SaptakTypography.fontName as CFString, 20, nil)
        XCTAssertEqual(CTFontCopyPostScriptName(font) as String, "Alice-Regular")
        let licenseURL = try XCTUnwrap(SaptakTypography.resourceBundle.url(
            forResource: "OFL", withExtension: "txt", subdirectory: "Fonts"))
        let license = try String(contentsOf: licenseURL)
        XCTAssertTrue(license.contains("SIL OPEN FONT LICENSE Version 1.1"))
        XCTAssertTrue(license.contains("The Alice Project Authors"))
    }

    @MainActor func testRenderedTextHierarchyUsesTheBundledFaceAtDistinctSizes() throws {
        func height(_ role: SaptakTextRole) throws -> Int {
            let content = Text("Saptak").saptakText(role).fixedSize()
            return try XCTUnwrap(ImageRenderer(content: content).cgImage).height
        }
        XCTAssertGreaterThan(try height(.paneTitle), try height(.item))
        XCTAssertGreaterThan(try height(.item), try height(.metadata))
    }

    @MainActor func testAlreadyScaledFontIsNotScaledAgain() throws {
        func height(_ size: DynamicTypeSize) throws -> Int {
            let content = Text("Saptak").font(SaptakTypography.scaled(24))
                .environment(\.dynamicTypeSize, size).fixedSize()
            return try XCTUnwrap(ImageRenderer(content: content).cgImage).height
        }
        XCTAssertEqual(try height(.large), try height(.accessibility5))
    }

}
