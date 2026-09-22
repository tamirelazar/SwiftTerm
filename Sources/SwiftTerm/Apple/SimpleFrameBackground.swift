#if os(macOS) || os(iOS) || os(visionOS)
import CoreGraphics

/// A complete thin box in the displayed terminal buffer. Validation of all four
/// edges prevents partial output, resize debris or unrelated corner characters
/// from producing a mask across the simulation.
struct SimpleFrameBounds: Equatable {
    let left: Int
    let right: Int
    let top: Int
    let bottom: Int

    static func find(in buffer: Buffer, rows: ClosedRange<Int>) -> SimpleFrameBounds? {
        guard buffer.cols >= 3, rows.count >= 3 else { return nil }
        for top in rows.dropLast(2) where buffer.lines[top].renderMode == .single {
            let line = buffer.lines[top]
            for left in 0..<(buffer.cols - 2) where line[left].code == 0x250c {
                var right = left + 1
                while right < buffer.cols && line[right].code == 0x2500 { right += 1 }
                guard right > left + 1, right < buffer.cols,
                      line[right].code == 0x2510 else { continue }
                for bottom in (top + 1)...rows.upperBound {
                    let edge = buffer.lines[bottom]
                    guard edge.renderMode == .single else { break }
                    if edge[left].code == 0x2502 && edge[right].code == 0x2502 { continue }
                    if bottom > top + 1, edge[left].code == 0x2514,
                       edge[right].code == 0x2518,
                       ((left + 1)..<right).allSatisfy({ edge[$0].code == 0x2500 }) {
                        return SimpleFrameBounds(left: left, right: right, top: top, bottom: bottom)
                    }
                    break
                }
            }
        }
        return nil
    }
}

extension TerminalView {
    /// Four rectangles in device pixels, with the same bottom-left origin and
    /// rounded cell placement as the procedural box glyphs. Recomputed from the
    /// displayed buffer so a moved/resized frame never leaves a stale mask.
    func simpleFrameBackgroundRects(scale: CGFloat, firstRow: Int,
                                    lastRow: Int, yDisp: Int) -> [CGRect] {
        guard simpleFrameOuterBackground != nil, customBlockGlyphs,
              !antiAliasCustomBlockGlyphs, scale > 0, firstRow <= lastRow,
              let box = SimpleFrameBounds.find(in: terminal.displayBuffer,
                                               rows: firstRow...lastRow) else { return [] }
        let width = max(1, Int(round(cellDimension.width * scale)))
        let height = max(1, Int(round(cellDimension.height * scale)))
        let thickness = max(1, Int(round(scale)),
                            Int(round(scale * fontSet.underlineThickness() * 1.35)))
        let stroke = BoxDrawingRenderer.lightStrokeBounds(cellWidthPx: width,
                                                         cellHeightPx: height,
                                                         thicknessPx: thickness)
        func rowOrigin(_ row: Int) -> CGFloat {
            round((bounds.height - CGFloat(row - yDisp + 1) * cellDimension.height) * scale)
        }
        // Split beneath the opaque stroke. Integer splits keep the adjacent
        // background fills pixel aligned even when a stroke has odd thickness.
        let left = CGFloat(box.left * width) + floor(stroke.midX)
        let right = CGFloat(box.right * width) + floor(stroke.midX)
        let top = rowOrigin(box.top) + CGFloat(height) - floor(stroke.midY)
        let bottom = rowOrigin(box.bottom) + CGFloat(height) - floor(stroke.midY)
        let minX = floor(CGFloat(box.left) * cellDimension.width * scale)
        let maxX = ceil(CGFloat(box.right + 1) * cellDimension.width * scale)
        let minY = floor((bounds.height - CGFloat(box.bottom - yDisp + 1) * cellDimension.height) * scale)
        let maxY = ceil((bounds.height - CGFloat(box.top - yDisp) * cellDimension.height) * scale)
        return [CGRect(x: minX, y: top, width: maxX - minX, height: maxY - top),
                CGRect(x: minX, y: minY, width: maxX - minX, height: bottom - minY),
                CGRect(x: minX, y: bottom, width: left - minX, height: top - bottom),
                CGRect(x: right, y: bottom, width: maxX - right, height: top - bottom)]
            .filter { $0.width > 0 && $0.height > 0 }
    }
}
#endif
