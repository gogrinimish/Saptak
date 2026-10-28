import Foundation
import MediaPlayer
import SaptakCore
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum SystemPlaybackCommand: Equatable {
    case play, pause, toggle, next, previous, stop
    case seek(Double)
}

/// Only presentation data is donated to the OS, never file URLs or folder paths.
struct SystemPlaybackState: Equatable {
    var title: String?
    var index: Int?
    var count: Int
    var position: Double
    var duration: Double
    var isPlaying: Bool
    var isLoading: Bool
    var canGoNext: Bool

    var artist: String? = nil
    var album: String? = nil
    var artwork: Data? = nil

    var canPlay: Bool { title != nil && !isLoading }
    var canSeek: Bool { canPlay && duration.isFinite && duration > 0 }

    var metadata: [String: Any]? {
        guard let title else { return nil }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position.isFinite ? max(0, position) : 0.0,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying && !isLoading ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyPlaybackQueueCount: count,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyIsLiveStream: false
        ]
        if let artist { info[MPMediaItemPropertyArtist] = artist }
        if let album { info[MPMediaItemPropertyAlbumTitle] = album }
        if let index { info[MPNowPlayingInfoPropertyPlaybackQueueIndex] = index }
        if duration.isFinite && duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        if #available(macOS 15, iOS 18, *) {
            info[MPNowPlayingInfoPropertyExcludeFromSuggestions] = true
        }
        return info
    }
}

@MainActor protocol SystemPlaybackOutput: AnyObject {
    func bind(_ handler: @escaping @MainActor (SystemPlaybackCommand) -> Bool)
    func update(_ state: SystemPlaybackState)
}

/// Created by SaptakApp only; ordinary PlayerModel tests never touch system ownership.
@MainActor final class NativeSystemPlaybackOutput: SystemPlaybackOutput {
    private let center = MPNowPlayingInfoCenter.default()
    private let commands = MPRemoteCommandCenter.shared()
    private var registrations: [(MPRemoteCommand, Any)] = []
    private var handler: (@MainActor (SystemPlaybackCommand) -> Bool)?
    private var artwork: MPMediaItemArtwork?
    private var lastArtworkData: Data?
    private var trackArtwork: MPMediaItemArtwork?

    init() {
        #if os(macOS)
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url), image.isValid {
            artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        #endif
    }

    func bind(_ handler: @escaping @MainActor (SystemPlaybackCommand) -> Bool) {
        self.handler = handler
        guard registrations.isEmpty else { return }
        register(commands.playCommand) { _ in .play }
        register(commands.pauseCommand) { _ in .pause }
        register(commands.togglePlayPauseCommand) { _ in .toggle }
        register(commands.nextTrackCommand) { _ in .next }
        register(commands.previousTrackCommand) { _ in .previous }
        register(commands.stopCommand) { _ in .stop }
        register(commands.changePlaybackPositionCommand) { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent,
                  event.positionTime.isFinite else { return nil }
            return .seek(event.positionTime)
        }
    }

    private func register(_ command: MPRemoteCommand,
                          action: @escaping (MPRemoteCommandEvent) -> SystemPlaybackCommand?) {
        let token = command.addTarget { [weak self] event in
            guard let action = action(event) else { return .commandFailed }
            // MediaPlayer may deliver outside the UI actor. Accept and dispatch;
            // the player rechecks availability when the command executes.
            Task { @MainActor [weak self] in _ = self?.handler?(action) }
            return .success
        }
        registrations.append((command, token))
    }

    func update(_ state: SystemPlaybackState) {
        var metadata = state.metadata
        if state.artwork != lastArtworkData {
            lastArtworkData = state.artwork
            trackArtwork = nil
            if let data = state.artwork {
                #if os(macOS)
                if let image = NSImage(data: data), image.isValid {
                    trackArtwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                }
                #else
                if let image = UIImage(data: data) {
                    trackArtwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                }
                #endif
            }
        }
        if metadata != nil, let image = trackArtwork ?? artwork { metadata?[MPMediaItemPropertyArtwork] = image }
        center.nowPlayingInfo = metadata
        #if os(macOS)
        center.playbackState = state.title == nil ? .stopped : state.isPlaying ? .playing : .paused
        #endif
        commands.playCommand.isEnabled = state.canPlay
        commands.pauseCommand.isEnabled = state.title != nil && (state.isPlaying || state.isLoading)
        commands.togglePlayPauseCommand.isEnabled = state.title != nil
        commands.nextTrackCommand.isEnabled = state.canGoNext
        commands.previousTrackCommand.isEnabled = state.canPlay
        commands.changePlaybackPositionCommand.isEnabled = state.canSeek
        commands.stopCommand.isEnabled = state.title != nil
    }

    deinit {
        for (command, token) in registrations { command.removeTarget(token) }
        center.nowPlayingInfo = nil
        #if os(macOS)
        center.playbackState = .stopped
        #endif
    }
}
