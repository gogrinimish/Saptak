import XCTest
import SaptakCore
@testable import SaptakPlatform

final class OriginalFileLocationTests: XCTestCase {
    func testFilesLinkPreservesOriginalUnicodeFilenameAndEscaping() throws {
        let root = URL(fileURLWithPath: "/Music/My Audio", isDirectory: true)
        let original = root.appendingPathComponent("Lessons/राग #1 50%?.opus")
        let location = try OriginalFileLocation(track: AudioTrack(url: original), root: root)
        XCTAssertEqual(location.fileURL, original)
        XCTAssertEqual(location.filename, "राग #1 50%?.opus")
        XCTAssertEqual(location.folderDescription, "My Audio › Lessons")
        let routed = try XCTUnwrap(location.filesURL)
        var components = try XCTUnwrap(URLComponents(url: routed, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "shareddocuments")
        XCTAssertNil(components.query)
        XCTAssertNil(components.fragment)
        components.scheme = "file"
        XCTAssertEqual(components.url, original)
    }

    func testSiblingFolderIsNotMistakenForSelectedRoot() throws {
        let root = URL(fileURLWithPath: "/Music/Lessons", isDirectory: true)
        let file = URL(fileURLWithPath: "/Music/Lessons Backup/Subfolder/voice.m4a")
        let location = try OriginalFileLocation(track: AudioTrack(url: file), root: root)
        XCTAssertEqual(location.folderDescription, "Subfolder")
        XCTAssertEqual(location.folderURL.path, "/Music/Lessons Backup/Subfolder")
    }

    func testNonDocumentAndRemoteFileURLsAreRejected() {
        for url in [URL(string: "https://example.com/audio.m4a")!,
                    URL(string: "file://remote.example/audio.m4a")!,
                    URL(string: "file:///Music/audio.m4a?export=copy")!] {
            XCTAssertThrowsError(try OriginalFileLocation(track: AudioTrack(url: url), root: nil))
        }
    }

    func testInspectionDoesNotReadAudioOrCreateCopies() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("recording.opus")
        let bytes = Data([1, 7, 9, 12])
        try bytes.write(to: file)
        let access = FolderAccess(url: root)
        let location = try await OriginalFileLocationAccess.prepare(track: AudioTrack(url: file), access: access) {
            try OriginalFileLocationAccess.inspect($0, coordinate: { url, accessor in accessor(url) })
        }
        XCTAssertEqual(location.fileURL, file)
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["recording.opus"])
    }

    func testMissingFileAndDirectoryFailExplicitly() throws {
        let missing = URL(fileURLWithPath: "/tmp/\(UUID().uuidString).m4a")
        let coordinate: ProviderAccess.CoordinateRead = { url, accessor in accessor(url) }
        XCTAssertThrowsError(try OriginalFileLocationAccess.inspect(missing, coordinate: coordinate))
        XCTAssertThrowsError(try OriginalFileLocationAccess.inspect(FileManager.default.temporaryDirectory, coordinate: coordinate))
    }

    func testProviderFailuresAndMissingCallbacksAreNotReportedAsSuccess() throws {
        let file = URL(fileURLWithPath: "/Music/voice.m4a")
        XCTAssertThrowsError(try OriginalFileLocationAccess.inspect(file, coordinate: { _, _ in
            throw CocoaError(.fileReadNoPermission)
        })) { XCTAssertEqual(($0 as? CocoaError)?.code, .fileReadNoPermission) }
        XCTAssertThrowsError(try OriginalFileLocationAccess.inspect(file, coordinate: { _, _ in }))
    }

    func testCancelledPreparationDoesNotReturnLocation() async {
        do {
            _ = try await OriginalFileLocationAccess.prepare(
                track: AudioTrack(url: URL(fileURLWithPath: "/Music/voice.m4a")), access: nil,
                inspect: { _ in throw CancellationError() })
            XCTFail("Cancelled requests must not launch another app")
        } catch { XCTAssertTrue(error is CancellationError) }
    }
}
