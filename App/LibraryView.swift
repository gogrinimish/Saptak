import SwiftUI
import UniformTypeIdentifiers
import SaptakCore

private enum LibrarySection: String, CaseIterable, Identifiable {
    case recordings = "Tracks"
    case upNext = "Up Next"

    var id: Self { self }
}

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryModel
    @EnvironmentObject private var player: PlayerModel
    @Environment(\.saptakTheme) private var theme
    @State private var showPicker = false
    @State private var showQueue = false
    @State private var showPlayer = false
    @State private var showCloudHelp = false
    @State private var showFontLicense = false
    #if DEBUG
    @State private var screenshotConfigured = false
    #endif
    @State private var searchQuery = ""
    @State private var selectedFolder: URL?
    @State private var selectedSection: LibrarySection = .recordings
    #if os(iOS)
    @State private var mobilePath: [URL] = []
    #endif

    #if os(macOS)
    @ScaledMetric(relativeTo: .title) private var headerHeight: CGFloat = 68
    @State private var playbackHeight: CGFloat = 0
    #endif

    var body: some View {
        libraryLayout
            .foregroundStyle(theme.text)
            .background(theme.background)
            .fileImporter(isPresented: $showPicker, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        player.stop()
                        selectedFolder = nil
                        library.select(url)
                    }
                case .failure(let error): library.error = error.localizedDescription
                }
            }
            .sheet(isPresented: $showCloudHelp) { CloudFolderHelpView() }
            .sheet(isPresented: $showFontLicense) { FontLicenseView() }
            #if os(iOS)
            .sheet(isPresented: $showQueue) { QueueView() }
            .sheet(isPresented: $showPlayer) { ExpandedPlayerView() }
            #endif
            .alert(library.error != nil ? "Folder access" : "Playback", isPresented: Binding(
                get: { library.error != nil || player.error != nil },
                set: { if !$0 { library.error = nil; player.error = nil } }
            )) {
                if library.error != nil, library.access != nil {
                    Button("Retry") { library.refresh() }
                }
                Button("OK") { library.error = nil; player.error = nil }
            } message: { Text(library.error ?? player.error ?? "") }
            .onReceive(library.$root) { updated in
                guard let updated, let selectedFolder, updated.folder(at: selectedFolder) == nil else { return }
                self.selectedFolder = updated.nearestSurvivingAncestor(of: selectedFolder)
            }
            #if DEBUG
            .task(id: library.root?.url) { await configureScreenshot() }
            #endif
            .onAppear {
                if let root = library.root { player.restoreIfNeeded(root: root, access: library.access) }
            }
            .onChange(of: library.root?.url) {
                if let root = library.root { player.restoreIfNeeded(root: root, access: library.access) }
                searchQuery = ""
                selectedFolder = $0
                selectedSection = .recordings
                #if os(iOS)
                mobilePath = []
                #endif
            }
            #if os(macOS)
            .frame(minWidth: 680, minHeight: 520)
            #endif
    }

    #if DEBUG
    @MainActor private func configureScreenshot() async {
        guard !screenshotConfigured, let config = ScreenshotCaptureConfiguration.current else { return }
        guard config.scene == .welcome || library.root != nil else { return }
        screenshotConfigured = true
        do {
            try await Task.sleep(nanoseconds: 500_000_000)
            if config.scene != .welcome, let root = library.root {
                try await config.preparePlayback(root: root, player: player, access: library.access)
                if config.scene == .folder {
                    let destination = root.url.appendingPathComponent("Music/Acoustic Sessions", isDirectory: true)
                    selectedFolder = destination
                    #if os(iOS)
                    mobilePath = root.ancestry(to: destination)?.dropFirst().map(\.url) ?? []
                    #endif
                }
                if config.scene == .search { searchQuery = "light" }
                #if os(iOS)
                if config.scene == .player { showPlayer = true }
                if config.scene == .queue { showQueue = true }
                #else
                if config.scene == .queue { selectedSection = .upNext }
                #endif
            }
            try await Task.sleep(nanoseconds: 2_000_000_000)
            try await config.finish()
        } catch {
            try? Data("error: \(error.localizedDescription)".utf8).write(to: config.ready, options: .atomic)
        }
    }
    #endif

    @ViewBuilder private var libraryLayout: some View {
        if library.root == nil {
            WelcomeView(isLoading: library.isRefreshing, chooseFolder: { showPicker = true },
                        retry: library.access == nil ? nil : { library.refresh() })
                .environment(\.saptakTheme, detailTheme)
                .tint(detailTheme.accent)
                #if os(macOS)
                .environment(\.colorScheme, .light)
                .toolbarBackground(.hidden, for: .windowToolbar)
                #endif
        } else {
            browserLayout
        }
    }

    @ViewBuilder private var browserLayout: some View {
        #if os(macOS)
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
        } detail: {
            MacLibraryColumn {
                centerTabs
                    .frame(maxWidth: .infinity)
                    .frame(height: headerHeight)
                    .overlay(alignment: .bottom) { Divider() }
                ZStack {
                    switch selectedSection {
                    case .recordings:
                        VStack(spacing: 0) {
                            LibrarySearchField(query: $searchQuery)
                            Divider()
                            if isSearching { searchResults } else { detail }
                        }
                    case .upNext: PlaybackQueueList()
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .clipped()
                PlaybackControls()
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(key: PlaybackHeightKey.self, value: geometry.size.height)
                        }
                    }
                    .clipped()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(detailTheme.text)
            .tint(detailTheme.accent)
            .background(detailTheme.background)
            .environment(\.saptakTheme, detailTheme)
            .environment(\.colorScheme, .light)
            .navigationTitle("")
        }
        .toolbarBackground(.hidden, for: .windowToolbar)
        .onPreferenceChange(PlaybackHeightKey.self) { playbackHeight = $0 }
        .background(SaptakTheme.plum.ignoresSafeArea())
        #else
        PlayerDockLayout {
            NavigationStack(path: $mobilePath) {
                if let root = library.root {
                    mobileFolder(root.url)
                        .navigationDestination(for: URL.self) { mobileFolder($0) }
                }
            }
            .id(library.root?.url)
            .onReceive(library.$root) { root in
                if let root { mobilePath = root.validNavigationPath(mobilePath) }
            }
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            .clipped()
            CompactPlayerView { showPlayer = true }
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .clipped()
        }
        .background(SaptakTheme.plum.ignoresSafeArea(edges: .bottom))
        #endif
    }

    #if os(macOS)
    private var centerTabs: some View {
        HStack(spacing: 8) {
            ForEach(LibrarySection.allCases) { section in
                Button { selectedSection = section } label: {
                    Text(section == .upNext && !player.queue.tracks.isEmpty
                         ? "Up Next (\(player.queue.tracks.count))" : section.rawValue)
                        .frame(minWidth: 72)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(SaptakButtonStyle(prominent: selectedSection == section, compact: true))
                .accessibilityAddTraits(selectedSection == section ? .isSelected : [])
                .help(section == .recordings ? "Show tracks in the selected folder" : "Show the current track and playback order")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Library view")
        .padding(.horizontal, 20).padding(.vertical, 12)
    }
    #endif

    private var detailTheme: SaptakTheme {
        #if os(macOS)
        return SaptakTheme(dark: false, increasedContrast: theme.increasedContrast)
        #else
        return theme
        #endif
    }

    @ViewBuilder private var detail: some View {
        if let root = library.root {
            FolderView(folderURL: selectedFolder ?? root.url) {
                if let root = library.root { player.restoreIfNeeded(root: root, access: library.access) }
                searchQuery = ""
                selectedFolder = $0
                selectedSection = .recordings
            }
        }
    }

    #if os(macOS)
    private var sidebarSeparator: some View {
        Rectangle()
            .fill(SaptakTheme.cream.opacity(theme.increasedContrast ? 0.8 : 0.3))
            .frame(height: theme.borderWidth)
            .padding(.horizontal, 20)
            .accessibilityHidden(true)
    }

    private var sidebar: some View {
        MacLibraryColumn {
            HStack(spacing: 12) {
                SaptakIcon(markInset: 5).frame(width: 40, height: 40)
                SaptakWordmark()
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20).padding(.vertical, 8)
            .frame(height: headerHeight)
            .overlay(alignment: .bottom) { sidebarSeparator }

            ScrollView {
                if let root = library.root {
                    SidebarFolderNode(folder: root, selected: selectedFolder ?? root.url,
                                      select: { searchQuery = ""; selectedFolder = $0; selectedSection = .recordings },
                                      refresh: { library.refresh() }, isRefreshing: library.isRefreshing)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16).padding(.vertical, 12)
                }
            }
            .id(library.root?.url)
            .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            .clipped()

            Button { showPicker = true } label: {
                Label("Change folder…", systemImage: "folder.badge.plus")
                    .saptakText(.item)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).frame(minHeight: 44)
                    .contentShape(Rectangle())
                    .overlay { RoundedRectangle(cornerRadius: 10).stroke(SaptakTheme.cream, lineWidth: theme.borderWidth) }
            }
            .buttonStyle(.plain)
            .help("Choose a different audio folder")
            .contextMenu {
                Button("Using cloud folders") { showCloudHelp = true }
                Link("Privacy policy", destination: SaptakLinks.privacyPolicy)
                Link("Support", destination: SaptakLinks.support)
                Button("Font license") { showFontLicense = true }
            }
            .accessibilityHint("Replaces the selected folder. Your original files stay where they are.")
            .padding(16)
            .frame(minHeight: playbackHeight, alignment: .bottom)
            .overlay(alignment: .top) { sidebarSeparator }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(SaptakTheme.cream)
        .tint(SaptakTheme.cream)
        .background(SaptakTheme.plum)
        .navigationTitle("")
    }
    #endif

    private var isSearching: Bool { !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var searchResults: some View {
        LibrarySearchView(query: searchQuery) { destination in
            searchQuery = ""
            selectedFolder = destination
            #if os(iOS)
            mobilePath = library.root?.ancestry(to: destination)?.dropFirst().map(\.url) ?? []
            #endif
        }
    }

    #if os(iOS)
    private func mobileFolder(_ url: URL) -> some View {
        VStack(spacing: 0) {
            LibrarySearchField(query: $searchQuery)
            Divider()
            if isSearching { searchResults }
            else {
                FolderView(folderURL: url) { destination in
                    mobilePath = library.root?.ancestry(to: destination)?.dropFirst().map(\.url) ?? []
                }
            }
        }
        .navigationTitle(library.root?.folder(at: url)?.title ?? url.lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(theme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar { libraryToolbar }
    }

    @ToolbarContentBuilder private var libraryToolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            HStack(spacing: 6) {
                SaptakIcon(markInset: 3, cornerRadius: 6).frame(width: 24, height: 24)
                SaptakWordmark(style: .headline).lineLimit(1)
            }
            .foregroundStyle(theme.text)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Saptak")
        }
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            Button { showQueue = true } label: { Label("Up Next", systemImage: "list.bullet") }
                .accessibilityLabel("Show Up Next")
            Menu {
                if !mobilePath.isEmpty, let root = library.root {
                    Button { mobilePath = [] } label: { Label("Back to \(root.title)", systemImage: "house") }
                }
                Button { library.refresh() } label: { Label("Refresh folders", systemImage: "arrow.clockwise") }
                    .disabled(library.access == nil || library.isRefreshing)
                Button { showPicker = true } label: { Label("Change folder…", systemImage: "folder.badge.plus") }
                Divider()
                Button { showCloudHelp = true } label: { Label("Using cloud folders", systemImage: "questionmark.circle") }
                Link("Privacy policy", destination: SaptakLinks.privacyPolicy)
                Link("Support", destination: SaptakLinks.support)
                Button("Font license") { showFontLicense = true }
            } label: { Label("Folder actions", systemImage: "ellipsis.circle") }
        }
    }
    #endif
}

#if os(macOS)
private struct PlaybackHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct SidebarFolderNode: View {
    let folder: AudioFolder
    let selected: URL
    let select: (URL) -> Void
    var refresh: (() -> Void)? = nil
    var isRefreshing = false
    var depth = 0
    @State private var expanded = true

    private var isSelected: Bool { selected == folder.url }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if folder.children.isEmpty {
                folderRow
            } else {
                DisclosureGroup(isExpanded: $expanded) {
                    ForEach(folder.children) { child in
                        SidebarFolderNode(folder: child, selected: selected, select: select, depth: depth + 1)
                            .padding(.leading, 16)
                    }
                } label: { folderRow }
            }
        }
    }

    private var folderRow: some View {
        HStack(spacing: 4) {
            folderButton
            if let refresh {
                Button(action: refresh) {
                    Group {
                        if isRefreshing { ProgressView().controlSize(.small).tint(SaptakTheme.cream) }
                        else { Image(systemName: "arrow.clockwise") }
                    }
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(SaptakTheme.cream)
                .disabled(isRefreshing)
                .accessibilityLabel("Refresh \(folder.title) and its subfolders")
                .accessibilityValue(isRefreshing ? "Refreshing" : "")
                .help("Rescan this folder and subfolders for track changes")
            }
        }
    }

    private var folderButton: some View {
        Button { select(folder.url) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "folder")
                Text(folder.title)
                    .saptakText(.item)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if isSelected { Image(systemName: "checkmark").accessibilityHidden(true) }
                Text("\(folder.allTracks.count)").saptakText(.count).monospacedDigit()
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .foregroundStyle(isSelected ? SaptakTheme.deepInk : SaptakTheme.cream)
            .background(isSelected ? SaptakTheme.olive : .clear, in: RoundedRectangle(cornerRadius: 9))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(folder.title), \(trackCountLabel(folder.allTracks.count))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
#endif

struct FolderView: View {
    let folderURL: URL
    var selectFolder: ((URL) -> Void)? = nil
    @EnvironmentObject private var library: LibraryModel
    @EnvironmentObject private var player: PlayerModel
    @Environment(\.saptakTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if let folder = library.root?.folder(at: folderURL) {
                folderList(folder)
            } else {
                VStack(spacing: 16) {
                    Text("This folder is no longer available.").font(SaptakTypography.text(.headline))
                    Text("Choose a folder in the library or return to your audio folder.")
                    if let root = library.root, let selectFolder {
                        Button("Return to library") { selectFolder(root.url) }.buttonStyle(SaptakButtonStyle())
                    }
                }.padding().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(theme.background)
    }

    private func folderList(_ folder: AudioFolder) -> some View {
        #if os(macOS)
        VStack(spacing: 0) {
            folderSummary(folder)
                .padding(.horizontal, 8).padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            trackList(folder)
        }
        #else
        VStack(spacing: 0) {
            if let ancestors = library.root?.ancestry(to: folder.url), ancestors.count > 1, let selectFolder {
                FolderBreadcrumbs(ancestors: Array(ancestors.dropLast()), select: selectFolder)
                Divider()
            }
            trackList(folder)
        }
        #endif
    }

    private func folderSummary(_ folder: AudioFolder) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(folder.title).saptakText(.paneTitle)
                .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
            Text(folder.children.isEmpty ? trackCountLabel(folder.tracks.count) :
                 "\(trackCountLabel(folder.allTracks.count)) · includes subfolders")
                .saptakText(.metadata).foregroundStyle(theme.secondaryText)
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) { folderActions(folder) }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { folderActions(folder) }
                    VStack(alignment: .leading, spacing: 12) { folderActions(folder) }
                }
            }
            if library.isRefreshing { ProgressView("Refreshing…") }
        }
    }

    private func trackList(_ folder: AudioFolder) -> some View {
        List {
            #if os(iOS)
            Section {
                folderSummary(folder).modifier(MobileLibraryRow())
            }
            .listSectionSeparator(.hidden)
            .listRowBackground(theme.background)
            #endif

            if !library.warnings.isEmpty {
                Section {
                    ForEach(Array(library.warnings.enumerated()), id: \.offset) { _, warning in
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(theme.text)
                            .modifier(MobileLibraryRow())
                    }
                } header: { Text("Folder access notices").saptakText(.section).accessibilityAddTraits(.isHeader) }.listRowBackground(theme.secondarySurface)
                #if os(iOS)
                .listSectionSeparator(.hidden)
                #endif
            }
            #if os(iOS)
            if !folder.children.isEmpty {
                Section {
                    ForEach(folder.children) { child in
                        NavigationLink(value: child.url) { folderLabel(child) }
                            .modifier(MobileLibraryRow())
                    }.listRowBackground(theme.background)
                } header: { Text("Folders").saptakText(.section).accessibilityAddTraits(.isHeader) }
                .listSectionSeparator(.hidden)
            }
            #endif
            Section {
                if displayedTracks(folder).isEmpty {
                    Text(emptyMessage(folder)).saptakText(.metadata)
                        .foregroundStyle(theme.secondaryText).padding(.vertical, 12)
                        .modifier(MobileLibraryRow())
                        .listRowBackground(theme.background)
                }
                ForEach(displayedTracks(folder)) { track in
                    let selected = player.queue.current?.url == track.url
                    Button { player.play(displayedTracks(folder), access: library.access, startingAt: track) } label: {
                        RecordingLabel(track: track, selected: selected,
                                       status: selected ? (player.isLoading ? "Loading" : player.isPlaying ? "Now playing" : "Paused") : nil)
                    }
                    .buttonStyle(.plain)
                    .modifier(MobileLibraryRow())
                    .originalFileSharing(track: track, access: library.access)
                    .help("Play from this track in the folder playlist")
                    .accessibilityHint("Starts this track, then continues through the displayed tracks")
                    .listRowBackground(selected ? SaptakTheme.olive : theme.background)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            } header: { Text("Tracks").saptakText(.section).accessibilityAddTraits(.isHeader) }
            #if os(macOS)
            .listSectionSeparator(.hidden, edges: .top)
            #else
            .listSectionSeparator(.hidden)
            #endif
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(theme.background)
        .foregroundStyle(theme.text)
    }

    private func displayedTracks(_ folder: AudioFolder) -> [AudioTrack] {
        #if os(macOS)
        return folder.allTracks
        #else
        return folder.tracks
        #endif
    }

    private func emptyMessage(_ folder: AudioFolder) -> String {
        #if os(macOS)
        return "No supported tracks in this folder or its subfolders."
        #else
        return folder.children.isEmpty ? "No supported tracks in this folder." : "Tracks are in the subfolders above. Play All includes them."
        #endif
    }

    @ViewBuilder private func folderActions(_ folder: AudioFolder) -> some View {
        Button { player.play(folder.allTracks, access: library.access) } label: {
            Label("Play all", systemImage: "play.fill").labelStyle(.titleAndIcon)
        }
        .buttonStyle(SaptakButtonStyle(prominent: true))
        .accessibilityLabel("Play all \(trackCountLabel(folder.allTracks.count)), including subfolders")
        .help("Play this folder and all its subfolders")
        .disabled(folder.allTracks.isEmpty)
        Button { player.play(folder.allTracks, access: library.access, shuffled: true) } label: {
            Label("Shuffle", systemImage: "shuffle").labelStyle(.titleAndIcon)
        }
        .buttonStyle(SaptakButtonStyle())
        .accessibilityLabel("Shuffle all tracks, including subfolders")
        .help("Play this folder and its subfolders in a shuffled order")
        .disabled(folder.allTracks.isEmpty)
    }

    private func folderLabel(_ folder: AudioFolder) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "folder").font(.title3).accessibilityHidden(true)
            Text(folder.title).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Text("\(folder.allTracks.count)").monospacedDigit()
        }
        .foregroundStyle(theme.text)
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(folder.title), \(trackCountLabel(folder.allTracks.count))")
    }
}

struct RecordingLabel: View {
    @EnvironmentObject private var player: PlayerModel
    let track: AudioTrack
    var selected = false
    var status: String?
    @Environment(\.saptakTheme) private var theme

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: selected ? "speaker.wave.2.fill" : "music.note")
                .font(.title3).frame(width: 26).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(selected ? player.title : track.title).saptakText(.item)
                    .fixedSize(horizontal: false, vertical: true)
                Text(status ?? track.url.deletingLastPathComponent().lastPathComponent)
                    .saptakText(.metadata).foregroundStyle(selected ? SaptakTheme.deepInk : theme.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .contentShape(Rectangle())
        .foregroundStyle(selected ? SaptakTheme.deepInk : theme.text)
        .accessibilityElement(children: .combine)
    }
}

/// Embedded on Mac; the iOS sheet reuses this content without owning playback state.
struct PlaybackQueueList: View {
    var showsHeading = true
    @EnvironmentObject private var player: PlayerModel
    @Environment(\.saptakTheme) private var theme

    var body: some View {
        let items = Array(player.queue.tracks.enumerated())
        List {
            if showsHeading {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Up Next").saptakText(.paneTitle)
                            .accessibilityAddTraits(.isHeader)
                        Text("\(player.queue.tracks.count) \(player.queue.tracks.count == 1 ? "track" : "tracks") in playback order")
                            .saptakText(.metadata).foregroundStyle(theme.secondaryText)
                    }.padding(.vertical, 12)
                }.listRowBackground(theme.background)
            }
            if player.queue.tracks.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Nothing queued yet").font(SaptakTypography.text(.headline))
                    Text("Choose a track or Play all to start a queue.")
                        .font(SaptakTypography.text(.body)).foregroundStyle(theme.secondaryText)
                }
                .padding(.vertical, 16).listRowBackground(theme.background)
            } else if let current = player.queue.index {
                if current > 0 {
                    Section {
                        ForEach(Array(items.prefix(current)), id: \.offset) { index, track in
                            queueRow(index, track: track)
                        }
                    } header: { Text("Earlier in queue").saptakText(.section) }
                }
                Section {
                    if let track = player.queue.current { queueRow(current, track: track) }
                } header: {
                    Text(player.isPlaying ? "Now playing" : "Current track").saptakText(.section)
                }
                Section {
                    if current + 1 < player.queue.tracks.count {
                        ForEach(Array(items.dropFirst(current + 1)), id: \.offset) { index, track in
                            queueRow(index, track: track)
                        }
                    } else {
                        Text(player.queue.repeatMode == .all ? "Repeat All returns to the first track." :
                             player.queue.repeatMode == .one ? "Repeat One replays the current track." :
                             "This is the last track in the queue.")
                            .font(SaptakTypography.text(.callout)).foregroundStyle(theme.secondaryText)
                            .listRowBackground(theme.background)
                    }
                } header: { Text("Up next").saptakText(.section) }
            }
        }
        .listStyle(.plain).scrollContentBackground(.hidden)
        .background(theme.background).foregroundStyle(theme.text)
    }

    private func queueRow(_ index: Int, track: AudioTrack) -> some View {
        let selected = player.queue.index == index
        return Button { player.select(index) } label: {
            HStack(alignment: .center, spacing: 12) {
                Text("\(index + 1)").font(SaptakTypography.text(.caption)).monospacedDigit()
                    .frame(minWidth: 24).accessibilityHidden(true)
                RecordingLabel(track: track, selected: selected,
                               status: selected ? (player.isLoading ? "Loading" : player.isPlaying ? "Now playing" : "Current track") : nil)
            }
            .foregroundStyle(selected ? SaptakTheme.deepInk : theme.secondaryText)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(selected ? SaptakTheme.olive : theme.background)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint("Continue playback from this track in the queue")
        .help("Continue playback from this track")
        .originalFileSharing(track: track, access: player.folderAccessForSharing)
    }
}

struct QueueView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.saptakTheme) private var theme

    var body: some View {
        NavigationStack {
            PlaybackQueueList(showsHeading: false)
                .navigationTitle("Up Next")
                .toolbar { Button("Done") { dismiss() }.frame(minHeight: 44) }
        }
        .tint(theme.accent)
        .frame(minWidth: 300, minHeight: 300)
    }
}

private func trackCountLabel(_ count: Int) -> String {
    "\(count) \(count == 1 ? "track" : "tracks")"
}
