import XCTest
import SaptakCore
@testable import SaptakPlatform

final class PlaylistSelectionTests: XCTestCase {
    private func tracks() -> [AudioTrack] {
        (0..<5).map { AudioTrack(url: URL(fileURLWithPath: "/tmp/\(UUID().uuidString)-\($0).m4a")) }
    }

    @MainActor func testSelectingFirstRecordingQueuesWholeFolder() {
        let player = PlayerModel()
        defer { player.stop() }
        let tracks = tracks()
        player.play(tracks, access: nil, startingAt: tracks[0])
        XCTAssertEqual(player.queue.tracks, tracks)
        XCTAssertEqual(player.queue.index, 0)
        player.next()
        XCTAssertEqual(player.queue.current, tracks[1])
    }

    @MainActor func testSelectingMiddleRecordingRetainsEarlierAndUpcomingItems() {
        let player = PlayerModel()
        defer { player.stop() }
        let tracks = tracks()
        player.play(tracks, access: nil, startingAt: tracks[2])
        XCTAssertEqual(player.queue.tracks, tracks)
        XCTAssertEqual(player.queue.current, tracks[2])
        XCTAssertEqual(Array(player.queue.tracks.suffix(from: 3)), Array(tracks[3...]))
        player.previous()
        XCTAssertEqual(player.queue.current, tracks[1])
    }

    @MainActor func testSelectingLastRecordingDoesNotLoopWithRepeatOff() {
        let player = PlayerModel()
        defer { player.stop() }
        let tracks = tracks()
        player.play(tracks, access: nil, startingAt: tracks[4])
        player.next()
        XCTAssertEqual(player.queue.current, tracks[4])
        XCTAssertEqual(player.queue.tracks.count, 5)
    }

    @MainActor func testStaleSelectionDoesNotReplaceCurrentQueue() {
        let player = PlayerModel()
        defer { player.stop() }
        let tracks = tracks()
        player.play(tracks, access: nil, startingAt: tracks[1])
        player.play([], access: nil, startingAt: tracks[1])
        player.play(tracks, access: nil, startingAt: self.tracks()[0])
        XCTAssertEqual(player.queue.tracks, tracks)
        XCTAssertEqual(player.queue.current, tracks[1])
    }

    @MainActor func testShuffleAfterSelectionPreservesSongAndWholePlaylist() {
        let player = PlayerModel()
        defer { player.stop() }
        let tracks = tracks()
        player.play(tracks, access: nil, startingAt: tracks[2])
        player.toggleShuffle()
        XCTAssertEqual(player.queue.current, tracks[2])
        XCTAssertEqual(Set(player.queue.tracks), Set(tracks))
        player.toggleShuffle()
        XCTAssertEqual(player.queue.tracks, tracks)
        XCTAssertEqual(player.queue.index, 2)
    }

    @MainActor func testPlayAllStillStartsAtFirstRecording() {
        let player = PlayerModel()
        defer { player.stop() }
        let tracks = tracks()
        player.play(tracks, access: nil)
        XCTAssertEqual(player.queue.tracks, tracks)
        XCTAssertEqual(player.queue.current, tracks.first)
    }

    @MainActor func testRepeatAllNaturallyPlaysEveryFolderRecordingAcrossTwoCycles() {
        let player = PlayerModel()
        defer { player.stop() }
        let tracks = tracks()
        player.play(tracks, access: nil, startingAt: tracks[0])
        player.cycleRepeat()
        XCTAssertEqual(player.queue.repeatMode, .all)
        for expected in Array(tracks.dropFirst()) + tracks + [tracks[0]] {
            player.playbackDidFinish()
            XCTAssertEqual(player.queue.current, expected)
            XCTAssertEqual(player.queue.tracks, tracks)
        }
    }

    @MainActor func testRepeatAllFromMiddleAdvancesBeforeWrapping() {
        let player = PlayerModel()
        defer { player.stop() }
        let tracks = tracks()
        player.play(tracks, access: nil, startingAt: tracks[2])
        player.cycleRepeat()
        for expected in [tracks[3], tracks[4], tracks[0], tracks[1], tracks[2]] {
            player.playbackDidFinish()
            XCTAssertEqual(player.queue.current, expected)
        }
    }

    @MainActor func testRepeatOneReplaysCurrentRecordingButManualNextAdvances() {
        let player = PlayerModel()
        defer { player.stop() }
        let tracks = tracks()
        player.play(tracks, access: nil, startingAt: tracks[2])
        player.cycleRepeat()
        player.cycleRepeat()
        XCTAssertEqual(player.queue.repeatMode, .one)
        player.playbackDidFinish()
        XCTAssertEqual(player.queue.current, tracks[2])
        player.next()
        XCTAssertEqual(player.queue.current, tracks[3])
    }

    @MainActor func testRepeatAllAfterShuffleVisitsWholeQueueBeforeWrapping() {
        let player = PlayerModel()
        defer { player.stop() }
        let tracks = tracks()
        player.play(tracks, access: nil, startingAt: tracks[2])
        player.toggleShuffle()
        player.cycleRepeat()
        let order = player.queue.tracks
        for expected in Array(order.dropFirst()) + [order[0]] {
            player.playbackDidFinish()
            XCTAssertEqual(player.queue.current, expected)
        }
        XCTAssertEqual(Set(order), Set(tracks))
    }

}
