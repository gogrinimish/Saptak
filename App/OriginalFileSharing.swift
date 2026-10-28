import SwiftUI
import UniformTypeIdentifiers
import SaptakCore

struct OriginalAudioFile: Transferable {
    let url: URL
    let access: FolderAccess?
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .audio) { file in
            // The OS may make a temporary export for the explicitly requested share.
            SentTransferredFile(file.url)
        }
    }
}

@MainActor final class OriginalFileShareModel: ObservableObject {
    @Published private(set) var url: URL?
    @Published private(set) var error: String?
    let access: FolderAccess?

    init(access: FolderAccess?) { self.access = access }

    func prepare(_ track: AudioTrack,
                 using prepare: @escaping @Sendable (URL) async throws -> URL = { try await ProviderAccess.prepare($0) }) async {
        url = nil
        error = nil
        let retainedAccess = access
        let task = Task.detached {
            defer { withExtendedLifetime(retainedAccess) {} }
            return try await prepare(track.url)
        }
        do {
            let prepared = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            try Task.checkCancellation()
            url = prepared
        } catch is CancellationError {
            // Dismissing the share panel cancels presentation, not file permissions in use elsewhere.
        } catch {
            guard !Task.isCancelled else { return }
            self.error = "Could not prepare this file for sharing. \(error.localizedDescription)"
        }
    }
}

private struct OriginalFileShareView: View {
    let track: AudioTrack
    @StateObject var model: OriginalFileShareModel
    @State private var retry = 0
    @Environment(\.dismiss) private var dismiss
    @Environment(\.saptakTheme) private var theme

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text(track.title).saptakText(.section).multilineTextAlignment(.center)
                if let url = model.url {
                    ShareLink(item: OriginalAudioFile(url: url, access: model.access), preview: SharePreview(track.title)) {
                        Label("Share original file", systemImage: "square.and.arrow.up")
                    }.buttonStyle(SaptakButtonStyle(prominent: true))
                    Text("Shares the audio file, not a link to your library. Your original stays where it is.")
                        .saptakText(.metadata).foregroundStyle(theme.secondaryText)
                } else if let error = model.error {
                    Text(error).foregroundStyle(theme.secondaryText)
                    Button("Retry") { retry += 1 }.buttonStyle(SaptakButtonStyle())
                } else {
                    ProgressView("Preparing audio file…")
                    Text("Cloud files may need to download before sharing.")
                        .saptakText(.metadata).foregroundStyle(theme.secondaryText)
                }
            }
            .multilineTextAlignment(.center).padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.background).foregroundStyle(theme.text)
            .navigationTitle("Share original file")
            .toolbar { Button("Done") { dismiss() }.frame(minHeight: 44) }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 300)
        #endif
        .task(id: retry) { await model.prepare(track) }
    }
}

private struct OriginalFileSharing: ViewModifier {
    let track: AudioTrack
    let access: FolderAccess?
    @State private var presented = false

    func body(content: Content) -> some View {
        content.contextMenu {
            Button { presented = true } label: { Label("Share original file…", systemImage: "square.and.arrow.up") }
        }
        .accessibilityAction(named: Text("Share original file")) { presented = true }
        .sheet(isPresented: $presented) {
            OriginalFileShareView(track: track, model: OriginalFileShareModel(access: access))
        }
    }
}

extension View {
    func originalFileSharing(track: AudioTrack, access: FolderAccess?) -> some View {
        modifier(OriginalFileSharing(track: track, access: access))
    }
}

struct OriginalFileShareButton: View {
    let track: AudioTrack
    let access: FolderAccess?
    @State private var presented = false

    var body: some View {
        Button { presented = true } label: {
            Label("Share original file…", systemImage: "square.and.arrow.up")
        }
        .buttonStyle(SaptakButtonStyle())
        .sheet(isPresented: $presented) {
            OriginalFileShareView(track: track, model: OriginalFileShareModel(access: access))
        }
    }
}
