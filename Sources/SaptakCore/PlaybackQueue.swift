import Foundation

public enum RepeatMode: String, CaseIterable, Sendable {
    case off, all, one

    public var next: RepeatMode {
        switch self {
        case .off: return .all
        case .all: return .one
        case .one: return .off
        }
    }
}

/// Playback order and transitions, independent of AVFoundation and UI state.
public struct PlaybackQueue: Sendable {
    public private(set) var tracks: [AudioTrack] = []
    public private(set) var index: Int?
    public private(set) var isShuffled = false
    public var repeatMode: RepeatMode = .off
    private var original: [AudioTrack] = []

    public init() {}
    public var current: AudioTrack? { index.map { tracks[$0] } }

    public mutating func replace(with tracks: [AudioTrack], shuffled: Bool = false) {
        original = tracks
        self.tracks = shuffled ? tracks.shuffled() : tracks
        isShuffled = shuffled
        index = tracks.isEmpty ? nil : 0
    }

    public mutating func select(_ index: Int) {
        guard tracks.indices.contains(index) else { return }
        self.index = index
    }

    /// Natural completion honors repeat-one; an explicit Next always moves forward.
    @discardableResult public mutating func advance(automatically: Bool = false) -> Bool {
        guard let index else { return false }
        if automatically && repeatMode == .one { return true }
        if index + 1 < tracks.count { self.index = index + 1; return true }
        if repeatMode == .all { self.index = 0; return true }
        return false
    }

    @discardableResult public mutating func previous() -> Bool {
        guard let index else { return false }
        if index > 0 { self.index = index - 1; return true }
        if repeatMode == .all && !tracks.isEmpty { self.index = tracks.count - 1; return true }
        return false
    }

    public mutating func toggleShuffle() {
        let selected = current
        isShuffled.toggle()
        if isShuffled {
            tracks = original.shuffled()
            if let selected, let position = tracks.firstIndex(of: selected) {
                tracks.swapAt(0, position)
            }
        } else {
            tracks = original
        }
        index = selected.flatMap { tracks.firstIndex(of: $0) }
    }
}
