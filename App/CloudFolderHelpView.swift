import SwiftUI

struct CloudFolderHint: View {
    @Environment(\.saptakTheme) private var theme

    var body: some View {
        #if os(iOS)
        Text("Choose a folder on your device, in iCloud Drive, or from another service available in Files.")
            .saptakText(.metadata).foregroundStyle(theme.secondaryText)
            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        #else
        Text("Choose a folder on your Mac, in iCloud Drive, or from another cloud service available in Finder.")
            .saptakText(.metadata).foregroundStyle(theme.secondaryText)
            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        #endif
    }
}

struct CloudFolderHelpView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.saptakTheme) private var theme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    section("Choose where your audio lives") {
                        #if os(iOS)
                        Text("The folder picker shows locations available through the Files app, including your device and iCloud Drive.")
                        #else
                        Text("The folder picker shows folders available through Finder, including your Mac and iCloud Drive.")
                        #endif
                    }
                    section("Add another cloud service") {
                        #if os(iOS)
                        Text("Install and sign in to your provider’s app, such as Dropbox, OneDrive or Google Drive. Then open Files → Browse → … → Edit and turn on that service under Locations.")
                        #else
                        Text("Install and sign in to your provider’s Mac app. If it makes a folder available in Finder, you can look for that folder in the picker.")
                        #endif
                        Text("A service must support folder selection and access to the audio inside it. Availability and behavior vary by provider.")
                    }
                    section("Downloads and your original files") {
                        Text("Cloud tracks may need an internet connection and may download to your device, using local storage. Downloaded availability is managed by the provider.")
                        Text("Saptak plays your selected files in place. It does not move them or permanently import them into a separate library.")
                    }
                }
                .padding(24).frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .foregroundStyle(theme.text)
            .background(theme.background)
            .navigationTitle("Using cloud folders")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { Button("Done") { dismiss() }.frame(minHeight: 44) }
        }
        .tint(theme.accent)
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 440)
        #endif
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(SaptakTypography.text(.headline)).accessibilityAddTraits(.isHeader)
            content().font(SaptakTypography.text(.body)).fixedSize(horizontal: false, vertical: true)
        }
    }
}
