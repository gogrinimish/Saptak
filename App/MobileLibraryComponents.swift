import SwiftUI
import SaptakCore

/// Reserves the player's actual height before proposing space to the whole navigation stack.
struct PlayerDockLayout: Layout {
    struct Regions {
        let browser: CGRect
        let player: CGRect

        init(size: CGSize, playerHeight: CGFloat) {
            let width = max(0, size.width)
            let height = max(0, size.height)
            let dock = min(height, max(0, playerHeight))
            browser = CGRect(x: 0, y: 0, width: width, height: height - dock)
            player = CGRect(x: 0, y: height - dock, width: width, height: dock)
        }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? 390, height: proposal.height ?? 800)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let measured = subviews[1].sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
        let regions = Regions(size: bounds.size, playerHeight: measured.height)
        for (view, rect) in zip(subviews, [regions.browser, regions.player]) {
            view.place(at: CGPoint(x: bounds.minX + rect.minX, y: bounds.minY + rect.minY),
                       anchor: .topLeading, proposal: ProposedViewSize(rect.size))
        }
    }
}

struct FolderBreadcrumbs: View {
    let ancestors: [AudioFolder]
    let select: (URL) -> Void
    @Environment(\.saptakTheme) private var theme
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 44

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(ancestors.enumerated()), id: \.element.url) { index, folder in
                        if index > 0 {
                            Image(systemName: "chevron.right").font(.caption2)
                                .foregroundStyle(theme.secondaryText).accessibilityHidden(true)
                        }
                        Button { select(folder.url) } label: {
                            Text(folder.title).saptakText(.metadata)
                                .lineLimit(1).padding(.horizontal, 8).frame(minHeight: 44)
                        }
                        .buttonStyle(.plain).foregroundStyle(theme.accent)
                        .accessibilityLabel("Back to \(folder.title)")
                        .id(folder.url)
                    }
                }.padding(.horizontal, 8)
            }
            .onAppear { if let last = ancestors.last { proxy.scrollTo(last.url, anchor: .trailing) } }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Parent folders")
        .frame(height: rowHeight)
    }
}

/// One gutter for summary, folder and track rows, independent of icon/text alignment.
struct MobileLibraryRow: ViewModifier {
    @Environment(\.saptakTheme) private var theme

    @ViewBuilder func body(content: Content) -> some View {
        #if os(iOS)
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .overlay(alignment: .bottom) {
                Rectangle().fill(theme.outline.opacity(theme.increasedContrast ? 0.6 : 0.16))
                    .frame(height: theme.borderWidth).padding(.horizontal, 16)
                    .accessibilityHidden(true)
            }
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
        #else
        content
        #endif
    }
}
