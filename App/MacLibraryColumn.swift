#if os(macOS)
import SwiftUI

/// A bounded window column: the scrolling middle never supplies the window's height.
struct MacLibraryColumn: Layout {
    struct Regions {
        let header: CGRect
        let content: CGRect
        let footer: CGRect

        init(size: CGSize, headerHeight: CGFloat, footerHeight: CGFloat) {
            let width = max(0, size.width)
            let height = max(0, size.height)
            let header = min(max(0, headerHeight), height)
            let footer = min(max(0, footerHeight), height - header)
            self.header = CGRect(x: 0, y: 0, width: width, height: header)
            content = CGRect(x: 0, y: header, width: width, height: height - header - footer)
            self.footer = CGRect(x: 0, y: height - footer, width: width, height: footer)
        }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // Split-view ideal-size queries must not expand to a List's full contents.
        CGSize(width: proposal.width ?? 400, height: proposal.height ?? 520)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        let measure = ProposedViewSize(width: bounds.width, height: nil)
        let regions = Regions(size: bounds.size,
                              headerHeight: subviews[0].sizeThatFits(measure).height,
                              footerHeight: subviews[2].sizeThatFits(measure).height)
        for (view, rect) in zip(subviews, [regions.header, regions.content, regions.footer]) {
            view.place(at: CGPoint(x: bounds.minX + rect.minX, y: bounds.minY + rect.minY),
                       anchor: .topLeading, proposal: ProposedViewSize(rect.size))
        }
    }
}
#endif
