import XCTest
@testable import SaptakCore

final class PlaybackQueueTests: XCTestCase {
    private let tracks = ["a", "b", "c"].map { AudioTrack(url: URL(fileURLWithPath: "/\($0).m4a")) }

    func testEmptyQueueAndInvalidSelectionAreSafe() {
        var queue = PlaybackQueue()
        XCTAssertNil(queue.current)
        XCTAssertFalse(queue.advance())
        XCTAssertFalse(queue.previous())
        queue.select(10)
        queue.toggleShuffle()
        XCTAssertNil(queue.current)
    }

    func testNaturalCompletionAndManualNextHaveDifferentRepeatOneBehavior() {
        var queue = PlaybackQueue()
        queue.replace(with: tracks)
        queue.repeatMode = .one
        XCTAssertTrue(queue.advance(automatically: true))
        XCTAssertEqual(queue.current, tracks[0])
        XCTAssertTrue(queue.advance())
        XCTAssertEqual(queue.current, tracks[1])
    }

    func testRepeatAllWrapsInBothDirections() {
        var queue = PlaybackQueue()
        queue.replace(with: tracks)
        queue.repeatMode = .all
        XCTAssertTrue(queue.previous())
        XCTAssertEqual(queue.current, tracks[2])
        XCTAssertTrue(queue.advance(automatically: true))
        XCTAssertEqual(queue.current, tracks[0])
    }

    func testQueueStopsAtEndWithRepeatOff() {
        var queue = PlaybackQueue()
        queue.replace(with: tracks)
        queue.select(2)
        XCTAssertFalse(queue.advance(automatically: true))
        XCTAssertEqual(queue.current, tracks[2])
        queue.select(-1)
        XCTAssertEqual(queue.index, 2)
    }

    func testShufflePreservesSelectionAndRestoresOriginalOrder() {
        var queue = PlaybackQueue()
        queue.replace(with: tracks)
        queue.select(1)
        queue.toggleShuffle()
        XCTAssertTrue(queue.isShuffled)
        XCTAssertEqual(queue.current, tracks[1])
        XCTAssertEqual(queue.index, 0)
        XCTAssertEqual(Set(queue.tracks), Set(tracks))
        queue.toggleShuffle()
        XCTAssertEqual(queue.tracks, tracks)
        XCTAssertEqual(queue.index, 1)
        XCTAssertFalse(queue.isShuffled)
    }

    func testReplacingQueueResetsSelectionAndShuffleButPreservesRepeatPreference() {
        var queue = PlaybackQueue()
        queue.repeatMode = .all
        queue.replace(with: tracks, shuffled: true)
        XCTAssertEqual(Set(queue.tracks), Set(tracks))
        queue.replace(with: [])
        XCTAssertNil(queue.current)
        XCTAssertFalse(queue.isShuffled)
        XCTAssertEqual(queue.repeatMode, .all)
        XCTAssertEqual(RepeatMode.off.next.next.next, .off)
    }
}
