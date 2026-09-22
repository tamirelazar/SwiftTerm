#if os(macOS)
import AppKit
import XCTest
@testable import SwiftTerm

@MainActor
final class SimpleFrameCoreGraphicsTests: XCTestCase {
    func testFallbackPreservesInteriorAndCoversExteriorOnEachRow() throws {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 240, height: 180))
        view.font = NSFont.monospacedSystemFont(ofSize: 16, weight: .regular)
        view.simpleFrameOuterBackground = .blue
        let escape = "\u{1b}"
        for (offset, text) in ["┌────┐", "│    │", "│    │", "└────┘"].enumerated() {
            view.feed(text: "\(escape)[\(offset + 2);3H\(escape)[38;2;0;255;0m\(escape)[48;2;255;0;0m\(text)")
        }
        let scale = view.backingScaleFactor()
        let width = Int(view.bounds.width * scale)
        let height = Int(view.bounds.height * scale)
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height,
                                             bitsPerComponent: 8, bytesPerRow: width * 4,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.scaleBy(x: scale, y: scale)
        view.drawTerminalContents(dirtyRect: view.bounds, context: context,
                                  bufferOffset: view.terminal.displayBuffer.yDisp)
        let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        func color(column: CGFloat, row: CGFloat) -> (UInt8, UInt8, UInt8) {
            let x = Int(column * view.cellDimension.width * scale)
            let y = Int(row * view.cellDimension.height * scale)
            let index = (y * width + x) * 4
            return (pixels[index], pixels[index + 1], pixels[index + 2])
        }
        // Border cells occupy columns 2...7, rows 1...4. Test both sides of
        // every rule without relying on the masking helper's coordinates.
        let outside: [(CGFloat, CGFloat)] = [
            (2.1, 1.1), (7.9, 1.1), (2.1, 4.9), (7.9, 4.9),
            (4, 1.1), (4, 4.9), (2.1, 2.5), (7.9, 2.5)
        ]
        for (column, row) in outside {
            let rgb = color(column: column, row: row)
            XCTAssertEqual(rgb.0, 0, "red spill at \(column),\(row)")
            XCTAssertEqual(rgb.2, 255, "missing exterior at \(column),\(row)")
        }
        let inside: [(CGFloat, CGFloat)] = [
            (2.9, 1.9), (7.1, 1.9), (2.9, 4.1), (7.1, 4.1),
            (4, 1.9), (4, 4.1), (2.9, 2.5), (7.1, 2.5)
        ]
        for (column, row) in inside {
            let rgb = color(column: column, row: row)
            XCTAssertEqual(rgb.0, 255, "interior lost at \(column),\(row)")
            XCTAssertEqual(rgb.2, 0, "exterior crossed border at \(column),\(row)")
        }
    }
}
#endif
