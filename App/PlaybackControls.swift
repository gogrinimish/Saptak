import SwiftUI

struct PlaybackControls: View {
    @EnvironmentObject private var player: PlayerModel
    @State private var scrubPosition: Double = 0
    @State private var scrubbing = false

    var body: some View {
        Group {
            #if os(macOS)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 20) {
                    trackInformation.frame(width: 210)
                    VStack(spacing: 10) {
                        HStack(spacing: 8) { transportButtons }
                        seekBar
                        playbackModes
                    }.frame(minWidth: 290)
                }
                stackedContents
            }
            #else
            stackedContents
            #endif
        }
        .foregroundStyle(SaptakTheme.cream)
        .padding(20)
        .background(SaptakTheme.plum)
        .environment(\.colorScheme, .dark)
        .onChange(of: player.queue.current?.url) { _ in scrubbing = false; scrubPosition = 0 }
    }

    private var stackedContents: some View {
        VStack(alignment: .leading, spacing: 14) {
            trackInformation
            seekBar
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { transportButtons }.frame(maxWidth: .infinity)
                VStack(spacing: 12) { transportButtons }.frame(maxWidth: .infinity)
            }
            playbackModes
        }
    }

    private var playbackModes: some View {
        Text("Shuffle \(player.queue.isShuffled ? "on" : "off") · Repeat \(player.queue.repeatMode.rawValue)")
            .font(SaptakTypography.text(.callout)).frame(maxWidth: .infinity)
    }

    private var trackInformation: some View {
            HStack(alignment: .top, spacing: 16) {
                if player.metadata.artwork != nil {
                    PlaybackArtwork().frame(width: 44, height: 44)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(player.title).font(SaptakTypography.text(.headline)).fixedSize(horizontal: false, vertical: true)
                    if player.queue.current != nil {
                        Text(player.subtitle)
                            .font(SaptakTypography.text(.callout)).fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Choose a track to begin.").font(SaptakTypography.text(.callout))
                    }
                }
                Spacer(minLength: 0)
                if player.isLoading { ProgressView("Loading…").tint(SaptakTheme.cream) }
                #if os(iOS)
                AirPlayButton().frame(width: 44, height: 44)
                    .accessibilityLabel("Choose audio output with AirPlay")
                #endif
            }
    }

    private var seekBar: some View {
            HStack(spacing: 12) {
                Text(playbackTime(scrubbing ? scrubPosition : player.position))
                    .monospacedDigit().accessibilityHidden(true)
                Slider(value: Binding(
                    get: { scrubbing ? scrubPosition : min(player.position, max(player.duration, 1)) },
                    set: { scrubPosition = $0 }
                ), in: 0...max(player.duration, 1)) { editing in
                    if editing { scrubPosition = player.position }
                    scrubbing = editing
                    if !editing { player.seek(to: scrubPosition) }
                }
                .disabled(player.duration <= 0 || player.isLoading)
                .tint(SaptakTheme.rose)
                .accessibilityLabel("Playback position")
                .help("Seek within the current track")
                .accessibilityValue("\(playbackTime(player.position)) of \(playbackTime(player.duration))")
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: player.seek(to: player.position + 15)
                    case .decrement: player.seek(to: player.position - 15)
                    @unknown default: break
                    }
                }
                Text(playbackTime(player.duration)).monospacedDigit().accessibilityHidden(true)
            }.font(SaptakTypography.text(.callout))
    }

    @ViewBuilder private var transportButtons: some View {
        Button { player.toggleShuffle() } label: { Image(systemName: "shuffle") }
            .buttonStyle(TransportButtonStyle(selected: player.queue.isShuffled))
            .accessibilityLabel("Shuffle").accessibilityValue(player.queue.isShuffled ? "On" : "Off")
            .help(player.queue.isShuffled ? "Restore the original track order" : "Shuffle the playback queue")
            .disabled(player.queue.tracks.isEmpty)
            .modifier(TransportRowItem())
        Button { player.previous() } label: { Image(systemName: "backward.end.fill") }
            .buttonStyle(TransportButtonStyle()).accessibilityLabel("Previous track")
            .help("Restart this track or play the previous track")
            .disabled(player.queue.tracks.isEmpty)
            .modifier(TransportRowItem())
        playbackButton.modifier(TransportRowItem())
        Button { player.next() } label: { Image(systemName: "forward.end.fill") }
            .buttonStyle(TransportButtonStyle()).accessibilityLabel("Next track")
            .help("Play the next track in the queue").disabled(player.queue.tracks.isEmpty)
            .modifier(TransportRowItem())
        Button { player.cycleRepeat() } label: {
            Image(systemName: player.queue.repeatMode == .one ? "repeat.1" : "repeat")
        }
        .buttonStyle(TransportButtonStyle(selected: player.queue.repeatMode != .off))
        .accessibilityLabel("Repeat mode").accessibilityValue(player.queue.repeatMode.rawValue)
        .help(repeatHelp).disabled(player.queue.tracks.isEmpty)
        .modifier(TransportRowItem())
    }

    private var repeatHelp: String {
        switch player.queue.repeatMode {
        case .off: return "Repeat is off. Click to repeat the whole queue."
        case .all: return "Repeating the whole queue. Click to repeat one track."
        case .one: return "Repeating one track. Click to turn repeat off."
        }
    }

    private var playbackButton: some View {
        Button { player.toggle() } label: { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill") }
            .buttonStyle(TransportButtonStyle(primary: true))
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            .help(player.isPlaying ? "Pause" : "Play")
            .disabled(player.isLoading || player.queue.tracks.isEmpty)
            #if os(macOS)
            .keyboardShortcut(.space, modifiers: [])
            #endif
    }
}

private struct TransportRowItem: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        #if os(iOS)
        content.frame(maxWidth: .infinity)
        #else
        content
        #endif
    }
}

private struct TransportButtonStyle: ButtonStyle {
    @Environment(\.saptakTheme) private var theme
    @Environment(\.isEnabled) private var enabled
    var primary = false
    var selected = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3.weight(.semibold))
            .frame(minWidth: 44, minHeight: 44)
            .padding(.horizontal, primary ? 8 : 0)
            .foregroundStyle(primary || selected ? SaptakTheme.deepInk : SaptakTheme.cream)
            .background(primary ? SaptakTheme.rose : selected ? SaptakTheme.olive : SaptakTheme.plum,
                        in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(enabled ? SaptakTheme.cream : SaptakTheme.olive,
                            lineWidth: configuration.isPressed ? 3 : theme.borderWidth)
            }
    }
}

struct CompactPlayerView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let expand: () -> Void
    @EnvironmentObject private var player: PlayerModel

    var body: some View {
        HStack(spacing: 12) {
            Button(action: expand) {
                HStack(spacing: 12) {
                    SaptakMark(color: SaptakTheme.cream).frame(width: 32, height: 32)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(player.title).font(SaptakTypography.text(.subheadline)).lineLimit(2)
                        Text(player.isLoading ? "Loading…" : dynamicTypeSize.isAccessibilitySize ? "Player" : "Player and Up Next")
                            .font(SaptakTypography.text(.caption)).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).foregroundStyle(SaptakTheme.cream)
            .accessibilityLabel("Open player, \(player.title)")
            .accessibilityHint("Shows playback controls and Up Next")
            Button { player.toggle() } label: { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill") }
                .buttonStyle(TransportButtonStyle(primary: true))
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                .disabled(player.queue.tracks.isEmpty || player.isLoading)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(SaptakTheme.plum.ignoresSafeArea(edges: .bottom))
    }
}

struct ExpandedPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.saptakTheme) private var theme
    @EnvironmentObject private var player: PlayerModel
    @State private var showQueue = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    PlaybackArtwork().frame(width: 120, height: 120).padding(.top, 24)
                    SaptakWordmark().foregroundStyle(theme.text)
                    PlaybackControls().clipShape(RoundedRectangle(cornerRadius: 20))
                    if let track = player.queue.current {
                        OriginalFileShareButton(track: track, access: player.folderAccessForSharing)
                    }
                    Button { showQueue = true } label: {
                        Label("Up Next · \(player.queue.tracks.count)", systemImage: "list.bullet")
                    }.buttonStyle(SaptakButtonStyle())
                }.padding(20)
            }
            .background(theme.background)
            .navigationTitle("Now playing")
            .toolbar { Button("Done") { dismiss() }.frame(minHeight: 44) }
            .sheet(isPresented: $showQueue) { QueueView() }
        }
        .tint(theme.accent)
    }
}

private func playbackTime(_ seconds: Double) -> String {
    let value = seconds.isFinite ? Int(max(0, seconds)) : 0
    if value >= 3600 { return String(format: "%d:%02d:%02d", value / 3600, (value / 60) % 60, value % 60) }
    return String(format: "%d:%02d", value / 60, value % 60)
}

#if os(iOS)
import AVKit

struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = UIColor(SaptakTheme.cream)
        view.activeTintColor = UIColor(SaptakTheme.rose)
        return view
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
#endif
