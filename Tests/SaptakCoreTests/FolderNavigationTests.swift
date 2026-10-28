import XCTest
@testable import SaptakCore

final class FolderNavigationTests: XCTestCase {
    private let rootURL = URL(fileURLWithPath: "/library", isDirectory: true)

    private func tree() -> AudioFolder {
        let lesson = AudioFolder(url: rootURL.appendingPathComponent("Practice/Lessons"), children: [], tracks: [])
        let practice = AudioFolder(url: rootURL.appendingPathComponent("Practice"), children: [lesson], tracks: [])
        let other = AudioFolder(url: rootURL.appendingPathComponent("Other"), children: [], tracks: [])
        return AudioFolder(url: rootURL, children: [practice, other], tracks: [])
    }

    func testDeletedSelectionFallsBackToNearestSurvivingAncestor() {
        let root = tree()
        XCTAssertEqual(root.nearestSurvivingAncestor(of: rootURL.appendingPathComponent("Practice/Lessons/Deleted")),
                       rootURL.appendingPathComponent("Practice/Lessons"))
        XCTAssertEqual(root.nearestSurvivingAncestor(of: rootURL.appendingPathComponent("Practice/Deleted/Child")),
                       rootURL.appendingPathComponent("Practice"))
    }

    func testSurvivingSelectionAndUnknownPathsRecoverWithinRoot() {
        let root = tree()
        XCTAssertEqual(root.nearestSurvivingAncestor(of: rootURL.appendingPathComponent("Other")), rootURL.appendingPathComponent("Other"))
        XCTAssertEqual(root.nearestSurvivingAncestor(of: URL(fileURLWithPath: "/unrelated/missing")), rootURL)
    }

    func testAncestryIncludesRootAndCurrentFolderExactlyOnce() throws {
        let root = tree()
        let target = rootURL.appendingPathComponent("Practice/Lessons")
        XCTAssertEqual(try XCTUnwrap(root.ancestry(to: target)).map(\.title), ["library", "Practice", "Lessons"])
    }

    func testRootAncestryDoesNotInventParentFolders() {
        XCTAssertEqual(tree().ancestry(to: rootURL)?.map(\.url), [rootURL])
    }

    func testUnknownFolderHasNoBreadcrumbTrail() {
        XCTAssertNil(tree().ancestry(to: rootURL.appendingPathComponent("Missing")))
    }

    func testNormalizedTargetResolvesToExistingFolder() {
        let target = URL(fileURLWithPath: "/library/Practice/./Lessons/")
        XCTAssertEqual(tree().ancestry(to: target)?.last?.title, "Lessons")
    }

    func testDuplicateTitlesDoNotNavigateToWrongBranch() throws {
        let first = AudioFolder(url: rootURL.appendingPathComponent("First/Lessons"), children: [], tracks: [])
        let second = AudioFolder(url: rootURL.appendingPathComponent("Second/Lessons"), children: [], tracks: [])
        let root = AudioFolder(url: rootURL, children: [
            AudioFolder(url: rootURL.appendingPathComponent("First"), children: [first], tracks: []),
            AudioFolder(url: rootURL.appendingPathComponent("Second"), children: [second], tracks: [])
        ], tracks: [])
        XCTAssertEqual(try XCTUnwrap(root.ancestry(to: second.url)).map(\.title), ["library", "Second", "Lessons"])
    }

    func testRefreshPreservesValidNavigationPath() {
        let path = [rootURL.appendingPathComponent("Practice"), rootURL.appendingPathComponent("Practice/Lessons")]
        XCTAssertEqual(tree().validNavigationPath(path), path)
        XCTAssertTrue(tree().validNavigationPath([]).isEmpty)
    }

    func testRemovedNestedFolderReturnsToNearestExistingParent() {
        let path = [rootURL.appendingPathComponent("Practice"), rootURL.appendingPathComponent("Practice/Removed")]
        XCTAssertEqual(tree().validNavigationPath(path), [path[0]])
    }

    func testRemovedAncestorReturnsToLibraryRoot() {
        let path = [rootURL.appendingPathComponent("Removed"), rootURL.appendingPathComponent("Removed/Lessons")]
        XCTAssertEqual(tree().validNavigationPath(path), [])
    }

    func testNavigationRejectsAPathThatJumpsBetweenSiblingFolders() {
        let path = [rootURL.appendingPathComponent("Practice"), rootURL.appendingPathComponent("Other")]
        XCTAssertEqual(tree().validNavigationPath(path), [path[0]])
    }
}
