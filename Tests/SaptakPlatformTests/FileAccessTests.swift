import XCTest
import AVFoundation
import SaptakCore
@testable import SaptakPlatform

final class FileAccessTests: XCTestCase {
    func testReadPreparationAndScanPreserveOriginalBytesAndDirectory() async throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("voice.m4a")
        let bytes = Data([10, 20, 30, 40])
        try bytes.write(to: source)
        let access = FolderAccess(url: root)
        XCTAssertEqual(try ProviderAccess.scan(access, coordinate: { url, accessor in accessor(url) }).root.allTracks.map(\.title), ["voice"])
        let prepared = try await ProviderAccess.prepare(source, coordinate: { url, accessor in accessor(url) })
        XCTAssertEqual(prepared, source)
        XCTAssertEqual(try Data(contentsOf: source), bytes)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["voice.m4a"])
    }

    func testMissingProviderFileFailsExplicitly() async {
        do {
            _ = try await ProviderAccess.prepare(URL(fileURLWithPath: "/tmp/\(UUID().uuidString).m4a"))
            XCTFail("Missing recordings must not appear playable")
        } catch { XCTAssertFalse(error.localizedDescription.isEmpty) }
    }

    func testM4AFixtureIsPlayableWithoutImport() async throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("sample.m4a")
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "tone", withExtension: "m4a", subdirectory: "Fixtures"))
        try FileManager.default.copyItem(at: fixture, to: url)
        let before = try Data(contentsOf: url)
        let prepared = try await ProviderAccess.prepare(url, coordinate: { url, accessor in accessor(url) })
        let asset = AVURLAsset(url: prepared)
        let playable = try await asset.load(.isPlayable)
        let duration = try await asset.load(.duration)
        XCTAssertTrue(playable)
        XCTAssertGreaterThan(duration.seconds, 0)
        XCTAssertEqual(try Data(contentsOf: url), before)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["sample.m4a"])
    }

    @MainActor func testPlayerStopClearsQueueAndControlsHandleEmptyState() {
        let model = PlayerModel()
        model.toggle()
        model.previous()
        model.next()
        model.seek(to: .nan)
        model.stop()
        XCTAssertTrue(model.queue.tracks.isEmpty)
        XCTAssertFalse(model.isPlaying)
        XCTAssertFalse(model.isLoading)
        XCTAssertEqual(model.position, 0)
    }
    func testNativeFileCoordinationIntegration() async throws {
        guard ProcessInfo.processInfo.environment["SAPTAK_NATIVE_INTEGRATION"] == "1" else {
            throw XCTSkip("Requires native file-coordination services; set SAPTAK_NATIVE_INTEGRATION=1 on an unrestricted Mac.")
        }
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "tone", withExtension: "m4a", subdirectory: "Fixtures"))
        let prepared = try await ProviderAccess.prepare(fixture)
        XCTAssertEqual(prepared, fixture)
        XCTAssertEqual(try ProviderAccess.scan(FolderAccess(url: fixture.deletingLastPathComponent())).root.allTracks.count, 1)
    }

    func testCoordinationFailureIsPropagated() throws {
        let folder = FolderAccess(url: URL(fileURLWithPath: "/tmp"))
        XCTAssertThrowsError(try ProviderAccess.scan(folder, coordinate: { _, _ in
            throw CocoaError(.fileReadNoPermission)
        })) { error in
            XCTAssertEqual((error as? CocoaError)?.code, .fileReadNoPermission)
        }
        XCTAssertThrowsError(try ProviderAccess.scan(folder, coordinate: { _, _ in }))
    }

    @MainActor func testPlaybackFailureRetainsQueueAndReportsUsefulError() async throws {
        let model = PlayerModel()
        let missing = AudioTrack(url: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).m4a"))
        model.play([missing], access: nil)
        for _ in 0..<100 {
            if !model.isLoading { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertFalse(model.isLoading)
        XCTAssertFalse(model.isPlaying)
        XCTAssertEqual(model.queue.current, missing)
        XCTAssertTrue(model.error?.contains("Could not play") == true)
        model.stop()
    }

    @MainActor func testStopAndNextAtEndCancelPendingPlayback() async throws {
        let model = PlayerModel()
        let missing = AudioTrack(url: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).m4a"))
        model.play([missing], access: nil)
        model.next()
        XCTAssertFalse(model.isLoading)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNil(model.error)
        XCTAssertFalse(model.isPlaying)
        model.play([missing], access: nil)
        model.stop()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(model.queue.tracks.isEmpty)
        XCTAssertFalse(model.isLoading)
        XCTAssertFalse(model.isPlaying)
        XCTAssertNil(model.error)
    }

}
