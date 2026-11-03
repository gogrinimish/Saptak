import XCTest
@testable import SaptakCore

final class CarPlayCatalogTests: XCTestCase {
    private let rootURL = URL(fileURLWithPath: "/Audio", isDirectory: true)

    private func track(_ name: String) -> AudioTrack { AudioTrack(url: rootURL.appendingPathComponent(name)) }
    private func folder(_ path: String, children: [AudioFolder] = [], tracks: [AudioTrack] = []) -> AudioFolder {
        AudioFolder(url: rootURL.appendingPathComponent(path), children: children, tracks: tracks)
    }

    func testBrowsingAndParentFollowActualHierarchyAndResetPage() {
        let leaf = folder("Lessons/Raag", tracks: [track("Lessons/Raag/one.opus")])
        let child = folder("Lessons", children: [leaf])
        let root = AudioFolder(url: rootURL, children: [child], tracks: [])
        var catalog = CarPlayCatalog()
        XCTAssertEqual(catalog.folder(in: root).url, rootURL)
        catalog.browse(leaf.url, in: root)
        catalog.showPage(3)
        catalog.parent(in: root)
        XCTAssertEqual(catalog.selectedURL, child.url)
        XCTAssertEqual(catalog.page, 0)
        catalog.parent(in: root)
        catalog.parent(in: root)
        XCTAssertEqual(catalog.selectedURL, rootURL)
    }

    func testRefreshRecoversNearestSurvivingFolderAndDifferentRoot() {
        let leaf = folder("Lessons/Raag")
        let child = folder("Lessons", children: [leaf])
        var root = AudioFolder(url: rootURL, children: [child], tracks: [])
        var catalog = CarPlayCatalog()
        catalog.browse(leaf.url, in: root)
        catalog.showPage(2)
        root = AudioFolder(url: rootURL, children: [folder("Lessons")], tracks: [])
        XCTAssertEqual(catalog.folder(in: root).url, child.url)
        XCTAssertEqual(catalog.page, 0)
        let replacement = AudioFolder(url: URL(fileURLWithPath: "/Other"), children: [], tracks: [])
        XCTAssertEqual(catalog.folder(in: replacement).url, replacement.url)
    }

    func testStaleOrUnrelatedFolderSelectionDoesNotChangeBrowsing() {
        let root = AudioFolder(url: rootURL, children: [], tracks: [])
        var catalog = CarPlayCatalog()
        _ = catalog.folder(in: root)
        catalog.browse(URL(fileURLWithPath: "/Audio Backup/Lessons"), in: root)
        XCTAssertEqual(catalog.selectedURL, rootURL)
    }

    func testEntriesPreserveFoldersThenDirectTracksAndRecursivePlaylist() throws {
        let nested = track("Lessons/nested.m4a"), direct = track("direct.m4a")
        let child = folder("Lessons", tracks: [nested])
        let root = AudioFolder(url: rootURL, children: [child], tracks: [direct])
        let entries = CarPlayCatalog.entries(in: root)
        XCTAssertEqual(entries.count, 2)
        guard case .folder(let first) = entries[0], case .track(let second) = entries[1] else {
            return XCTFail("Folder browsing must preserve hierarchy")
        }
        XCTAssertEqual(first.url, child.url)
        XCTAssertEqual(second, direct)
        var queue = PlaybackQueue()
        queue.replace(with: root.allTracks)
        queue.select(try XCTUnwrap(CarPlayCatalog.queueIndex(for: nested, in: queue.tracks)))
        XCTAssertEqual(queue.current, nested)
        XCTAssertEqual(queue.tracks, [direct, nested])
    }

    func testPagingReachesEveryEntryWithoutDuplicatesWithinVehicleBudget() {
        let elements = Array(0..<105)
        var visited: [Int] = []
        for index in 0..<6 {
            let page = CarPlayPage(elements, requested: index, capacity: 20)
            XCTAssertLessThanOrEqual(page.items.count + 6, 26)
            XCTAssertEqual(page.hasPrevious, index > 0)
            XCTAssertEqual(page.hasNext, index < 5)
            visited += page.items
        }
        XCTAssertEqual(visited, elements)
    }

    func testPageClampsAfterRemovalAndHandlesEmptyOrZeroLimit() {
        XCTAssertEqual(CarPlayPage([1, 2, 3], requested: 99, capacity: 2).items, [3])
        XCTAssertEqual(CarPlayPage([1, 2], requested: -1, capacity: 1).items, [1])
        XCTAssertTrue(CarPlayPage([1], requested: 1, capacity: 0).items.isEmpty)
        let empty = CarPlayPage<Int>([], requested: 10, capacity: 10)
        XCTAssertEqual(empty.count, 0)
        XCTAssertFalse(empty.hasNext)
        XCTAssertFalse(empty.hasPrevious)
    }

    func testQueueSelectionSurvivesShuffleButRejectsRemovedTrack() {
        let first = track("one.m4a"), second = track("two.opus")
        XCTAssertEqual(CarPlayCatalog.queueIndex(for: first, in: [second, first]), 1)
        XCTAssertNil(CarPlayCatalog.queueIndex(for: first, in: [second]))
    }
}
