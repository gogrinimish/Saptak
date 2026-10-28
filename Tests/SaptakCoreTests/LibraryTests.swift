import XCTest
@testable import SaptakCore
final class LibraryTests: XCTestCase {
    func testNestedFoldersBecomeDynamicQueues() throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        let nested = root.appendingPathComponent("Family/Birthdays")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        FileManager.default.createFile(atPath: nested.appendingPathComponent("voice.m4a").path, contents: Data())
        FileManager.default.createFile(atPath: nested.appendingPathComponent("ignore.txt").path, contents: Data())
        let first = try LibraryScanner.scan(root)
        XCTAssertEqual(first.allTracks.map(\.title), ["voice"])
        XCTAssertEqual(first.children.first?.children.first?.allTracks.count, 1)
        FileManager.default.createFile(atPath: nested.appendingPathComponent("new.mp3").path, contents: Data())
        XCTAssertEqual(try LibraryScanner.scan(root).allTracks.count, 2)
    }
    func testParentFoldersIncludeNestedTracksWithoutDuplicates() throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for folder in ["Family/Birthdays", "Family/Stories", "Discourses"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        for file in ["Family/Birthdays/a.m4a", "Family/Birthdays/b.mp3", "Family/Stories/c.wav", "Discourses/d.aac"] {
            XCTAssertTrue(FileManager.default.createFile(atPath: root.appendingPathComponent(file).path, contents: Data()))
        }
        let library = try LibraryScanner.scan(root)
        XCTAssertEqual(library.allTracks.count, 4)
        XCTAssertEqual(Set(library.allTracks.map(\.url)).count, 4)
        let family = try XCTUnwrap(library.children.first { $0.title == "Family" })
        XCTAssertEqual(family.allTracks.count, 3)
        XCTAssertEqual(try XCTUnwrap(family.children.first { $0.title == "Birthdays" }).allTracks.count, 2)
    }

    func testIgnoresNonAudioFilesAndIndexesSupportedAudio() throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["voice.M4A", "note.txt", "unverified.ogg", "sample.mp3"] {
            XCTAssertTrue(FileManager.default.createFile(atPath: root.appendingPathComponent(name).path, contents: Data()))
        }
        XCTAssertEqual(try LibraryScanner.scan(root).allTracks.count, 2)
    }

    func testOpusAppearsInNestedPlaylistsAndRefreshWithoutChangingSources() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let nested = root.appendingPathComponent("Recordings", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bytes = Data([0, 1, 2, 255])
        for name in ["voice.opus", "second.OPUS", "unsupported.ogg"] {
            try bytes.write(to: nested.appendingPathComponent(name))
        }
        let first = try LibraryScanner.scan(root)
        XCTAssertEqual(Set(first.allTracks.map(\.title)), Set(["voice", "second"]))
        XCTAssertEqual(first.children.first?.tracks.count, 2)
        XCTAssertEqual(try Data(contentsOf: nested.appendingPathComponent("voice.opus")), bytes)
        try FileManager.default.removeItem(at: nested.appendingPathComponent("voice.opus"))
        XCTAssertEqual(try LibraryScanner.scan(root).allTracks.map(\.title), ["second"])
    }

    func testRefreshReflectsRemovalAndNeverChangesOriginalContents() throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("voice.m4a")
        let bytes = Data([0, 1, 2, 3, 255])
        try bytes.write(to: source)
        let before = try FileManager.default.attributesOfItem(atPath: source.path)
        for _ in 0..<3 { XCTAssertEqual(try LibraryScanner.scan(root).allTracks.count, 1) }
        XCTAssertEqual(try Data(contentsOf: source), bytes)
        let after = try FileManager.default.attributesOfItem(atPath: source.path)
        XCTAssertEqual(before[.modificationDate] as? Date, after[.modificationDate] as? Date)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["voice.m4a"])
        try FileManager.default.removeItem(at: source)
        XCTAssertTrue(try LibraryScanner.scan(root).allTracks.isEmpty)
    }

    func testSymlinksHiddenFilesAndCyclesAreIgnored() throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: root.appendingPathComponent("real.mp3"))
        try Data().write(to: root.appendingPathComponent(".hidden.mp3"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("cycle"), withDestinationURL: root)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("alias.mp3"), withDestinationURL: root.appendingPathComponent("real.mp3"))
        XCTAssertEqual(try LibraryScanner.scan(root).allTracks.map(\.title), ["real"])
    }

    func testMissingRootThrowsRatherThanPretendingLibraryIsEmpty() {
        XCTAssertThrowsError(try LibraryScanner.scan(URL(fileURLWithPath: "/tmp/\(UUID().uuidString)")))
    }

    func testNaturalOrderingAndEmptyFolderHierarchy() throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        for name in ["Empty", "Part.10", "Part.2"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["10.mp3", "2.mp3", "1.mp3"] { try Data().write(to: root.appendingPathComponent(name)) }
        let report = try LibraryScanner.scanReport(root)
        XCTAssertEqual(report.root.tracks.map(\.title), ["1", "2", "10"])
        XCTAssertEqual(report.root.children.map(\.title), ["Empty", "Part.2", "Part.10"])
        XCTAssertTrue(report.issues.isEmpty)
    }

    func testUnreadableDescendantPreservesAccessibleTracksAndReportsIssue() throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        let denied = root.appendingPathComponent("Denied")
        try FileManager.default.createDirectory(at: denied, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: root.appendingPathComponent("voice.mp3"))
        let report = try LibraryScanner.scanReport(root, fileManager: DeniedFolderFileManager())
        XCTAssertEqual(report.root.allTracks.map(\.title), ["voice"])
        XCTAssertEqual(report.root.children.map(\.title), ["Denied"])
        XCTAssertEqual(report.issues.map { $0.url.lastPathComponent }, ["Denied"])
        XCTAssertNotNil(report.root.folder(at: try XCTUnwrap(report.root.children.first).url))
        XCTAssertNil(report.root.folder(at: root.appendingPathComponent("Removed")))
    }

}

private final class DeniedFolderFileManager: FileManager, @unchecked Sendable {
    override func contentsOfDirectory(at url: URL, includingPropertiesForKeys keys: [URLResourceKey]?, options mask: FileManager.DirectoryEnumerationOptions = []) throws -> [URL] {
        if url.lastPathComponent == "Denied" { throw CocoaError(.fileReadNoPermission) }
        return try super.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: mask)
    }
}
