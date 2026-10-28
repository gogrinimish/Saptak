#if DEBUG
import SwiftUI
import SaptakCore
#if os(macOS)
import AppKit
#endif

/// Explicit debug-only launch configuration. Never reads the normal app's saved selection.
struct ScreenshotCaptureConfiguration {
    enum Scene: String, CaseIterable { case welcome, library, folder, player, queue, search }
    let scene: Scene
    let root: URL
    let ready: URL
    let output: URL?

    static var current: Self? { parse(ProcessInfo.processInfo.arguments) }

    static func parse(_ arguments: [String]) -> Self? {
        func value(_ flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
        guard let name = value("--screenshot-scene"), let scene = Scene(rawValue: name),
              let root = value("--screenshot-root"), root.hasPrefix("/"),
              let ready = value("--screenshot-ready"), ready.hasPrefix("/") else { return nil }
        return Self(scene: scene, root: URL(fileURLWithPath: root, isDirectory: true),
                    ready: URL(fileURLWithPath: ready), output: value("--screenshot-output").map { URL(fileURLWithPath: $0) })
    }

    @MainActor static func library() -> LibraryModel {
        let defaults = UserDefaults(suiteName: "Saptak.ScreenshotCapture")!
        defaults.removePersistentDomain(forName: "Saptak.ScreenshotCapture")
        let library = LibraryModel(defaults: defaults)
        if let config = current, config.scene != .welcome { library.select(config.root) }
        return library
    }

    @MainActor func preparePlayback(root: AudioFolder, player: PlayerModel, access: FolderAccess?) async throws {
        let url = root.url.appendingPathComponent("Music/Acoustic Sessions", isDirectory: true)
        guard let folder = root.folder(at: url), folder.tracks.count >= 3 else {
            throw CocoaError(.fileNoSuchFile)
        }
        player.play(folder.allTracks, access: access, startingAt: folder.tracks[1])
        for _ in 0..<200 {
            if !player.isLoading, player.duration > 0 { break }
            if player.error != nil { throw CocoaError(.fileReadCorruptFile) }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        guard player.duration > 0 else { throw URLError(.timedOut) }
        player.seek(to: 83)
        player.cycleRepeat()
    }

    @MainActor func finish() async throws {
        try FileManager.default.createDirectory(at: ready.deletingLastPathComponent(), withIntermediateDirectories: true)
        #if os(macOS)
        if let output {
            guard let window = NSApplication.shared.windows.first(where: { $0.isVisible && $0.contentView != nil }),
                  let view = window.contentView else { throw CocoaError(.fileWriteUnknown) }
            window.appearance = NSAppearance(named: .aqua)
            window.setFrame(NSRect(origin: window.frame.origin, size: NSSize(width: 1440, height: 900)), display: true)
            window.orderFrontRegardless()
            NSApplication.shared.activate(ignoringOtherApps: true)
            try await Task.sleep(nanoseconds: 1_000_000_000)
            view.layoutSubtreeIfNeeded()
            // Native SwiftUI uses composited layers; the host captures only this window by ID.
            try Data(String(window.windowNumber).utf8).write(to: output.appendingPathExtension("windowid"), options: .atomic)
        }
        #endif
        try Data("ready".utf8).write(to: ready, options: .atomic)
    }
}
#endif
