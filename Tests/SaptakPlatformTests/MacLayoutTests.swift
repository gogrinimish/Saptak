import XCTest
import SwiftUI
@testable import SaptakPlatform

final class MacLayoutTests: XCTestCase {
    private func verifyRegions(size: CGSize, header: CGFloat, footer: CGFloat,
                               file: StaticString = #filePath, line: UInt = #line) {
        let regions = MacLibraryColumn.Regions(size: size, headerHeight: header, footerHeight: footer)
        let frames = [regions.header, regions.content, regions.footer]
        for frame in frames {
            XCTAssertGreaterThanOrEqual(frame.minY, 0, file: file, line: line)
            XCTAssertGreaterThanOrEqual(frame.height, 0, file: file, line: line)
            XCTAssertLessThanOrEqual(frame.maxY, max(0, size.height), file: file, line: line)
            XCTAssertEqual(frame.width, max(0, size.width), file: file, line: line)
        }
        XCTAssertEqual(regions.header.maxY, regions.content.minY, file: file, line: line)
        XCTAssertEqual(regions.content.maxY, regions.footer.minY, file: file, line: line)
        XCTAssertEqual(regions.footer.maxY, max(0, size.height), file: file, line: line)
    }

    func testMinimumWindowKeepsTabsAndPlayerInsideDetail() {
        verifyRegions(size: CGSize(width: 400, height: 520), header: 69, footer: 220)
        let regions = MacLibraryColumn.Regions(size: CGSize(width: 400, height: 520), headerHeight: 69, footerHeight: 220)
        XCTAssertEqual(regions.content.height, 231)
        XCTAssertEqual(regions.footer.height, 220)
    }

    func testSidebarKeepsBrandAndChangeFolderVisible() {
        verifyRegions(size: CGSize(width: 240, height: 520), header: 76, footer: 76)
    }

    func testLargeWindowAllocatesExtraHeightToRecordings() {
        let regions = MacLibraryColumn.Regions(size: CGSize(width: 1100, height: 1000), headerHeight: 69, footerHeight: 160)
        XCTAssertEqual(regions.content.height, 771)
        verifyRegions(size: CGSize(width: 1100, height: 1000), header: 69, footer: 160)
    }

    func testAccessibilityHeightCannotProduceNegativeContent() {
        verifyRegions(size: CGSize(width: 240, height: 520), header: 240, footer: 400)
    }

    func testZeroSizeDuringResizeIsSafe() {
        verifyRegions(size: .zero, header: 76, footer: 220)
    }

    func testNegativeTransientDimensionsAreClamped() {
        verifyRegions(size: CGSize(width: -1, height: -1), header: 76, footer: 220)
    }

    func testEmptyHeaderAndFooterLeaveEntireContentArea() {
        let regions = MacLibraryColumn.Regions(size: CGSize(width: 400, height: 520), headerHeight: 0, footerHeight: 0)
        XCTAssertEqual(regions.content, CGRect(x: 0, y: 0, width: 400, height: 520))
    }

    func testRapidResizeSequenceLeavesNoBottomGap() {
        for height in Array(stride(from: 520, through: 1400, by: 11)) + Array(stride(from: 1400, through: 520, by: -13)) {
            verifyRegions(size: CGSize(width: 800, height: CGFloat(height)), header: 69, footer: 180)
        }
    }

    /// Exercise SwiftUI's real Layout protocol, not just region arithmetic. The
    /// middle advertises a huge ideal height to reproduce a long scrolling list.
    @MainActor func testRenderedColumnBoundsOversizedContentAtMultipleSizes() throws {
        for size in [CGSize(width: 240, height: 520), CGSize(width: 400, height: 520),
                     CGSize(width: 720, height: 720), CGSize(width: 1200, height: 1100),
                     CGSize(width: 400, height: 520)] {
            let record = LayoutRecord()
            let view = MacLibraryColumn {
                MeasuredRegion(record: record, name: "header", idealHeight: 69) { Color.red }
                MeasuredRegion(record: record, name: "content", idealHeight: 10000) { Color.green }
                MeasuredRegion(record: record, name: "footer", idealHeight: 180) { Color.blue }
            }.frame(width: size.width, height: size.height)
            let renderer = ImageRenderer(content: view)
            renderer.proposedSize = ProposedViewSize(size)
            XCTAssertNotNil(renderer.cgImage)
            let header = try XCTUnwrap(record.frames["header"])
            let content = try XCTUnwrap(record.frames["content"])
            let footer = try XCTUnwrap(record.frames["footer"])
            XCTAssertEqual(header.minY, 0, accuracy: 0.5)
            XCTAssertEqual(header.height, 69, accuracy: 0.5)
            XCTAssertEqual(content.minY, header.maxY, accuracy: 0.5)
            XCTAssertEqual(content.maxY, footer.minY, accuracy: 0.5)
            XCTAssertEqual(footer.height, 180, accuracy: 0.5)
            XCTAssertEqual(footer.maxY, size.height, accuracy: 0.5)
        }
    }

    @MainActor func testActualPlayerRemainsVisibleInNarrowAndWideColumns() throws {
        let player = PlayerModel()
        for width in [CGFloat(320), 400, 600, 1000] {
            let record = LayoutRecord()
            let view = MacLibraryColumn {
                MeasuredRegion(record: record, name: "header", idealHeight: 69) { Color.clear }
                MeasuredRegion(record: record, name: "content", idealHeight: 10000) { Color.clear }
                MeasuredRegion(record: record, name: "footer", idealHeight: nil) {
                    PlaybackControls().environmentObject(player)
                }
            }.frame(width: width, height: 520)
            let renderer = ImageRenderer(content: view)
            XCTAssertNotNil(renderer.cgImage)
            let footer = try XCTUnwrap(record.frames["footer"])
            XCTAssertGreaterThan(footer.height, 100, "Transport and seeking need usable space")
            XCTAssertLessThan(footer.height, 350, "Player must leave space for recordings")
            XCTAssertEqual(footer.maxY, 520, accuracy: 0.5)
            XCTAssertGreaterThan(try XCTUnwrap(record.frames["content"]).height, 100)
        }
    }

}

private final class LayoutRecord {
    var frames: [String: CGRect] = [:]
}

private struct MeasuredRegion: Layout {
    let record: LayoutRecord
    let name: String
    let idealHeight: CGFloat?

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        if let idealHeight {
            return CGSize(width: proposal.width ?? 400, height: proposal.height ?? idealHeight)
        }
        return subviews.first?.sizeThatFits(proposal) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        record.frames[name] = bounds
        for view in subviews {
            view.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
        }
    }
}
