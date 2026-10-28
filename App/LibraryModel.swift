import Foundation
import SaptakCore

/// Shared ownership keeps folder permission alive while scans or playback still use it.
final class FolderAccess: @unchecked Sendable {
    let url: URL
    private let scoped: Bool

    init(url: URL) {
        self.url = url
        scoped = url.startAccessingSecurityScopedResource()
    }

    deinit {
        if scoped { url.stopAccessingSecurityScopedResource() }
    }
}

enum FileAccessError: LocalizedError {
    case unavailable(String)
    case downloadTimeout
    case unplayable

    var errorDescription: String? {
        switch self {
        case .unavailable(let detail): return "Cannot access this track. Select its folder again or make it available in Files. \(detail)"
        case .downloadTimeout: return "The track is still downloading from iCloud. Check your connection and try again."
        case .unplayable: return "This track cannot be played. It may be damaged or use an unsupported audio format."
        }
    }
}

enum ProviderAccess {
    typealias CoordinateRead = (URL, (URL) -> Void) throws -> Void

    static func coordinateRead(_ url: URL, accessor: (URL) -> Void) throws {
        var error: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [.withoutChanges], error: &error, byAccessor: accessor)
        if let error { throw error }
    }

    static func scan(_ access: FolderAccess, coordinate: CoordinateRead = coordinateRead) throws -> LibraryScan {
        var result: Result<LibraryScan, Error>?
        try coordinate(access.url) { url in
            result = Result { try LibraryScanner.scanReport(url) }
        }
        guard let result else { throw FileAccessError.unavailable("Folder provider did not respond.") }
        return try result.get()
    }

    static func prepare(_ url: URL, coordinate: CoordinateRead = coordinateRead) async throws -> URL {
        let manager = FileManager.default
        let values = try url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
        if values.isUbiquitousItem == true && values.ubiquitousItemDownloadingStatus != .current {
            try manager.startDownloadingUbiquitousItem(at: url)
            var ready = false
            for _ in 0..<120 {
                try Task.checkCancellation()
                let state = try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
                if state.ubiquitousItemDownloadingStatus == .current || state.ubiquitousItemDownloadingStatus == .downloaded {
                    ready = true
                    break
                }
                try await Task.sleep(nanoseconds: 500_000_000)
            }
            if !ready { throw FileAccessError.downloadTimeout }
        }
        try Task.checkCancellation()
        var result: Result<URL, Error>?
        try coordinate(url) { coordinatedURL in
            result = Result {
                // Open read-only to verify availability without importing or altering audio.
                let handle = try FileHandle(forReadingFrom: coordinatedURL)
                try handle.close()
                return coordinatedURL
            }
        }
        guard let result else { throw FileAccessError.unavailable("File provider did not respond.") }
        return try result.get()
    }
}

struct ResolvedFolderBookmark {
    let url: URL
    let isStale: Bool
}

enum FolderBookmarks {
    static func create(_ url: URL) throws -> Data {
        #if os(iOS)
        let options: URL.BookmarkCreationOptions = [.minimalBookmark]
        #else
        let options: URL.BookmarkCreationOptions = [.withSecurityScope, .securityScopeAllowOnlyReadAccess]
        #endif
        return try url.bookmarkData(options: options, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    static func resolve(_ data: Data) throws -> ResolvedFolderBookmark {
        var stale = false
        #if os(iOS)
        let options: URL.BookmarkResolutionOptions = [.withoutUI]
        #else
        let options: URL.BookmarkResolutionOptions = [.withSecurityScope, .withoutUI]
        #endif
        let url = try URL(resolvingBookmarkData: data, options: options, relativeTo: nil, bookmarkDataIsStale: &stale)
        return ResolvedFolderBookmark(url: url, isStale: stale)
    }
}

@MainActor final class LibraryModel: ObservableObject {
    @Published var root: AudioFolder?
    @Published var error: String?
    @Published var warnings: [String] = []
    @Published var isRefreshing = false
    private(set) var access: FolderAccess?
    private var scanTask: Task<Void, Never>?
    private var generation = UUID()
    private let bookmarkKey = "selectedFolderBookmark"
    private let defaults: UserDefaults
    private let scan: @Sendable (FolderAccess) throws -> LibraryScan
    private let createBookmark: (URL) throws -> Data
    private let resolveBookmark: (Data) throws -> ResolvedFolderBookmark
    private var permissionError: String?
    private var lastRefreshAttempt: Date?
    @Published private(set) var lastRefreshed: Date?
    private let now: () -> Date

    init(defaults: UserDefaults = .standard,
         scan: @escaping @Sendable (FolderAccess) throws -> LibraryScan = { try ProviderAccess.scan($0) },
         createBookmark: @escaping (URL) throws -> Data = FolderBookmarks.create,
         resolveBookmark: @escaping (Data) throws -> ResolvedFolderBookmark = FolderBookmarks.resolve,
         now: @escaping () -> Date = Date.init) {
        self.now = now
        self.defaults = defaults
        self.scan = scan
        self.createBookmark = createBookmark
        self.resolveBookmark = resolveBookmark
        restore()
    }

    func select(_ url: URL) {
        scanTask?.cancel()
        access = FolderAccess(url: url)
        root = nil
        warnings = []
        error = nil
        permissionError = nil
        saveBookmark(url)
        refresh()
    }

    private func saveBookmark(_ url: URL) {
        do {
            let bookmark = try createBookmark(url)
            defaults.set(bookmark, forKey: bookmarkKey)
            permissionError = nil
        } catch {
            permissionError = "Could not save folder permission: \(error.localizedDescription)"
            self.error = permissionError
        }
    }

    func refreshIfNeeded() {
        guard !isRefreshing else { return }
        if let lastRefreshAttempt, now().timeIntervalSince(lastRefreshAttempt) < 30 { return }
        refresh()
    }

    func refresh() {
        guard let access else { return }
        lastRefreshAttempt = now()
        scanTask?.cancel()
        let token = UUID()
        generation = token
        error = permissionError
        isRefreshing = true
        let scan = scan
        scanTask = Task { [weak self] in
            let result = await Task.detached { Result { try scan(access) } }.value
            guard !Task.isCancelled, let self, self.generation == token else { return }
            self.isRefreshing = false
            switch result {
            case .success(let report):
                self.lastRefreshed = self.now()
                self.root = report.root
                self.warnings = report.issues.map { "\($0.url.lastPathComponent): \($0.message)" }
            case .failure(let failure):
                self.error = "Cannot refresh folder: \(failure.localizedDescription). Retry or choose the folder again."
            }
        }
    }

    private func restore() {
        guard let data = defaults.data(forKey: bookmarkKey) else { return }
        do {
            let resolved = try resolveBookmark(data)
            access = FolderAccess(url: resolved.url)
            if resolved.isStale { saveBookmark(resolved.url) }
            refresh()
        } catch {
            self.error = "Saved folder access is unavailable. Select the folder again. \(error.localizedDescription)"
        }
    }

    deinit { scanTask?.cancel() }
}
