import Foundation

public struct LibrarySearchResults: Sendable {
    public struct Folder: Identifiable, Sendable {
        public let folder: AudioFolder
        public let path: String
        public var id: URL { folder.url }
    }
    public struct Track: Identifiable, Sendable {
        public let track: AudioTrack
        public let folderURL: URL
        public let path: String
        public var id: URL { track.url }
    }
    public var folders: [Folder] = []
    public var tracks: [Track] = []
}

public enum LibrarySearch {
    public static func search(_ query: String, in root: AudioFolder) -> LibrarySearchResults {
        func normalized(_ text: String) -> String {
            text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        }
        let words = normalized(query).split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return LibrarySearchResults() }
        func matches(_ name: String) -> Bool {
            let name = normalized(name)
            return words.allSatisfy { name.contains($0) }
        }
        var results = LibrarySearchResults()
        func visit(_ folder: AudioFolder, ancestors: [String]) {
            let components = ancestors + [folder.title]
            let path = components.joined(separator: " › ")
            if matches(folder.title) { results.folders.append(.init(folder: folder, path: path)) }
            for track in folder.tracks where matches(track.title) {
                results.tracks.append(.init(track: track, folderURL: folder.url, path: path))
            }
            for child in folder.children { visit(child, ancestors: components) }
        }
        visit(root, ancestors: [])
        return results
    }
}
