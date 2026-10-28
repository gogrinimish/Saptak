import SwiftUI
import SaptakCore

struct LibrarySearchField: View {
    @Binding var query: String
    @Environment(\.saptakTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").accessibilityHidden(true)
            TextField("Search all tracks and folders", text: $query)
                .textFieldStyle(.plain)
                .accessibilityLabel("Search all tracks and folders")
                .accessibilityHint("Searches names throughout your selected library")
                .submitLabel(.search)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                #endif
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44)
                }
                .buttonStyle(.plain).accessibilityLabel("Clear search")
            }
        }
        .saptakText(.item)
        .padding(.horizontal, 12).frame(minHeight: 44)
        .foregroundStyle(theme.text)
        .background(theme.background)
        .overlay { RoundedRectangle(cornerRadius: 10).stroke(theme.secondaryText.opacity(0.5), lineWidth: theme.borderWidth) }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(theme.background)
    }
}

struct LibrarySearchView: View {
    let query: String
    let selectFolder: (URL) -> Void
    @EnvironmentObject private var library: LibraryModel
    @EnvironmentObject private var player: PlayerModel
    @Environment(\.saptakTheme) private var theme

    var body: some View {
        let results = library.root.map { LibrarySearch.search(query, in: $0) }
        List {
            Section {
                if library.isRefreshing { ProgressView("Refreshing…") }
                ForEach(Array(library.warnings.enumerated()), id: \.offset) { _, warning in
                    Label(warning, systemImage: "exclamationmark.triangle").saptakText(.metadata)
                }
                Text("Searches all track and folder names in your selected library.")
                    .saptakText(.metadata).foregroundStyle(theme.secondaryText)
                    .modifier(MobileLibraryRow())
            }.listRowBackground(theme.background)
            if let results {
                if results.folders.isEmpty && results.tracks.isEmpty {
                    Text("No matching tracks or folders.").saptakText(.item)
                        .foregroundStyle(theme.secondaryText)
                        .modifier(MobileLibraryRow()).listRowBackground(theme.background)
                }
                if !results.folders.isEmpty {
                    Section {
                        ForEach(results.folders) { result in
                            Button { selectFolder(result.folder.url) } label: {
                                resultLabel(result.folder.title, path: result.path, icon: "folder")
                            }
                            .buttonStyle(.plain).modifier(MobileLibraryRow())
                            .accessibilityHint("Open this folder and leave search")
                        }
                    } header: { Text("Folders (\(results.folders.count))").saptakText(.section).accessibilityAddTraits(.isHeader) }.listRowBackground(theme.background)
                }
                if !results.tracks.isEmpty {
                    Section {
                        ForEach(results.tracks) { result in
                            let selected = player.queue.current?.url == result.track.url
                            Button {
                                guard let folder = library.root?.folder(at: result.folderURL) else { return }
                                player.play(folder.allTracks, access: library.access, startingAt: result.track)
                            } label: {
                                resultLabel(result.track.title, path: result.path,
                                            icon: selected ? "speaker.wave.2.fill" : "music.note", selected: selected)
                            }
                            .buttonStyle(.plain).modifier(MobileLibraryRow())
                            .originalFileSharing(track: result.track, access: library.access)
                            .accessibilityHint("Play this track in its containing folder's recursive playlist")
                            .listRowBackground(selected ? SaptakTheme.olive : theme.background)
                        }
                    } header: { Text("Tracks (\(results.tracks.count))").saptakText(.section).accessibilityAddTraits(.isHeader) }
                }
            }
        }
        .listStyle(.plain).scrollContentBackground(.hidden)
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        #endif
        .background(theme.background).foregroundStyle(theme.text)
    }

    private func resultLabel(_ title: String, path: String, icon: String, selected: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).frame(width: 26).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).saptakText(.item).foregroundStyle(selected ? SaptakTheme.deepInk : theme.text).fixedSize(horizontal: false, vertical: true)
                Text(path).saptakText(.metadata).foregroundStyle(selected ? SaptakTheme.deepInk : theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.vertical, 6).contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
