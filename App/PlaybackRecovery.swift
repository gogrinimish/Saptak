import Foundation

struct PlaybackCheckpoint: Codable, Equatable {
    let urls: [URL]
    let current: URL
    let seconds: Double
}

@MainActor final class PlaybackRecoveryStore {
    private let defaults: UserDefaults
    private let key = "playbackCheckpoint.v1"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func read() -> PlaybackCheckpoint? {
        guard let data = defaults.data(forKey: key),
              let value = try? JSONDecoder().decode(PlaybackCheckpoint.self, from: data),
              value.seconds.isFinite, value.seconds >= 0,
              value.urls.count <= 10000, value.urls.contains(value.current) else { return nil }
        return value
    }

    func write(_ checkpoint: PlaybackCheckpoint) {
        guard checkpoint.seconds.isFinite, checkpoint.seconds >= 0,
              checkpoint.urls.count <= 10000,
              checkpoint.urls.contains(checkpoint.current),
              let data = try? JSONEncoder().encode(checkpoint) else { return }
        defaults.set(data, forKey: key)
    }
}

struct PlaybackInterruptionPolicy {
    private(set) var interrupted = false
    private var shouldResume = false

    mutating func begin(wasPlaying: Bool) {
        if !interrupted { shouldResume = wasPlaying }
        interrupted = true
    }

    mutating func cancelResume() { shouldResume = false }

    mutating func end(systemAllowsResume: Bool) -> Bool {
        let resume = interrupted && shouldResume && systemAllowsResume
        interrupted = false
        shouldResume = false
        return resume
    }
}
