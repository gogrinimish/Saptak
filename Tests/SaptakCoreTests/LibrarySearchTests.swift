import XCTest
@testable import SaptakCore

final class LibrarySearchTests: XCTestCase {
    private func library() -> AudioFolder {
        let root = URL(fileURLWithPath: "/audio")
        let children = ["Practice", "Lessons"].map { name in
            AudioFolder(url: root.appendingPathComponent(name), children: [], tracks: [
                AudioTrack(url: root.appendingPathComponent("\(name)/Café Morning.m4a")),
                AudioTrack(url: root.appendingPathComponent("\(name)/Evening.opus"))
            ])
        }
        return AudioFolder(url: root, children: children, tracks: [AudioTrack(url: root.appendingPathComponent("Root track.wav"))])
    }

    func testBlankQueryDoesNotReturnEntireLibrary() {
        for query in ["", " \n\t "] {
            let result = LibrarySearch.search(query, in: library())
            XCTAssertTrue(result.tracks.isEmpty)
            XCTAssertTrue(result.folders.isEmpty)
        }
    }

    func testSearchIsCaseAndDiacriticInsensitiveAndRequiresAllWords() {
        let root = library()
        XCTAssertEqual(LibrarySearch.search(" MORNING cafe ", in: root).tracks.count, 2)
        XCTAssertTrue(LibrarySearch.search("cafe evening", in: root).tracks.isEmpty)
    }

    func testDuplicateTitlesHaveDistinctURLsAndFolderPaths() {
        let result = LibrarySearch.search("cafe", in: library())
        XCTAssertEqual(Set(result.tracks.map(\.id)).count, 2)
        XCTAssertEqual(result.tracks.map(\.path), ["audio › Practice", "audio › Lessons"])
        XCTAssertEqual(result.tracks.map { $0.folderURL.lastPathComponent }, ["Practice", "Lessons"])
    }

    func testFolderMatchDoesNotImplicitlyMatchEveryDescendantTrack() {
        let result = LibrarySearch.search("practice", in: library())
        XCTAssertEqual(result.folders.map { $0.folder.title }, ["Practice"])
        XCTAssertTrue(result.tracks.isEmpty)
    }

    func testRootFolderAndRootTracksAreSearchable() {
        XCTAssertEqual(LibrarySearch.search("audio", in: library()).folders.count, 1)
        XCTAssertEqual(LibrarySearch.search("root", in: library()).tracks.first?.path, "audio")
    }

    func testExtensionDoesNotMatchAsTitleAndResultsAreDeterministic() {
        XCTAssertTrue(LibrarySearch.search("opus", in: library()).tracks.isEmpty)
        let first = LibrarySearch.search("evening", in: library()).tracks.map(\.id)
        XCTAssertEqual(first, LibrarySearch.search("evening", in: library()).tracks.map(\.id))
    }

    func testNewLibrarySnapshotUpdatesResults() {
        let root = library()
        _ = LibrarySearch.search("cafe", in: root)
        let empty = AudioFolder(url: root.url, children: [], tracks: [])
        XCTAssertTrue(LibrarySearch.search("cafe", in: empty).tracks.isEmpty)
    }
}
