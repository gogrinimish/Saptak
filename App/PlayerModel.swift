import AVFoundation
import SaptakCore

@MainActor final class PlayerModel: ObservableObject {
    @Published private(set) var queue = PlaybackQueue() { didSet { publishSystemPlayback() } }
    @Published private(set) var isPlaying = false { didSet { publishSystemPlayback() } }
    @Published private(set) var isLoading = false { didSet { publishSystemPlayback() } }
    @Published private(set) var position: Double = 0 { didSet { publishSystemPlayback() } }
    @Published private(set) var duration: Double = 0 { didSet { publishSystemPlayback() } }
    @Published private(set) var metadata = AudioMetadata() { didSet { publishSystemPlayback() } }
    private var metadataTask: Task<Void, Never>?
    @Published var error: String?
    private let player = AVPlayer()
    private var access: FolderAccess?
    private var loadTask: Task<Void, Never>?
    private var generation = UUID()
    private var endObserver: NSObjectProtocol?
    private var failureObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    private var playbackObservation: NSKeyValueObservation?
    private var timeObserver: Any?
    private var finished = false
    private let systemPlayback: SystemPlaybackOutput?
    private var lastSystemState: SystemPlaybackState?

    private let recovery: PlaybackRecoveryStore?
    private var restored = false
    private var pendingPosition: Double = 0
    private var lastCheckpoint = Date.distantPast
    private var interruption = PlaybackInterruptionPolicy()
    private var sessionObservers: [NSObjectProtocol] = []

    func checkpoint() {
        guard let current = queue.current, !isLoading else { return }
        recovery?.write(PlaybackCheckpoint(urls: queue.tracks.map(\.url), current: current.url,
                                           seconds: finished ? 0 : position))
        lastCheckpoint = Date()
    }

    func restoreIfNeeded(root: AudioFolder, access: FolderAccess?) {
        guard !restored, queue.current == nil, let saved = recovery?.read() else { return }
        restored = true
        let available = Dictionary(root.allTracks.map { ($0.url.standardizedFileURL.path, $0) }, uniquingKeysWith: { first, _ in first })
        guard let current = available[saved.current.standardizedFileURL.path] else { return }
        let tracks = saved.urls.compactMap { available[$0.standardizedFileURL.path] }
        self.access = access
        queue.replace(with: tracks)
        if let index = tracks.firstIndex(of: current) { queue.select(index) }
        pendingPosition = saved.seconds
        position = saved.seconds
        // Do not open/download the file or activate audio until the user presses Play.
    }

    func interruptionBegan() {
        interruption.begin(wasPlaying: isPlaying || isLoading)
        pauseForInterruption()
    }

    func interruptionEnded(shouldResume: Bool) {
        if interruption.end(systemAllowsResume: shouldResume) { resume() }
    }

    func outputDisconnected() { pause() }

    private func pauseForInterruption() {
        let policy = interruption
        pause()
        interruption = policy
    }

    var folderAccessForSharing: FolderAccess? { access }

    var title: String { metadata.title ?? queue.current?.title ?? "Nothing playing" }
    var subtitle: String {
        let tags = [metadata.artist, metadata.album].compactMap { $0 }
        return tags.isEmpty ? (queue.current?.url.deletingLastPathComponent().lastPathComponent ?? "") : tags.joined(separator: " · ")
    }

    func applyMetadata(_ value: AudioMetadata, for track: AudioTrack) {
        guard queue.current == track else { return }
        metadata = value
    }

    init(systemPlayback: SystemPlaybackOutput? = nil, recovery: PlaybackRecoveryStore? = nil) {
        self.recovery = recovery
        self.systemPlayback = systemPlayback
        systemPlayback?.bind { [weak self] command in self?.handleSystemCommand(command) ?? false }
        publishSystemPlayback()
        #if os(iOS)
        sessionObservers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(), queue: .main) { [weak self] notification in
            let type = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber)?.uintValue
            let options = (notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? NSNumber)?.uintValue ?? 0
            Task { @MainActor in
                if type == AVAudioSession.InterruptionType.began.rawValue { self?.interruptionBegan() }
                else if type == AVAudioSession.InterruptionType.ended.rawValue {
                    self?.interruptionEnded(shouldResume: AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume))
                }
            }
        })
        sessionObservers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: AVAudioSession.sharedInstance(), queue: .main) { [weak self] notification in
            let reason = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? NSNumber)?.uintValue
            if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
                Task { @MainActor in self?.outputDisconnected() }
            }
        })
        #endif
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self, self.player.currentItem != nil, !self.isLoading else { return }
                // Read the current item, not a queued timestamp from an old track.
                let seconds = self.player.currentTime().seconds
                self.position = seconds.isFinite ? max(0, seconds) : 0
                let length = self.player.currentItem?.duration.seconds ?? 0
                self.duration = length.isFinite ? max(0, length) : 0
                if Date().timeIntervalSince(self.lastCheckpoint) >= 5 { self.checkpoint() }
            }
        }
        playbackObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor in
                guard let self else { return }
                self.isPlaying = self.player.timeControlStatus != .paused && self.queue.current != nil
            }
        }
    }

    /// Row selection starts within the displayed playlist, preserving its context.
    func play(_ tracks: [AudioTrack], access: FolderAccess?, shuffled: Bool = false,
              startingAt track: AudioTrack? = nil) {
        if let track, !tracks.contains(track) { return }
        stop()
        self.access = access
        queue.replace(with: tracks, shuffled: shuffled)
        if let track, let index = queue.tracks.firstIndex(of: track) {
            queue.select(index)
        }
        if queue.current != nil { loadCurrent() }
    }

    func stop() {
        checkpoint()
        interruption.cancelResume()
        pendingPosition = 0
        generation = UUID()
        metadataTask?.cancel()
        metadata = AudioMetadata()
        loadTask?.cancel()
        player.pause()
        clearItemObservers()
        player.replaceCurrentItem(with: nil)
        access = nil
        isPlaying = false
        isLoading = false
        position = 0
        duration = 0
        error = nil
        finished = false
        queue.replace(with: [])
    }

    func toggle() {
        if isPlaying || isLoading { pause() }
        else { resume() }
    }

    func resume() {
        guard queue.current != nil, !isLoading else { return }
        guard !interruption.interrupted else { return }
        if finished || player.currentItem == nil { loadCurrent(resumeAt: pendingPosition) }
        else {
            #if os(iOS)
            do { try AVAudioSession.sharedInstance().setActive(true) }
            catch { fail(error.localizedDescription); return }
            #endif
            player.play()
        }
    }

    func pause() {
        interruption.cancelResume()
        checkpoint()
        if isLoading {
            generation = UUID()
            loadTask?.cancel()
            isLoading = false
            finished = true
        }
        player.pause()
        isPlaying = false
    }

    @discardableResult func handleSystemCommand(_ command: SystemPlaybackCommand) -> Bool {
        guard queue.current != nil else { return false }
        switch command {
        case .play:
            guard !isLoading else { return false }
            if !isPlaying { resume() }
        case .pause: pause()
        case .toggle: toggle()
        case .next:
            guard queue.index.map({ $0 + 1 < queue.tracks.count || queue.repeatMode == .all }) == true else { return false }
            next()
        case .previous: previous()
        case .stop: stop()
        case .seek(let seconds):
            guard seconds.isFinite, duration > 0, !isLoading else { return false }
            seek(to: seconds)
        }
        return true
    }

    private func publishSystemPlayback() {
        guard let systemPlayback else { return }
        let state = SystemPlaybackState(title: queue.current == nil ? nil : title, index: queue.index,
                                        count: queue.tracks.count, position: position, duration: duration,
                                        isPlaying: isPlaying, isLoading: isLoading,
                                        canGoNext: queue.index.map { $0 + 1 < queue.tracks.count || queue.repeatMode == .all } ?? false,
                                        artist: metadata.artist, album: metadata.album, artwork: metadata.artwork)
        guard state != lastSystemState else { return }
        lastSystemState = state
        systemPlayback.update(state)
    }

    func next() {
        checkpoint()
        interruption.cancelResume()
        if queue.advance() { loadCurrent() }
        else {
            generation = UUID()
            loadTask?.cancel()
            player.pause()
            isLoading = false
            isPlaying = false
            finished = true
        }
    }

    /// Shared natural-completion path, also exercised without native audio services.
    func playbackDidFinish() {
        position = 0
        checkpoint()
        if queue.advance(automatically: true) { loadCurrent() }
        else { player.pause(); isPlaying = false; finished = true }
    }

    func previous() {
        checkpoint()
        interruption.cancelResume()
        if position > 3 { seek(to: 0) }
        else if queue.previous() { loadCurrent() }
        else { seek(to: 0) }
    }

    func select(_ index: Int) {
        guard queue.tracks.indices.contains(index) else { return }
        checkpoint()
        interruption.cancelResume()
        queue.select(index)
        loadCurrent()
    }

    func toggleShuffle() { queue.toggleShuffle() }
    func cycleRepeat() { queue.repeatMode = queue.repeatMode.next }

    func seek(to seconds: Double) {
        guard seconds.isFinite, duration > 0 else { return }
        let target = min(max(0, seconds), duration)
        finished = false
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        position = target
        checkpoint()
    }

    private func loadCurrent(resumeAt seconds: Double = 0) {
        guard let track = queue.current else { return }
        loadTask?.cancel()
        metadataTask?.cancel()
        metadata = AudioMetadata()
        let token = UUID()
        generation = token
        player.pause()
        clearItemObservers()
        player.replaceCurrentItem(with: nil)
        error = nil
        isPlaying = false
        isLoading = true
        finished = false
        pendingPosition = seconds
        position = seconds
        duration = 0
        let retainedAccess = access
        loadTask = Task { [weak self] in
            defer { withExtendedLifetime(retainedAccess) {} }
            do {
                // Provider coordination can block; never run it on the UI actor.
                let preparation = Task.detached { [retainedAccess] in
                    defer { withExtendedLifetime(retainedAccess) {} }
                    return try await ProviderAccess.prepare(track.url)
                }
                let url = try await withTaskCancellationHandler {
                    try await preparation.value
                } onCancel: { preparation.cancel() }
                try Task.checkCancellation()
                let asset = AVURLAsset(url: url)
                guard try await asset.load(.isPlayable) else { throw FileAccessError.unplayable }
                guard let self, self.generation == token, !Task.isCancelled else { return }
                #if os(iOS)
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                try AVAudioSession.sharedInstance().setActive(true)
                #endif
                let item = AVPlayerItem(asset: asset)
                self.statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                    guard item.status == .failed else { return }
                    let detail = item.error?.localizedDescription ?? "Unsupported or unavailable audio."
                    Task { @MainActor in
                        guard self?.generation == token else { return }
                        self?.fail(detail)
                    }
                }
                self.endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                    Task { @MainActor in
                        guard let self, self.generation == token else { return }
                        self.playbackDidFinish()
                    }
                }
                self.failureObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] notification in
                    let detail = (notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?.localizedDescription ?? "Playback interrupted."
                    Task { @MainActor in
                        guard self?.generation == token else { return }
                        self?.fail(detail)
                    }
                }
                self.player.replaceCurrentItem(with: item)
                let length = try await asset.load(.duration).seconds
                guard self.generation == token, !Task.isCancelled else { return }
                self.duration = length.isFinite ? max(0, length) : 0
                let target = seconds < self.duration - 1 ? max(0, seconds) : 0
                if target > 0 {
                    await self.player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                }
                guard self.generation == token, !Task.isCancelled else { return }
                self.pendingPosition = 0
                self.position = target
                self.isLoading = false
                if !self.interruption.interrupted { self.player.play() }
                self.metadataTask = Task { [weak self, retainedAccess] in
                    defer { withExtendedLifetime(retainedAccess) {} }
                    let value = await AudioMetadata.load(from: asset)
                    guard !Task.isCancelled, let self, self.generation == token else { return }
                    self.applyMetadata(value, for: track)
                }
            } catch is CancellationError {
                // A newer selection owns UI state.
            } catch {
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.fail(error.localizedDescription)
            }
        }
    }

    private func fail(_ detail: String) {
        player.pause()
        isPlaying = false
        isLoading = false
        finished = true
        error = "Could not play \(title). \(detail) You can retry, choose Next, or refresh the folder."
    }

    private func clearItemObservers() {
        statusObservation = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
        endObserver = nil
        failureObserver = nil
    }

    deinit {
        metadataTask?.cancel()
        loadTask?.cancel()
        for observer in sessionObservers { NotificationCenter.default.removeObserver(observer) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
        if let timeObserver { player.removeTimeObserver(timeObserver) }
    }
}
