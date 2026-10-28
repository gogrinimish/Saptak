import XCTest
import SaptakCore
@testable import SaptakPlatform

final class PlaybackRecoveryTests: XCTestCase {
    @MainActor func testCheckpointRoundTripAndInvalidWritePreservesPrevious() {
        let name = "RecoveryTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = PlaybackRecoveryStore(defaults: defaults)
        let url = URL(fileURLWithPath: "/test/track.m4a")
        let saved = PlaybackCheckpoint(urls: [url], current: url, seconds: 42)
        store.write(saved)
        XCTAssertEqual(store.read(), saved)
        store.write(PlaybackCheckpoint(urls: [url], current: url, seconds: -.infinity))
        XCTAssertEqual(store.read(), saved)
        store.write(PlaybackCheckpoint(urls: [], current: url, seconds: 0))
        XCTAssertEqual(store.read(), saved)
    }

    @MainActor func testRestorationDropsMissingTracksAndNeverStartsPlayback() throws {
        let name = "RecoveryTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = PlaybackRecoveryStore(defaults: defaults)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("present.m4a")
        try Data([1, 2, 3]).write(to: url)
        let missing = directory.appendingPathComponent("missing.m4a")
        let root = try LibraryScanner.scan(directory)
        let scannedURL = try XCTUnwrap(root.allTracks.first?.url)
        store.write(PlaybackCheckpoint(urls: [missing, scannedURL], current: scannedURL, seconds: 42))
        let player = PlayerModel(recovery: store)
        player.restoreIfNeeded(root: root, access: nil)
        XCTAssertEqual(player.queue.tracks.map(\.url), [scannedURL])
        XCTAssertEqual(player.position, 42)
        XCTAssertFalse(player.isPlaying)
        XCTAssertFalse(player.isLoading)
        XCTAssertNil(player.error)
        XCTAssertEqual(try Data(contentsOf: url), Data([1, 2, 3]))
        player.stop()
    }

    @MainActor func testMissingCurrentTrackDoesNotRestoreOtherAudio() throws {
        let name = "RecoveryTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = PlaybackRecoveryStore(defaults: defaults)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let missing = directory.appendingPathComponent("missing.m4a")
        store.write(PlaybackCheckpoint(urls: [missing], current: missing, seconds: 12))
        let player = PlayerModel(recovery: store)
        player.restoreIfNeeded(root: try LibraryScanner.scan(directory), access: nil)
        XCTAssertNil(player.queue.current)
        XCTAssertFalse(player.isLoading)
    }

    @MainActor func testCorruptRecoveryDataIsIgnored() {
        let name = "RecoveryTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(Data("invalid".utf8), forKey: "playbackCheckpoint.v1")
        XCTAssertNil(PlaybackRecoveryStore(defaults: defaults).read())
    }

    @MainActor func testInterruptionAndManualPauseDoNotRestartCancelledLoading() {
        let player = PlayerModel()
        let track = AudioTrack(url: URL(fileURLWithPath: "/missing/track.m4a"))
        player.play([track], access: nil)
        XCTAssertTrue(player.isLoading)
        player.interruptionBegan()
        XCTAssertFalse(player.isLoading)
        player.pause()
        player.interruptionEnded(shouldResume: true)
        XCTAssertFalse(player.isLoading)
        XCTAssertFalse(player.isPlaying)
        player.stop()
    }

    func testInterruptionRequiresPriorPlaybackAndSystemPermission() {
        var policy = PlaybackInterruptionPolicy()
        XCTAssertFalse(policy.end(systemAllowsResume: true))
        policy.begin(wasPlaying: false)
        XCTAssertFalse(policy.end(systemAllowsResume: true))
        policy.begin(wasPlaying: true)
        XCTAssertFalse(policy.end(systemAllowsResume: false))
        policy.begin(wasPlaying: true)
        XCTAssertTrue(policy.end(systemAllowsResume: true))
        XCTAssertFalse(policy.end(systemAllowsResume: true))
    }

    func testManualPauseOrDisconnectCancelsAutomaticResume() {
        var policy = PlaybackInterruptionPolicy()
        policy.begin(wasPlaying: true)
        policy.cancelResume()
        XCTAssertFalse(policy.end(systemAllowsResume: true))
    }

    func testDuplicateBeginDoesNotErasePlaybackIntent() {
        var policy = PlaybackInterruptionPolicy()
        policy.begin(wasPlaying: true)
        policy.begin(wasPlaying: false)
        XCTAssertTrue(policy.end(systemAllowsResume: true))
    }
}
