import XCTest
import SaptakCore
@testable import SaptakPlatform

final class OriginalFileSharingTests: XCTestCase {
    @MainActor func testPreparationReturnsOriginalWithoutChangingBytesOrCreatingCopies() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("original.opus")
        let bytes = Data([1, 2, 3, 4])
        try bytes.write(to: url)
        let model = OriginalFileShareModel(access: nil)
        await model.prepare(AudioTrack(url: url), using: { $0 })
        XCTAssertEqual(model.url, url)
        XCTAssertNil(model.error)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["original.opus"])
    }

    @MainActor func testUnavailableFileShowsErrorAndRetryClearsIt() async {
        let url = URL(fileURLWithPath: "/missing/track.m4a")
        let track = AudioTrack(url: url)
        let model = OriginalFileShareModel(access: nil)
        await model.prepare(track, using: { _ in throw CocoaError(.fileNoSuchFile) })
        XCTAssertNil(model.url)
        XCTAssertNotNil(model.error)
        await model.prepare(track, using: { $0 })
        XCTAssertEqual(model.url, url)
        XCTAssertNil(model.error)
    }

    @MainActor func testCancelledPreparationDoesNotOfferAFile() async {
        let model = OriginalFileShareModel(access: nil)
        await model.prepare(AudioTrack(url: URL(fileURLWithPath: "/track.m4a")), using: { _ in throw CancellationError() })
        XCTAssertNil(model.url)
        XCTAssertNil(model.error)
    }
}
