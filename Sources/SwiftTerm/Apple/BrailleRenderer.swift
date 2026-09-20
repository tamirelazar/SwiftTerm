#if os(macOS) || os(iOS) || os(visionOS)
import CoreGraphics
import Foundation
#if os(iOS) || os(visionOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Plots the braille patterns U+2800...U+28FF as a 2x4 dot grid, the way
/// ``BlockElementMapping`` plots the block elements: the dots are geometry the
/// renderer draws, not glyphs a font supplies.
///
/// The grid fills the cell with no inset, which is the only arrangement that
/// tiles: the gap between the last dot column of one cell and the first of the
/// next is `(0.5 + inset)` cell widths against an intra-cell pitch of
/// `(0.5 - inset)`, so any inset above zero puts a visible seam at every cell
/// boundary. A font's braille glyph can only approximate that; here it holds by
/// construction.
public enum BrailleRenderer {
    static let lowerBoundary: UInt32 = 0x2800
    static let upperBoundary: UInt32 = 0x28FF

    /// Dot size as a fraction of the dot pitch, for a view that has not been
    /// configured. The geometry is per-view state on ``TerminalView``; these
    /// are only that property's initial value, so an unconfigured fork still
    /// draws the look this renderer was designed around.
    public static let defaultDotSizeFraction: CGFloat = 0.78

    /// Corner radius as a fraction of the dot size, for a view that has not
    /// been configured. The dots are rounded squares rather than circles,
    /// which keeps their weight up at small sizes.
    public static let defaultCornerFraction: CGFloat = 0.3

    static func shouldRender(codePoint: UInt32) -> Bool {
        codePoint >= lowerBoundary && codePoint <= upperBoundary
    }

    /// Dot bit (the U+2800 offset, 0...7) to its column and row in the 2x4
    /// grid, row 0 at the top.
    private static let layout: [(col: Int, row: Int)] = [
        (0, 0), (0, 1), (0, 2), (1, 0), (1, 1), (1, 2), (0, 3), (1, 3)
    ]

    /// Fills the cell's set dots with the context's current fill color. The
    /// context is expected to be y-up, matching the other custom glyph drawers.
    ///
    /// Both fractions are required rather than defaulted: every caller draws
    /// on behalf of a particular view, and a silent fallback here is how two
    /// copies of the same number start disagreeing. Neither is range-checked
    /// — what a sensible dot size is, is the embedder's policy, and a second
    /// opinion here would only diverge from it.
    static func draw(codePoint: UInt32,
                     in context: CGContext,
                     cellOrigin: CGPoint,
                     cellSize: CGSize,
                     dotSizeFraction: CGFloat,
                     cornerFraction: CGFloat) {
        guard shouldRender(codePoint: codePoint) else {
            return
        }
        let bits = codePoint - lowerBoundary
        guard bits != 0 else {
            return
        }
        let pitchX = cellSize.width / 2.0
        let pitchY = cellSize.height / 4.0
        let dotSize = min(pitchX, pitchY) * dotSizeFraction
        guard dotSize > 0 else {
            return
        }
        let corner = dotSize * cornerFraction
        for bit in 0..<8 where bits & (1 << UInt32(bit)) != 0 {
            let (col, row) = layout[bit]
            let centerX = cellOrigin.x + (CGFloat(col) + 0.5) * pitchX
            let centerY = cellOrigin.y + (CGFloat(3 - row) + 0.5) * pitchY
            let rect = CGRect(x: centerX - dotSize / 2,
                              y: centerY - dotSize / 2,
                              width: dotSize,
                              height: dotSize)
            context.addPath(CGPath(roundedRect: rect,
                                   cornerWidth: corner,
                                   cornerHeight: corner,
                                   transform: nil))
        }
        context.fillPath()
    }
}

struct BrailleRenderItem {
    let column: Int
    let columnWidth: Int
    let codePoint: UInt32
    let foregroundColor: TTColor
}
#endif
