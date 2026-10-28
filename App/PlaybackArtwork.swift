import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct PlaybackArtwork: View {
    @EnvironmentObject private var player: PlayerModel

    var body: some View {
        Group {
            #if os(macOS)
            if let data = player.metadata.artwork, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFit()
            } else { SaptakIcon() }
            #else
            if let data = player.metadata.artwork, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit()
            } else { SaptakIcon() }
            #endif
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityHidden(true)
    }
}
