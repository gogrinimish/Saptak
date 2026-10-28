import XCTest
import MediaPlayer
import SaptakCore
@testable import SaptakPlatform

final class SystemPlaybackTests: XCTestCase {
    private func state(title: String? = "Practice", position: Double = 12, duration: Double = 60,
                       playing: Bool = true, loading: Bool = false) -> SystemPlaybackState {
        SystemPlaybackState(title: title, index: title == nil ? nil : 1, count: title == nil ? 0 : 3,
                            position: position, duration: duration, isPlaying: playing,
                            isLoading: loading, canGoNext: title != nil)
    }

    func testMetadataContainsTitleProgressAndQueueContextWithoutPaths() throws {
        let info = try XCTUnwrap(state().metadata)
        XCTAssertEqual(info[MPMediaItemPropertyTitle] as? String, "Practice")
        XCTAssertEqual(info[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double, 12)
        XCTAssertEqual(info[MPMediaItemPropertyPlaybackDuration] as? Double, 60)
        XCTAssertEqual(info[MPNowPlayingInfoPropertyPlaybackRate] as? Double, 1)
        XCTAssertEqual(info[MPNowPlayingInfoPropertyPlaybackQueueIndex] as? Int, 1)
        XCTAssertEqual(info[MPNowPlayingInfoPropertyPlaybackQueueCount] as? Int, 3)
        XCTAssertNil(info[MPMediaItemPropertyAssetURL])
        XCTAssertNil(info[MPMediaItemPropertyAlbumTitle])
        XCTAssertNil(info[MPMediaItemPropertyArtist])
    }

    func testMetadataPausesProgressWhilePausedOrLoading() throws {
        for snapshot in [state(playing: false), state(playing: true, loading: true)] {
            let info = try XCTUnwrap(snapshot.metadata)
            XCTAssertEqual(info[MPNowPlayingInfoPropertyPlaybackRate] as? Double, 0)
        }
    }

    func testMetadataSanitizesInvalidTimesAndDisablesSeeking() throws {
        let snapshot = state(position: .nan, duration: .infinity)
        let info = try XCTUnwrap(snapshot.metadata)
        XCTAssertEqual(info[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double, 0)
        XCTAssertNil(info[MPMediaItemPropertyPlaybackDuration])
        XCTAssertFalse(snapshot.canSeek)
        XCTAssertEqual(state(position: -5).metadata?[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double, 0)
    }

    func testNoTrackClearsMetadataAndDisablesPlay() {
        let snapshot = state(title: nil)
        XCTAssertNil(snapshot.metadata)
        XCTAssertFalse(snapshot.canPlay)
        XCTAssertFalse(snapshot.canSeek)
    }

    func testMetadataOptsOutOfSuggestionsWhereSupported() throws {
        if #available(macOS 15, *) {
            XCTAssertEqual(try XCTUnwrap(state().metadata)[MPNowPlayingInfoPropertyExcludeFromSuggestions] as? Bool, true)
        }
    }

    @MainActor func testPlayerPublishesSelectedTitleAndStopClearsIt() throws {
        let output = RecordingSystemOutput()
        let player = PlayerModel(systemPlayback: output)
        defer { player.stop() }
        let tracks = tracks()
        player.play(tracks, access: nil, startingAt: tracks[1])
        XCTAssertEqual(output.latest?.title, tracks[1].title)
        XCTAssertEqual(output.latest?.index, 1)
        XCTAssertEqual(output.latest?.count, 3)
        XCTAssertTrue(output.latest?.isLoading == true)
        player.stop()
        XCTAssertNil(output.latest?.title)
        XCTAssertNil(output.latest?.metadata)
        XCTAssertFalse(output.send(.play))
    }

    @MainActor func testRemoteNextPreviousAndNaturalCompletionUpdateTitle() {
        let output = RecordingSystemOutput()
        let player = PlayerModel(systemPlayback: output)
        defer { player.stop() }
        let tracks = tracks()
        player.play(tracks, access: nil)
        XCTAssertTrue(output.send(.next))
        XCTAssertEqual(output.latest?.title, tracks[1].title)
        XCTAssertTrue(output.send(.previous))
        XCTAssertEqual(output.latest?.title, tracks[0].title)
        player.playbackDidFinish()
        XCTAssertEqual(output.latest?.title, tracks[1].title)
    }

    @MainActor func testRemotePauseCancelsPendingLoadAndPlayDoesNotToggleIt() async throws {
        let output = RecordingSystemOutput()
        let player = PlayerModel(systemPlayback: output)
        defer { player.stop() }
        player.play(tracks(), access: nil)
        XCTAssertFalse(output.send(.play), "Play during loading must not turn into Pause")
        XCTAssertTrue(output.send(.pause))
        XCTAssertFalse(player.isLoading)
        XCTAssertFalse(player.isPlaying)
        XCTAssertFalse(output.latest?.isPlaying == true)
        XCTAssertTrue(output.send(.pause), "Pause is idempotent")
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertNil(player.error, "Cancelled load must not publish a late playback error")
        XCTAssertTrue(output.send(.play))
        XCTAssertTrue(player.isLoading)
    }

    @MainActor func testRemoteNextRespectsQueueEndAndRepeatAll() {
        let output = RecordingSystemOutput()
        let player = PlayerModel(systemPlayback: output)
        defer { player.stop() }
        let tracks = tracks()
        player.play(tracks, access: nil, startingAt: tracks[2])
        XCTAssertFalse(output.latest?.canGoNext == true)
        XCTAssertFalse(output.send(.next))
        player.cycleRepeat()
        XCTAssertTrue(output.latest?.canGoNext == true)
        XCTAssertTrue(output.send(.next))
        XCTAssertEqual(player.queue.current, tracks[0])
    }

    @MainActor func testRemoteStopAndInvalidSeekAreSafe() {
        let output = RecordingSystemOutput()
        let player = PlayerModel(systemPlayback: output)
        player.play(tracks(), access: nil)
        XCTAssertFalse(output.send(.seek(.nan)))
        XCTAssertFalse(output.send(.seek(20)), "No known duration while loading")
        XCTAssertTrue(output.send(.stop))
        XCTAssertTrue(player.queue.tracks.isEmpty)
        XCTAssertNil(output.latest?.metadata)
        XCTAssertFalse(output.send(.next))
        XCTAssertFalse(output.send(.toggle))
    }

    @MainActor func testRemoteHandlerDoesNotRetainPlayer() {
        let output = RecordingSystemOutput()
        weak var reference: PlayerModel?
        autoreleasepool {
            let player = PlayerModel(systemPlayback: output)
            reference = player
        }
        XCTAssertNil(reference)
        XCTAssertFalse(output.send(.play))
    }

    private func tracks() -> [AudioTrack] {
        (0..<3).map { AudioTrack(url: URL(fileURLWithPath: "/tmp/\(UUID().uuidString)-\($0).m4a")) }
    }
}

@MainActor private final class RecordingSystemOutput: SystemPlaybackOutput {
    private var handler: (@MainActor (SystemPlaybackCommand) -> Bool)?
    var latest: SystemPlaybackState?
    func bind(_ handler: @escaping @MainActor (SystemPlaybackCommand) -> Bool) { self.handler = handler }
    func update(_ state: SystemPlaybackState) { latest = state }
    func send(_ command: SystemPlaybackCommand) -> Bool { handler?(command) ?? false }
}
