import XCTest
import SwiftUI
import SaptakCore
@testable import SaptakPlatform

final class PlayerDockLayoutTests: XCTestCase {
    func testBrowserViewportExcludesPlayerHeight() {
        let regions = PlayerDockLayout.Regions(size: CGSize(width: 390, height: 750), playerHeight: 90)
        XCTAssertEqual(regions.browser, CGRect(x: 0, y: 0, width: 390, height: 660))
        XCTAssertEqual(regions.player, CGRect(x: 0, y: 660, width: 390, height: 90))
    }

    func testOversizedFooterAndTransientSizesNeverOverlapBrowser() {
        for size in [CGSize.zero, CGSize(width: -1, height: -1), CGSize(width: 320, height: 40)] {
            let regions = PlayerDockLayout.Regions(size: size, playerHeight: 180)
            XCTAssertGreaterThanOrEqual(regions.browser.height, 0)
            XCTAssertGreaterThanOrEqual(regions.player.height, 0)
            XCTAssertEqual(regions.browser.maxY, regions.player.minY)
            XCTAssertEqual(regions.player.maxY, max(0, size.height))
        }
    }

    @MainActor func testRealCompactPlayerStaysBelowBrowserAtPhoneAndLandscapeSizes() throws {
        try renderAndCheck(sizes: [CGSize(width: 320, height: 480), CGSize(width: 393, height: 750),
                                   CGSize(width: 430, height: 860), CGSize(width: 844, height: 340)],
                           longTitle: false, dynamicType: .large)
    }

    @MainActor func testLongTitleAndAccessibilityTextReserveActualPlayerHeight() throws {
        try renderAndCheck(sizes: [CGSize(width: 320, height: 600), CGSize(width: 393, height: 750)],
                           longTitle: true, dynamicType: .accessibility3)
    }

    @MainActor func testResizeBackToSmallHeightDoesNotKeepAnOldViewport() throws {
        try renderAndCheck(sizes: [CGSize(width: 393, height: 750), CGSize(width: 844, height: 340),
                                   CGSize(width: 393, height: 750), CGSize(width: 320, height: 480)],
                           longTitle: true, dynamicType: .large)
    }

    @MainActor private func renderAndCheck(sizes: [CGSize], longTitle: Bool, dynamicType: DynamicTypeSize) throws {
        let player = PlayerModel()
        defer { player.stop() }
        if longTitle {
            let title = String(repeating: "A long practice track title ", count: 6)
            player.play([AudioTrack(url: URL(fileURLWithPath: "/tmp/\(title).m4a"))], access: nil)
        }
        for size in sizes {
            let record = DockBounds()
            let view = PlayerDockLayout {
                DockRegion(record: record, name: "browser", idealHeight: 10000) { Color.clear }
                DockRegion(record: record, name: "player", idealHeight: nil) {
                    CompactPlayerView(expand: {}).environmentObject(player)
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                        .clipped()
                }
            }
            .environment(\.dynamicTypeSize, dynamicType)
            .frame(width: size.width, height: size.height)
            let renderer = ImageRenderer(content: view)
            XCTAssertNotNil(renderer.cgImage)
            let browser = try XCTUnwrap(record.frames["browser"])
            let dock = try XCTUnwrap(record.frames["player"])
            XCTAssertEqual(browser.minY, 0, accuracy: 0.5)
            XCTAssertEqual(browser.maxY, dock.minY, accuracy: 0.5)
            XCTAssertEqual(dock.maxY, size.height, accuracy: 0.5)
            XCTAssertEqual(dock.width, size.width, accuracy: 0.5)
            XCTAssertGreaterThanOrEqual(dock.height, 44)
            XCTAssertGreaterThan(browser.height, 44)
        }
    }
}

private final class DockBounds {
    var frames: [String: CGRect] = [:]
}

private struct DockRegion: Layout {
    let record: DockBounds
    let name: String
    let idealHeight: CGFloat?

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        if let idealHeight { return CGSize(width: proposal.width ?? 390, height: proposal.height ?? idealHeight) }
        return subviews.first?.sizeThatFits(proposal) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        record.frames[name] = bounds
        for view in subviews { view.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size)) }
    }
}
