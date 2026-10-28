import SwiftUI
import CoreText
#if os(iOS)
import UIKit
#endif


/// Public help pages; opening them is always an explicit user action.
enum SaptakLinks {
    static let privacyPolicy = URL(string: "https://gogrinimish.github.io/Saptak/privacy.html")!
    static let support = URL(string: "https://gogrinimish.github.io/Saptak/support.html")!
}

/// One real Regular face. No synthesized weights; semantic text still scales.
enum SaptakTypography {
    static let fontName = "Alice-Regular"

    static var resourceBundle: Bundle {
        #if SWIFT_PACKAGE
        return .module
        #else
        return .main
        #endif
    }

    static var fontURL: URL? {
        resourceBundle.url(forResource: "Alice-Regular", withExtension: "ttf", subdirectory: "Fonts")
    }

    static let isAvailable: Bool = {
        guard let url = fontURL else { return false }
        // Info.plist also registers this face in app builds. Duplicate registration is harmless.
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        let font = CTFontCreateWithName(fontName as CFString, 17, nil)
        return CTFontCopyPostScriptName(font) as String == fontName
    }()

    static func baseSize(_ style: Font.TextStyle) -> CGFloat {
        #if os(macOS)
        switch style {
        case .largeTitle: return 34
        case .title: return 28
        case .title2: return 24
        case .title3: return 20
        case .headline, .body: return 15
        case .subheadline: return 14
        case .callout: return 13
        case .footnote, .caption: return 12
        case .caption2: return 11
        @unknown default: return 15
        }
        #else
        switch style {
        case .largeTitle: return 34
        case .title: return 28
        case .title2: return 22
        case .title3: return 20
        case .headline, .body: return 17
        case .subheadline: return 15
        case .callout: return 16
        case .footnote: return 13
        case .caption: return 12
        case .caption2: return 11
        @unknown default: return 17
        }
        #endif
    }

    static func text(_ style: Font.TextStyle) -> Font {
        guard isAvailable else { return .system(style, design: .serif) }
        return .custom(fontName, size: baseSize(style), relativeTo: style)
    }

    static func scaled(_ size: CGFloat) -> Font {
        guard isAvailable else { return .system(size: size, design: .serif) }
        return .custom(fontName, fixedSize: size)
    }

    #if os(iOS)
    @MainActor static func configureNavigationAppearance() {
        guard isAvailable, let title = UIFont(name: fontName, size: 17),
              let largeTitle = UIFont(name: fontName, size: 34) else { return }
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.titleTextAttributes = [.font: UIFontMetrics(forTextStyle: .headline)
            .scaledFont(for: title)]
        appearance.largeTitleTextAttributes = [.font: UIFontMetrics(forTextStyle: .largeTitle)
            .scaledFont(for: largeTitle)]
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
    }
    #endif
}

struct FontLicenseView: View {
    @Environment(\.dismiss) private var dismiss
    private var license: String {
        guard let url = SaptakTypography.resourceBundle.url(forResource: "OFL", withExtension: "txt", subdirectory: "Fonts"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "Alice is licensed under the SIL Open Font License 1.1."
        }
        return text
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(license).font(SaptakTypography.text(.body)).textSelection(.enabled)
                    .frame(maxWidth: 700, alignment: .leading).padding(24)
            }
            .navigationTitle("Font license")
            .toolbar { Button("Done") { dismiss() } }
        }
        .font(SaptakTypography.text(.body))
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 400)
        #endif
    }
}

struct SaptakTheme {
    var dark = false
    var increasedContrast = false

    static let plum = Color(hex: 0x54244F)
    static let rose = Color(hex: 0xE8A6BC)
    static let olive = Color(hex: 0xB9BF8A)
    static let deepInk = Color(hex: 0x30212F)
    static let cream = Color(hex: 0xF9ECD9)
    static let iconBackground = rose

    var background: Color { dark ? Color(hex: 0x261C29) : Color(hex: 0xFBF5E9) }
    var secondarySurface: Color { dark ? Color(hex: 0x35243B) : Color(hex: 0xF3D7B6) }
    var text: Color { dark ? Self.cream : (increasedContrast ? .black : Self.deepInk) }
    var secondaryText: Color { dark ? Color(hex: 0xDDCED8) : Color(hex: 0x695466) }
    var outline: Color { dark ? Color(hex: 0xD0B7CA) : Color(hex: 0x492043) }
    var accent: Color { dark ? Self.rose : Color(hex: 0x492043) }
    var borderWidth: CGFloat { increasedContrast ? 2 : 1 }
}

private struct SaptakThemeKey: EnvironmentKey {
    static let defaultValue = SaptakTheme()
}

extension EnvironmentValues {
    var saptakTheme: SaptakTheme {
        get { self[SaptakThemeKey.self] }
        set { self[SaptakThemeKey.self] = newValue }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255,
                  green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1)
    }
}

struct SaptakRootView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let theme = SaptakTheme(dark: colorScheme == .dark, increasedContrast: contrast == .increased)
        LibraryView()
            .font(SaptakTypography.text(.body))
            .environment(\.saptakTheme, theme)
            .tint(theme.accent)
    }
}

struct SaptakButtonStyle: ButtonStyle {
    @Environment(\.saptakTheme) private var theme
    @Environment(\.isEnabled) private var enabled
    var prominent = false
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SaptakTypography.text(compact ? .callout : .body))
            .padding(.horizontal, compact ? 12 : 14)
            .frame(minHeight: compact ? 32 : 44)
            .foregroundStyle(enabled ? (prominent ? SaptakTheme.deepInk : theme.text) : theme.secondaryText)
            .background(prominent && enabled ? SaptakTheme.rose : theme.background,
                        in: RoundedRectangle(cornerRadius: 11))
            .overlay {
                RoundedRectangle(cornerRadius: 11)
                    .stroke(theme.outline, lineWidth: configuration.isPressed ? 3 : theme.borderWidth)
            }
    }
}

/// Vector identity remains sharp at text-accessibility and window scaling sizes.
struct SaptakMark: View {
    var color = SaptakTheme.plum

    var body: some View {
        SoundMarkShape().fill(color)
        .accessibilityHidden(true)
    }
}

/// Center the visible artwork bounds, rather than the unoccupied drawing canvas.
private struct SoundMarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 72
        let origin = CGPoint(x: rect.midX - 33 * scale, y: rect.midY - 37 * scale)
        var path = Path()
        for (index, height) in [18.0, 30, 44, 62, 46, 32, 20].enumerated() {
            let bar = CGRect(x: origin.x + CGFloat(index * 10) * scale,
                             y: origin.y + (68 - height) * scale,
                             width: 5.5 * scale, height: height * scale)
            path.addRoundedRect(in: bar, cornerSize: CGSize(width: 2.75 * scale, height: 2.75 * scale))
        }
        path.addEllipse(in: CGRect(x: origin.x + 58 * scale, y: origin.y + 10 * scale,
                                   width: 8 * scale, height: 8 * scale))
        return path
    }
}

/// The same licensed wordmark face is used by the app and product website.
struct SaptakWordmark: View {
    var style: Font.TextStyle = .title

    var body: some View {
        Text("Saptak")
            .font(SaptakTypography.text(style))
            .tracking(0.5)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Shared brand tagline at a subordinate semantic text size.
struct SaptakTagline: View {
    var body: some View {
        Text("Your audio. Yours to play.")
            .font(SaptakTypography.text(.title3))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct SaptakIcon: View {
    var markInset: CGFloat = 9
    var cornerRadius: CGFloat = 12

    var body: some View {
        SaptakMark()
            .padding(markInset)
            .background(SaptakTheme.iconBackground, in: RoundedRectangle(cornerRadius: cornerRadius))
            .accessibilityHidden(true)
    }
}

/// Shared scale for navigation, track rows and metadata.
enum SaptakTextRole {
    case paneTitle, item, metadata, count, section

    var style: Font.TextStyle {
        switch self {
        case .paneTitle: return .title2
        case .item: return .body
        case .metadata: return .callout
        case .count: return .caption
        case .section: return .headline
        }
    }

    var baseSize: CGFloat {
        #if os(macOS)
        switch self {
        case .paneTitle: return 24
        case .item: return 15
        case .metadata, .count: return 13
        case .section: return 14
        }
        #else
        switch self {
        case .paneTitle: return 28
        case .item: return 17
        case .metadata: return 15
        case .count: return 13
        case .section: return 17
        }
        #endif
    }
}

private struct SaptakTextModifier: ViewModifier {
    @ScaledMetric private var size: CGFloat

    init(role: SaptakTextRole) {
        _size = ScaledMetric(wrappedValue: role.baseSize, relativeTo: role.style)
    }

    func body(content: Content) -> some View {
        content.font(SaptakTypography.scaled(size))
    }
}

extension View {
    func saptakText(_ role: SaptakTextRole) -> some View {
        modifier(SaptakTextModifier(role: role))
    }
}
