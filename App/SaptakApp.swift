import SwiftUI
#if os(macOS)
import AppKit
#endif

@main
struct SaptakApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(SaptakApplicationDelegate.self) private var applicationDelegate
    #endif
    @StateObject private var library: LibraryModel
    @StateObject private var player: PlayerModel

    @MainActor init() {
        #if os(iOS)
        SaptakTypography.configureNavigationAppearance()
        #endif
        #if DEBUG
        if ScreenshotCaptureConfiguration.current != nil {
            _library = StateObject(wrappedValue: ScreenshotCaptureConfiguration.library())
            _player = StateObject(wrappedValue: PlayerModel())
            return
        }
        #endif
        _library = StateObject(wrappedValue: LibraryModel())
        _player = StateObject(wrappedValue: PlayerModel(systemPlayback: NativeSystemPlaybackOutput(), recovery: PlaybackRecoveryStore()))
    }

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup("Saptak") {
            SaptakRootView()
                .environmentObject(library)
                .environmentObject(player)
                .onChange(of: scenePhase) {
                    if $0 == .active { library.refreshIfNeeded() }
                    else { player.checkpoint() }
                }
                #if os(macOS)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in player.checkpoint() }
                #endif
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1000, height: 720)
        #endif
    }
}

#if os(macOS)
@MainActor final class SaptakApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Use the built bundle's icon for the running Dock tile, including Xcode launches.
        guard let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let image = NSImage(contentsOf: url), image.isValid else { return }
        NSApplication.shared.applicationIconImage = image
    }
}
#endif
