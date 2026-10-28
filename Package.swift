// swift-tools-version: 5.9
import PackageDescription

var targets: [Target] = [
    .target(name: "SaptakCore"),
    .testTarget(name: "SaptakCoreTests", dependencies: ["SaptakCore"])
]

#if os(macOS)
// Exercise the same Apple integration sources used by the apps without a UI host.
targets += [
    .target(
        name: "SaptakPlatform",
        dependencies: ["SaptakCore"],
        path: "App",
        exclude: ["SaptakApp.swift", "Assets.xcassets", "SaptakMac.entitlements", "PrivacyInfo.xcprivacy"],
        sources: ["LibraryModel.swift", "PlayerModel.swift", "SystemPlayback.swift", "MacLibraryColumn.swift", "MobileLibraryComponents.swift", "LibraryView.swift", "PlaybackControls.swift", "SaptakTheme.swift", "WelcomeView.swift", "CloudFolderHelpView.swift", "PlaybackRecovery.swift", "LibrarySearchView.swift", "OriginalFileSharing.swift", "AudioMetadata.swift", "PlaybackArtwork.swift", "ScreenshotCapture.swift"],
        resources: [.copy("Fonts")]
    ),
    .testTarget(name: "SaptakPlatformTests", dependencies: ["SaptakPlatform", "SaptakCore"], resources: [.copy("Fixtures")])
]
#endif

let package = Package(
    name: "SaptakCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "SaptakCore", targets: ["SaptakCore"])],
    targets: targets
)
