import SwiftUI

/// First launch is a single decision, without an empty browser or disabled player.
struct WelcomeView: View {
    var isLoading = false
    let chooseFolder: () -> Void
    var retry: (() -> Void)? = nil
    @Environment(\.saptakTheme) private var theme

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                WelcomeContent(isLoading: isLoading, chooseFolder: chooseFolder, retry: retry)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
        }
        .foregroundStyle(theme.text)
        .background(theme.background.ignoresSafeArea())
    }
}

/// Content is separate from scrolling so its intrinsic layout can be previewed directly.
struct WelcomeContent: View {
    var isLoading = false
    let chooseFolder: () -> Void
    var retry: (() -> Void)? = nil
    @Environment(\.saptakTheme) private var theme
    @State private var showCloudHelp = false
    @State private var showFontLicense = false

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                SaptakIcon().frame(width: 72, height: 72)
                SaptakWordmark()
            }
            Text("Open-source. MIT-licensed.").saptakText(.metadata)
                .foregroundStyle(theme.secondaryText)
            SaptakTagline()
                .foregroundStyle(theme.text)
            Text("Every folder is a playlist. Your files stay where they are.")
                .saptakText(.item)
                .multilineTextAlignment(.center)
                .foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if isLoading { ProgressView("Opening folder…").tint(theme.accent) }
            if !isLoading, let retry {
                Button("Retry folder access", action: retry)
                    .buttonStyle(SaptakButtonStyle())
                    .help("Try reading the selected folder again")
            }
            Button(action: chooseFolder) {
                Label(isLoading ? "Choose another folder…" : "Choose folder…", systemImage: "folder.badge.plus")
            }
            .buttonStyle(SaptakButtonStyle(prominent: true))
            .help("Choose a folder to play its audio files directly")
            .accessibilityHint("Each folder becomes a playlist, including its subfolders. Original files are not imported or moved.")
            VStack(spacing: 8) {
                CloudFolderHint()
                Button("Using cloud folders") { showCloudHelp = true }
                    .buttonStyle(.plain).font(SaptakTypography.text(.callout))
                    .foregroundStyle(theme.accent).frame(minHeight: 44)
                    .accessibilityHint("Explains cloud locations, provider setup and downloads")
                HStack(spacing: 20) {
                    Link("Privacy policy", destination: SaptakLinks.privacyPolicy)
                    Link("Support", destination: SaptakLinks.support)
                }
                .font(SaptakTypography.text(.caption))
                .frame(minHeight: 44)
                Button("Font license") { showFontLicense = true }
                    .font(SaptakTypography.text(.caption)).frame(minHeight: 44)
            }
        }
        .frame(maxWidth: 400)
        .padding(24)
        .sheet(isPresented: $showCloudHelp) { CloudFolderHelpView() }
        .sheet(isPresented: $showFontLicense) { FontLicenseView() }
    }
}
