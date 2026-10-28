import Foundation

public struct AudioTrack: Identifiable, Hashable, Sendable {
    public let url: URL
    public var id: URL { url }
    public var title: String { url.deletingPathExtension().lastPathComponent }
    public init(url: URL) { self.url = url }
}

public struct AudioFolder: Identifiable, Sendable {
    public let url: URL
    public let children: [AudioFolder]
    public let tracks: [AudioTrack]
    public var id: URL { url }
    public var title: String { url.lastPathComponent }
    public var allTracks: [AudioTrack] { tracks + children.flatMap(\.allTracks) }
    public func folder(at url: URL) -> AudioFolder? {
        if self.url.standardizedFileURL.path == url.standardizedFileURL.path { return self }
        for child in children {
            if let match = child.folder(at: url) { return match }
        }
        return nil
    }
    /// Root-to-current context for breadcrumbs; never infer parents from path strings.
    public func ancestry(to target: URL) -> [AudioFolder]? {
        if url.standardizedFileURL.path == target.standardizedFileURL.path { return [self] }
        for child in children {
            if let trail = child.ancestry(to: target) { return [self] + trail }
        }
        return nil
    }

    /// NavigationStack excludes its root. Drop obsolete/nonhierarchical suffixes after refresh.
    public func validNavigationPath(_ path: [URL]) -> [URL] {
        var current = self
        var result: [URL] = []
        for target in path {
            guard let child = current.children.first(where: {
                $0.url.standardizedFileURL.path == target.standardizedFileURL.path
            }) else { break }
            result.append(child.url)
            current = child
        }
        return result
    }

    public init(url: URL, children: [AudioFolder], tracks: [AudioTrack]) {
        self.url = url; self.children = children; self.tracks = tracks
    }
}

public struct ScanIssue: Sendable {
    public let url: URL
    public let message: String
}

public struct LibraryScan: Sendable {
    public let root: AudioFolder
    public let issues: [ScanIssue]
}

public enum LibraryScanner {
    // OPUS is a playback candidate: native support depends on container and OS version.
    public static let supportedExtensions: Set<String> = ["m4a", "mp3", "aac", "wav", "aif", "aiff", "caf", "flac", "opus"]

    public static func scan(_ root: URL, fileManager: FileManager = .default) throws -> AudioFolder {
        try scanReport(root, fileManager: fileManager).root
    }

    public static func scanReport(_ root: URL, fileManager: FileManager = .default) throws -> LibraryScan {
        var issues: [ScanIssue] = []
        let folder = try scanFolder(root, fileManager: fileManager, issues: &issues)
        return LibraryScan(root: folder, issues: issues)
    }

    private static func scanFolder(_ root: URL, fileManager: FileManager, issues: inout [ScanIssue]) throws -> AudioFolder {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
        let urls = try fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        var folders: [AudioFolder] = []
        var tracks: [AudioTrack] = []
        for url in urls {
            do {
                let values = try url.resourceValues(forKeys: Set(keys))
                if values.isSymbolicLink == true { continue }
                if values.isDirectory == true {
                    do {
                        folders.append(try scanFolder(url, fileManager: fileManager, issues: &issues))
                    } catch {
                        issues.append(ScanIssue(url: url, message: error.localizedDescription))
                        folders.append(AudioFolder(url: url, children: [], tracks: []))
                    }
                } else if values.isRegularFile == true && supportedExtensions.contains(url.pathExtension.lowercased()) {
                    tracks.append(AudioTrack(url: url))
                }
            } catch {
                issues.append(ScanIssue(url: url, message: error.localizedDescription))
            }
        }
        // A literal path tie-break makes ordering stable when localized titles compare equally.
        func ordered(_ lhs: String, _ rhs: String, lhsURL: URL, rhsURL: URL) -> Bool {
            let comparison = lhs.localizedStandardCompare(rhs)
            return comparison == .orderedSame ? lhsURL.path < rhsURL.path : comparison == .orderedAscending
        }
        return AudioFolder(
            url: root,
            children: folders.sorted { ordered($0.title, $1.title, lhsURL: $0.url, rhsURL: $1.url) },
            tracks: tracks.sorted { ordered($0.title, $1.title, lhsURL: $0.url, rhsURL: $1.url) }
        )
    }
}

extension AudioFolder {
    /// Navigation recovery uses only the scanned tree, without touching the filesystem.
    public func nearestSurvivingAncestor(of selected: URL) -> URL {
        var candidate = selected.standardizedFileURL
        while true {
            if let folder = folder(at: candidate) { return folder.url }
            let parent = candidate.deletingLastPathComponent()
            if parent == candidate { return url }
            candidate = parent
        }
    }
}
