import SwiftUI
import SaptakCore
#if os(macOS)
import AppKit
#else
import UIKit
import UniformTypeIdentifiers
#endif

struct OriginalFileLocation: Identifiable, Sendable {
    var id: URL { fileURL }
    let fileURL: URL
    let folderURL: URL
    let filename: String
    let folderDescription: String

    init(track: AudioTrack, root: URL?) throws {
        let url = track.url
        guard url.isFileURL, url.user == nil, url.password == nil,
              url.host == nil || url.host == "" || url.host == "localhost",
              url.query == nil, url.fragment == nil, !url.lastPathComponent.isEmpty else {
            throw FileAccessError.unavailable("The original file location is not a local document URL.")
        }
        fileURL = url
        folderURL = url.deletingLastPathComponent()
        filename = url.lastPathComponent
        let parent = folderURL.standardizedFileURL.pathComponents
        if let root {
            let prefix = root.standardizedFileURL.pathComponents
            if parent.starts(with: prefix), let name = prefix.last {
                folderDescription = ([name] + parent.dropFirst(prefix.count)).joined(separator: " › ")
                return
            }
        }
        folderDescription = folderURL.lastPathComponent
    }

    /// Apple DTS describes this Files route publicly, but it is not a documented API contract.
    /// Preserve the exact original path and percent encoding; never substitute an export URL.
    var filesURL: URL? {
        var components = URLComponents(url: fileURL, resolvingAgainstBaseURL: false)
        components?.scheme = "shareddocuments"
        return components?.url
    }
}

enum OriginalFileLocationAccess {
    static func inspect(_ url: URL, coordinate: ProviderAccess.CoordinateRead = ProviderAccess.coordinateRead) throws {
        var result: Result<Void, Error>?
        try coordinate(url) { coordinatedURL in
            result = Result {
                let values = try coordinatedURL.resourceValues(forKeys: [.isRegularFileKey])
                guard values.isRegularFile == true else {
                    throw FileAccessError.unavailable("The original track is no longer an audio file. Refresh the library.")
                }
            }
        }
        guard let result else { throw FileAccessError.unavailable("The file provider did not respond.") }
        try result.get()
    }

    static func prepare(track: AudioTrack, access: FolderAccess?,
                        inspect: @escaping @Sendable (URL) throws -> Void = { try Self.inspect($0) }) async throws -> OriginalFileLocation {
        let location = try OriginalFileLocation(track: track, root: access?.url)
        let task = Task.detached {
            defer { withExtendedLifetime(access) {} }
            try Task.checkCancellation()
            try inspect(location.fileURL)
            try Task.checkCancellation()
        }
        try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
        try Task.checkCancellation()
        return location
    }
}

private struct FileLocationRequest: Identifiable {
    let id = UUID()
    let track: AudioTrack
    let access: FolderAccess?
}

struct OriginalFileLocationButton: View {
    let track: AudioTrack
    let access: FolderAccess?
    var compact = false
    @Environment(\.saptakTheme) private var theme
    @State private var request: FileLocationRequest?
    @State private var isPreparing = false
    @State private var error: String?
    #if os(iOS)
    @State private var fallback: OriginalFileLocation?
    @State private var fallbackAccess: FolderAccess?
    #endif

    private var title: String {
        #if os(macOS)
        return "Show in Finder"
        #else
        return "Show in Files"
        #endif
    }

    var body: some View {
        Button { request = FileLocationRequest(track: track, access: access) } label: {
            if compact { Image(systemName: "folder").font(.title3) }
            else { Label(isPreparing ? "Finding file…" : title, systemImage: "folder").labelStyle(.titleAndIcon) }
        }
        #if os(macOS)
        .buttonStyle(.plain)
        #else
        .buttonStyle(SaptakButtonStyle())
        #endif
        .font(SaptakTypography.text(compact ? .caption : .callout))
        .frame(minWidth: compact ? 44 : nil, minHeight: 44)
        .accessibilityLabel(title)
        .overlay {
            if compact {
                RoundedRectangle(cornerRadius: 12).stroke(SaptakTheme.cream, lineWidth: theme.borderWidth)
            }
        }
        .disabled(isPreparing)
        .help("Reveal the original audio file in its folder")
        .accessibilityHint("Opens the original location without exporting or moving the audio")
        .task(id: request?.id) {
            guard let request else { return }
            isPreparing = true
            defer { isPreparing = false; withExtendedLifetime(request.access) {} }
            do {
                let location = try await OriginalFileLocationAccess.prepare(track: request.track, access: request.access)
                try Task.checkCancellation()
                #if os(macOS)
                NSWorkspace.shared.activateFileViewerSelecting([location.fileURL])
                #else
                // Files and individual providers may reject this route. Offer a documented
                // system browser fallback rather than claiming that a reveal succeeded.
                let opened: Bool
                if let url = location.filesURL { opened = await UIApplication.shared.open(url) }
                else { opened = false }
                if !opened, !Task.isCancelled {
                    fallbackAccess = request.access
                    fallback = location
                }
                #endif
            } catch is CancellationError {
                // Closing the player cancels the request, not access held by playback.
            } catch {
                guard !Task.isCancelled else { return }
                self.error = "Could not locate the original file. It may have moved or its provider may be unavailable. Refresh the library and try again. \(error.localizedDescription)"
            }
        }
        .alert("File location unavailable", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
        #if os(iOS)
        .contextMenu {
            Button("File location…") { showOriginalLocation() }
        }
        .accessibilityAction(named: Text("View file location")) { showOriginalLocation() }
        .sheet(item: $fallback, onDismiss: { fallbackAccess = nil }) { location in
            FileLocationFallbackView(location: location, access: fallbackAccess)
        }
        #endif
    }

    #if os(iOS)
    private func showOriginalLocation() {
        do {
            let location = try OriginalFileLocation(track: track, root: access?.url)
            fallbackAccess = access
            fallback = location
        } catch { self.error = error.localizedDescription }
    }
    #endif
}

#if os(iOS)
private struct FileLocationFallbackView: View {
    let location: OriginalFileLocation
    // Retain the original root grant while the system browser is presented.
    let access: FolderAccess?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.saptakTheme) private var theme
    @State private var showBrowser = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(location.filename).saptakText(.section).textSelection(.enabled)
                    Label(location.folderDescription, systemImage: "folder").saptakText(.item)
                    Text("Find this original file in its folder. If Files cannot reveal it directly, browse below. Your provider may start in a different folder.")
                        .saptakText(.metadata).foregroundStyle(theme.secondaryText)
                    Button { showBrowser = true } label: { Label("Browse folder", systemImage: "folder") }
                        .buttonStyle(SaptakButtonStyle(prominent: true))
                    Button("Copy filename") { UIPasteboard.general.string = location.filename }
                        .buttonStyle(SaptakButtonStyle())
                    Text("Browsing does not replace your audio folder or change what is playing.")
                        .saptakText(.metadata).foregroundStyle(theme.secondaryText)
                }.padding(24)
            }
            .background(theme.background).foregroundStyle(theme.text)
            .navigationTitle("Original file location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() }.frame(minHeight: 44) }
            .sheet(isPresented: $showBrowser) { OriginalFolderBrowser(folder: location.folderURL, isPresented: $showBrowser) }
        }
    }
}

private struct OriginalFolderBrowser: UIViewControllerRepresentable {
    let folder: URL
    @Binding var isPresented: Bool

    func makeCoordinator() -> Coordinator { Coordinator { isPresented = false } }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: false)
        picker.directoryURL = folder
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        // This is only a location browser. Do not use selections as imports or library roots.
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let finish: () -> Void
        init(finish: @escaping () -> Void) { self.finish = finish }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { finish() }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { finish() }
    }
}
#endif
