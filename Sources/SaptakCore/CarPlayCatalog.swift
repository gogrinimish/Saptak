import Foundation

/// Bounds vehicle lists without dropping the remaining folders or tracks.
public struct CarPlayPage<Element> {
    public let items: [Element]
    public let index: Int
    public let count: Int
    public var hasPrevious: Bool { index > 0 }
    public var hasNext: Bool { index + 1 < count }

    public init(_ elements: [Element], requested: Int, capacity: Int) {
        guard capacity > 0, !elements.isEmpty else {
            items = []; index = 0; count = 0
            return
        }
        count = (elements.count - 1) / capacity + 1
        index = min(max(0, requested), count - 1)
        let start = index * capacity
        items = Array(elements[start..<min(start + capacity, elements.count)])
    }
}

public enum CarPlayCatalogEntry: Sendable {
    case folder(AudioFolder)
    case track(AudioTrack)
}

/// Navigation reads the existing scanned hierarchy; it never accesses the filesystem.
public struct CarPlayCatalog {
    public private(set) var selectedURL: URL?
    public private(set) var page = 0

    public init() {}

    public mutating func folder(in root: AudioFolder) -> AudioFolder {
        let url = selectedURL.map { root.nearestSurvivingAncestor(of: $0) } ?? root.url
        if url != selectedURL { selectedURL = url; page = 0 }
        return root.folder(at: url) ?? root
    }

    public mutating func browse(_ url: URL, in root: AudioFolder) {
        guard let folder = root.folder(at: url) else { return }
        selectedURL = folder.url
        page = 0
    }

    public mutating func parent(in root: AudioFolder) {
        let current = folder(in: root)
        guard let trail = root.ancestry(to: current.url), trail.count > 1 else { return }
        browse(trail[trail.count - 2].url, in: root)
    }

    public mutating func showPage(_ index: Int) { page = max(0, index) }

    public static func entries(in folder: AudioFolder) -> [CarPlayCatalogEntry] {
        folder.children.map(CarPlayCatalogEntry.folder) + folder.tracks.map(CarPlayCatalogEntry.track)
    }

    /// Reject stale selections instead of playing a different track at an obsolete row index.
    public static func queueIndex(for selected: AudioTrack, in tracks: [AudioTrack]) -> Int? {
        tracks.firstIndex(of: selected)
    }
}
