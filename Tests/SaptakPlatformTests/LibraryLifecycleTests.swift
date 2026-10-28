import XCTest
import SaptakCore
@testable import SaptakPlatform

final class LibraryLifecycleTests: XCTestCase {
    private let bookmarkKey = "selectedFolderBookmark"

    @MainActor private func eventually(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for library state", file: file, line: line)
    }

    @MainActor func testAutomaticRefreshIsThrottledButManualRefreshIsImmediate() async throws {
        let fixture = try LibraryFixture()
        defer { fixture.cleanUp() }
        let scanner = ControlledLibraryScanner()
        var date = Date(timeIntervalSince1970: 1000)
        let model = LibraryModel(defaults: fixture.defaults, scan: { try scanner.scan($0) },
                                 createBookmark: { Data($0.absoluteString.utf8) }, now: { date })
        model.select(fixture.folder)
        try await eventually { !model.isRefreshing }
        XCTAssertEqual(scanner.calls, 1)
        XCTAssertEqual(model.lastRefreshed, date)
        date.addTimeInterval(29)
        model.refreshIfNeeded()
        XCTAssertFalse(model.isRefreshing)
        XCTAssertEqual(scanner.calls, 1)
        date.addTimeInterval(1)
        model.refreshIfNeeded()
        try await eventually { !model.isRefreshing }
        XCTAssertEqual(scanner.calls, 2)
        model.refresh()
        try await eventually { !model.isRefreshing }
        XCTAssertEqual(scanner.calls, 3)
    }

    @MainActor func testAutomaticRefreshFailureKeepsSnapshotAndCanRetryManually() async throws {
        let fixture = try LibraryFixture()
        defer { fixture.cleanUp() }
        let scanner = ControlledLibraryScanner()
        var date = Date(timeIntervalSince1970: 1000)
        let file = fixture.folder.appendingPathComponent("kept.m4a")
        try Data([1]).write(to: file)
        let model = LibraryModel(defaults: fixture.defaults, scan: { try scanner.scan($0) },
                                 createBookmark: { Data($0.absoluteString.utf8) }, now: { date })
        model.select(fixture.folder)
        try await eventually { !model.isRefreshing }
        let lastSuccess = model.lastRefreshed
        scanner.fail = true
        date.addTimeInterval(31)
        model.refreshIfNeeded()
        try await eventually { !model.isRefreshing }
        XCTAssertNotNil(model.error)
        XCTAssertEqual(model.root?.allTracks.map(\.title), ["kept"])
        XCTAssertEqual(model.lastRefreshed, lastSuccess)
        model.refreshIfNeeded()
        XCTAssertFalse(model.isRefreshing)
        scanner.fail = false
        model.refresh()
        try await eventually { !model.isRefreshing }
        XCTAssertNil(model.error)
    }

    @MainActor func testAutomaticRefreshDoesNotOverlapPendingScan() async throws {
        let fixture = try LibraryFixture()
        defer { fixture.cleanUp() }
        let gate = PausedFirstScan()
        var date = Date(timeIntervalSince1970: 1000)
        let model = LibraryModel(defaults: fixture.defaults, scan: { try gate.scan($0) },
                                 createBookmark: { Data($0.absoluteString.utf8) }, now: { date })
        model.select(fixture.folder)
        try await eventually { gate.started }
        date.addTimeInterval(60)
        model.refreshIfNeeded()
        XCTAssertTrue(model.isRefreshing)
        gate.release.signal()
        try await eventually { !model.isRefreshing }
        XCTAssertNil(model.error)
    }

    @MainActor func testFreshLibraryDoesNotInventSelection() throws {
        let fixture = try LibraryFixture()
        defer { fixture.cleanUp() }
        let scanner = ControlledLibraryScanner()
        let model = fixture.model(scanner: scanner)
        XCTAssertNil(model.root)
        XCTAssertNil(model.access)
        XCTAssertFalse(model.isRefreshing)
        XCTAssertNil(model.error)
        XCTAssertEqual(scanner.calls, 0)
    }

    @MainActor func testSelectionPersistsAndScansWithoutChangingOriginals() async throws {
        let fixture = try LibraryFixture()
        defer { fixture.cleanUp() }
        let file = fixture.folder.appendingPathComponent("voice.m4a")
        let bytes = Data([1, 2, 3])
        try bytes.write(to: file)
        let model = fixture.model()
        model.select(fixture.folder)
        try await eventually { !model.isRefreshing }
        XCTAssertEqual(model.root?.allTracks.map(\.title), ["voice"])
        XCTAssertEqual(fixture.defaults.data(forKey: bookmarkKey), fixture.bookmark)
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.folder.path), ["voice.m4a"])
    }

    @MainActor func testSavedSelectionRestoresWithoutChoosingAgain() async throws {
        let fixture = try LibraryFixture()
        defer { fixture.cleanUp() }
        fixture.defaults.set(fixture.bookmark, forKey: bookmarkKey)
        let model = fixture.model()
        try await eventually { !model.isRefreshing }
        XCTAssertEqual(model.access?.url, fixture.folder)
        XCTAssertEqual(model.root?.url, fixture.folder)
        XCTAssertNil(model.error)
    }

    @MainActor func testStaleBookmarkIsRenewedBeforeScanning() async throws {
        let fixture = try LibraryFixture()
        defer { fixture.cleanUp() }
        let old = Data([9, 9])
        fixture.defaults.set(old, forKey: bookmarkKey)
        let model = LibraryModel(defaults: fixture.defaults,
                                 scan: { try LibraryScanner.scanReport($0.url) },
                                 createBookmark: { _ in fixture.bookmark },
                                 resolveBookmark: { data in
            XCTAssertEqual(data, old)
            return ResolvedFolderBookmark(url: fixture.folder, isStale: true)
        })
        try await eventually { !model.isRefreshing }
        XCTAssertEqual(fixture.defaults.data(forKey: bookmarkKey), fixture.bookmark)
        XCTAssertEqual(model.root?.url, fixture.folder)
    }

    @MainActor func testExpiredBookmarkRemainsSavedForRecovery() throws {
        let fixture = try LibraryFixture()
        defer { fixture.cleanUp() }
        fixture.defaults.set(fixture.bookmark, forKey: bookmarkKey)
        let model = LibraryModel(defaults: fixture.defaults, resolveBookmark: { _ in
            throw CocoaError(.fileReadNoPermission)
        })
        XCTAssertNil(model.access)
        XCTAssertNotNil(model.error)
        XCTAssertFalse(model.isRefreshing)
        XCTAssertEqual(fixture.defaults.data(forKey: bookmarkKey), fixture.bookmark)
    }

    @MainActor func testBookmarkRenewalFailureDoesNotDiscardSavedSelection() async throws {
        let fixture = try LibraryFixture()
        defer { fixture.cleanUp() }
        fixture.defaults.set(fixture.bookmark, forKey: bookmarkKey)
        let model = LibraryModel(defaults: fixture.defaults,
                                 scan: { try LibraryScanner.scanReport($0.url) },
                                 createBookmark: { _ in throw CocoaError(.fileWriteNoPermission) },
                                 resolveBookmark: { _ in ResolvedFolderBookmark(url: fixture.folder, isStale: true) })
        try await eventually { !model.isRefreshing }
        XCTAssertEqual(model.root?.url, fixture.folder)
        XCTAssertEqual(fixture.defaults.data(forKey: bookmarkKey), fixture.bookmark)
        XCTAssertTrue(model.error?.contains("Could not save folder permission") == true)
        model.refresh()
        try await eventually { !model.isRefreshing }
        XCTAssertTrue(model.error?.contains("Could not save folder permission") == true)
    }

    @MainActor func testTransientRefreshFailurePreservesTreeAndBookmarkThenRecovers() async throws {
        let fixture = try LibraryFixture()
        defer { fixture.cleanUp() }
        let scanner = ControlledLibraryScanner()
        let model = fixture.model(scanner: scanner)
        model.select(fixture.folder)
        try await eventually { !model.isRefreshing }
        scanner.fail = true
        model.refresh()
        try await eventually { !model.isRefreshing }
        XCTAssertEqual(model.root?.url, fixture.folder)
        XCTAssertEqual(model.access?.url, fixture.folder)
        XCTAssertEqual(fixture.defaults.data(forKey: bookmarkKey), fixture.bookmark)
        XCTAssertNotNil(model.error)
        scanner.fail = false
        model.refresh()
        try await eventually { !model.isRefreshing }
        XCTAssertNil(model.error)
        XCTAssertEqual(model.root?.url, fixture.folder)
    }

    @MainActor func testFailedInitialScanCanRetryWithoutNewSelection() async throws {
        let fixture = try LibraryFixture()
        defer { fixture.cleanUp() }
        let scanner = ControlledLibraryScanner()
        scanner.fail = true
        let model = fixture.model(scanner: scanner)
        model.select(fixture.folder)
        try await eventually { !model.isRefreshing }
        XCTAssertNil(model.root)
        XCTAssertNotNil(model.error)
        XCTAssertEqual(model.access?.url, fixture.folder)
        scanner.fail = false
        model.refresh()
        try await eventually { !model.isRefreshing }
        XCTAssertEqual(model.root?.url, fixture.folder)
        XCTAssertNil(model.error)
    }

    @MainActor func testRefreshReflectsNestedAdditionsAndRemovals() async throws {
        let fixture = try LibraryFixture()
        defer { fixture.cleanUp() }
        let child = fixture.folder.appendingPathComponent("Lessons", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        let file = child.appendingPathComponent("lesson.opus")
        let model = fixture.model()
        model.select(fixture.folder)
        try await eventually { !model.isRefreshing }
        try Data([1]).write(to: file)
        model.refresh()
        try await eventually { !model.isRefreshing }
        XCTAssertEqual(model.root?.children.first?.tracks.map(\.title), ["lesson"])
        try FileManager.default.removeItem(at: file)
        model.refresh()
        try await eventually { !model.isRefreshing }
        XCTAssertEqual(model.root?.allTracks.count, 0)
        XCTAssertEqual(model.root?.children.first?.title, "Lessons")
    }

    @MainActor func testObsoleteSelectionCannotOverwriteNewFolderOrBookmark() async throws {
        let fixture = try LibraryFixture()
        defer { fixture.cleanUp() }
        let gate = PausedFirstScan()
        defer { gate.release.signal() }
        let model = LibraryModel(defaults: fixture.defaults, scan: { try gate.scan($0) },
                                 createBookmark: { Data($0.absoluteString.utf8) })
        model.select(fixture.folder)
        try await eventually { gate.started }
        let second = fixture.folder.appendingPathComponent("Second", isDirectory: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        model.select(second)
        try await eventually { !model.isRefreshing }
        gate.release.signal()
        try await eventually { gate.completed }
        // Allow the obsolete main-actor continuation to attempt publishing.
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(model.root?.url, second)
        XCTAssertEqual(model.access?.url, second)
        XCTAssertEqual(fixture.defaults.data(forKey: bookmarkKey), Data(second.absoluteString.utf8))
    }

    @MainActor func testOlderRefreshCannotRestoreRemovedTracks() async throws {
        let fixture = try LibraryFixture()
        defer { fixture.cleanUp() }
        let file = fixture.folder.appendingPathComponent("removed.m4a")
        try Data([1]).write(to: file)
        let gate = PausedFirstScan()
        defer { gate.release.signal() }
        let model = LibraryModel(defaults: fixture.defaults, scan: { try gate.scan($0) },
                                 createBookmark: { _ in fixture.bookmark })
        model.select(fixture.folder)
        try await eventually { gate.started }
        try FileManager.default.removeItem(at: file)
        model.refresh()
        try await eventually { !model.isRefreshing }
        gate.release.signal()
        try await eventually { gate.completed }
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(model.root?.allTracks.count, 0)
        XCTAssertNil(model.error)
    }
}

private final class LibraryFixture {
    let folder: URL
    let defaults: UserDefaults
    let suite: String
    var bookmark: Data { Data(folder.absoluteString.utf8) }

    init() throws {
        suite = "SaptakTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        folder = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    @MainActor func model(scanner: ControlledLibraryScanner = ControlledLibraryScanner()) -> LibraryModel {
        LibraryModel(defaults: defaults, scan: { try scanner.scan($0) },
                     createBookmark: { Data($0.absoluteString.utf8) },
                     resolveBookmark: { data in
            guard let string = String(data: data, encoding: .utf8), let url = URL(string: string) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return ResolvedFolderBookmark(url: url, isStale: false)
        })
    }

    func cleanUp() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: folder)
    }
}

private final class ControlledLibraryScanner: @unchecked Sendable {
    private let lock = NSLock()
    private var shouldFail = false
    private var count = 0
    var fail: Bool {
        get { lock.lock(); defer { lock.unlock() }; return shouldFail }
        set { lock.lock(); defer { lock.unlock() }; shouldFail = newValue }
    }
    var calls: Int { lock.lock(); defer { lock.unlock() }; return count }
    func scan(_ access: FolderAccess) throws -> LibraryScan {
        lock.lock()
        count += 1
        let fail = shouldFail
        lock.unlock()
        if fail { throw CocoaError(.fileReadNoPermission) }
        return try LibraryScanner.scanReport(access.url)
    }
}

private final class PausedFirstScan: @unchecked Sendable {
    let release = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var calls = 0
    private var didStart = false
    private var didComplete = false
    var started: Bool { lock.lock(); defer { lock.unlock() }; return didStart }
    var completed: Bool { lock.lock(); defer { lock.unlock() }; return didComplete }

    func scan(_ access: FolderAccess) throws -> LibraryScan {
        lock.lock()
        calls += 1
        let first = calls == 1
        lock.unlock()
        let result = try LibraryScanner.scanReport(access.url)
        if first {
            lock.lock(); didStart = true; lock.unlock()
            guard release.wait(timeout: .now() + 5) == .success else { throw CocoaError(.userCancelled) }
            lock.lock(); didComplete = true; lock.unlock()
        }
        return result
    }
}
