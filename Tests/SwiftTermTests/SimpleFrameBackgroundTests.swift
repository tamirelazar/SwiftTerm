#if os(macOS) && DEBUG
import AppKit
import Foundation
import CoreText
import Metal
import MetalKit
import XCTest

@testable import SwiftTerm

@MainActor
final class SimpleFrameBackgroundTests: XCTestCase {
    fileprivate enum RGB {
        case red, green, blue
    }

    func testMetalFrameExteriorMasksCoverAllSidesInBothBufferingModes() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal is unavailable")
        }

        var configurations: [(NSFont, CGFloat)] = [1, 2, 3].map {
            (NSFont.monospacedSystemFont(ofSize: 16, weight: .regular), CGFloat($0))
        }
        if let directory = ProcessInfo.processInfo.environment["SWIFTTERM_FRAME_FONTS_DIR"] {
            for (file, name) in [("JuliaMono-Bold.ttf", "JuliaMono-Bold"),
                                 ("JetBrainsMonoNerdFontMono-Regular.ttf", "JetBrainsMonoNFM-Regular")] {
                let url = URL(fileURLWithPath: directory).appendingPathComponent(file)
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
                configurations.append((try XCTUnwrap(NSFont(name: name, size: 16)), 2))
            }
        }
        for (font, scale) in configurations {
            for mode in [MetalBufferingMode.perRowPersistent, .perFrameAggregated] {
                let fixture = try makeFixture(device: device, bufferingMode: mode, font: font, scale: scale)
                let bitmap = try Bitmap(texture: fixture.renderer.renderOffscreenForTesting(scale: fixture.scale))
                if case .perFrameAggregated = mode, scale == 2,
                   font.fontName == NSFont.monospacedSystemFont(ofSize: 16, weight: .regular).fontName,
                   let path = ProcessInfo.processInfo.environment["SWIFTTERM_SIMPLE_FRAME_PNG"] {
                    try bitmap.writePNG(to: URL(fileURLWithPath: path))
                }

                // These are the outer quarters of the frame's red background cells.
                // They must instead show the blue field outside the visible rule.
                XCTAssertEqual(fixture.maskRects.count, 4)
                for (index, point) in fixture.cornerExterior.enumerated() {
                    XCTAssertTrue(bitmap.isColor(.blue, at: point.x, y: point.y),
                                  "corner exterior \(index) was not blue in \(mode)")
                }
                for (index, point) in fixture.cornerInterior.enumerated() {
                    XCTAssertTrue(bitmap.isColor(.red, at: point.x, y: point.y),
                                  "corner interior \(index) was not red in \(mode)")
                }
                for (index, probe) in fixture.edgeProbes.enumerated() {
                    XCTAssertTrue(bitmap.isColor(.blue, at: probe.exterior.x, y: probe.exterior.y),
                                  "edge exterior \(index) was not blue in \(mode)")
                    XCTAssertTrue(bitmap.isColor(.red, at: probe.interior.x, y: probe.interior.y),
                                  "edge interior \(index) was not red in \(mode)")
                }

                // Require a visible green rule at every edge, rather than merely
                // proving that the masks changed the cell fills.
                for (index, point) in fixture.strokePoints.enumerated() {
                    XCTAssertTrue(bitmap.hasColor(.green, near: point, radius: 2),
                                  "frame stroke \(index) disappeared in \(mode)")
                }
            }
        }
    }

    private func makeFixture(device: MTLDevice,
                             bufferingMode: MetalBufferingMode,
                             font: NSFont, scale: CGFloat) throws -> Fixture {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 240, height: 180))
        view.font = font
        view.nativeBackgroundColor = .blue
        view.nativeForegroundColor = .white
        view.metalBufferingMode = bufferingMode
        view.metalScaleFactorOverride = scale
        view.simpleFrameOuterBackground = .blue

        // A non-zero-origin, complete 5×4 frame. Border and interior cells
        // are red, rules green and the field blue, so each layer is
        // independently observable after the Metal readback.
        let esc = "\u{1b}"
        func write(_ row: Int, _ column: Int, foreground: String, background: String, _ text: String) {
            view.feed(text: "\(esc)[\(row);\(column)H\(esc)[38;2;\(foreground)m\(esc)[48;2;\(background)m\(text)\(esc)[0m")
        }
        view.feed(text: "\(esc)[?25l")
        write(3, 4, foreground: "0;255;0", background: "255;0;0", "┌───┐")
        write(4, 4, foreground: "0;255;0", background: "255;0;0", "│")
        write(4, 5, foreground: "255;0;0", background: "255;0;0", "   ")
        write(4, 8, foreground: "0;255;0", background: "255;0;0", "│")
        write(5, 4, foreground: "0;255;0", background: "255;0;0", "│")
        write(5, 5, foreground: "255;0;0", background: "255;0;0", "   ")
        write(5, 8, foreground: "0;255;0", background: "255;0;0", "│")
        write(6, 4, foreground: "0;255;0", background: "255;0;0", "└───┘")

        let metalView = MTKView(frame: view.bounds, device: device)
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.drawableSize = CGSize(width: view.bounds.width * scale, height: view.bounds.height * scale)
        let renderer = try MetalTerminalRenderer(view: metalView, terminalView: view)

        let buffer = view.terminal.displayBuffer
        let firstRow = buffer.yDisp
        let lastRow = min(buffer.lines.count - 1, buffer.yDisp + buffer.rows - 1)
        let maskRects = view.simpleFrameBackgroundRects(scale: scale,
                                                        firstRow: firstRow,
                                                        lastRow: lastRow,
                                                        yDisp: buffer.yDisp)
        XCTAssertEqual(maskRects.count, 4, "fixture frame was not detected")

        let cellWidth = CGFloat(max(1, Int(round(view.cellDimension.width * scale))))
        let cellHeight = CGFloat(max(1, Int(round(view.cellDimension.height * scale))))
        let left = 3 * cellWidth
        let top = view.bounds.height * scale - 2 * cellHeight
        let bottom = top - 4 * cellHeight
        func cellPoint(column: Int, row: Int, x: CGFloat, y: CGFloat) -> CGPoint {
            CGPoint(x: CGFloat(column) * cellWidth + x * cellWidth,
                    y: view.bounds.height * scale - CGFloat(row) * cellHeight - y * cellHeight)
        }
        // Each corner has two outer quarters covered by the horizontal mask
        // and one inward quarter that must retain its red cell background.
        let cornerExterior = [
            cellPoint(column: 3, row: 2, x: 0.25, y: 0.25),
            cellPoint(column: 3, row: 2, x: 0.75, y: 0.25),
            cellPoint(column: 7, row: 2, x: 0.25, y: 0.25),
            cellPoint(column: 7, row: 2, x: 0.75, y: 0.25),
            cellPoint(column: 3, row: 5, x: 0.25, y: 0.75),
            cellPoint(column: 3, row: 5, x: 0.75, y: 0.75),
            cellPoint(column: 7, row: 5, x: 0.25, y: 0.75),
            cellPoint(column: 7, row: 5, x: 0.75, y: 0.75),
            cellPoint(column: 3, row: 2, x: 0.25, y: 0.75),
            cellPoint(column: 7, row: 2, x: 0.75, y: 0.75),
            cellPoint(column: 3, row: 5, x: 0.25, y: 0.25),
            cellPoint(column: 7, row: 5, x: 0.75, y: 0.25),
        ]
        let cornerInterior = [
            cellPoint(column: 3, row: 2, x: 0.75, y: 0.75),
            cellPoint(column: 7, row: 2, x: 0.25, y: 0.75),
            cellPoint(column: 3, row: 5, x: 0.75, y: 0.25),
            cellPoint(column: 7, row: 5, x: 0.25, y: 0.25),
        ]
        let edgeProbes = [
            EdgeProbe(exterior: cellPoint(column: 5, row: 2, x: 0.5, y: 0.25), interior: cellPoint(column: 5, row: 2, x: 0.5, y: 0.75)),
            EdgeProbe(exterior: cellPoint(column: 5, row: 5, x: 0.5, y: 0.75), interior: cellPoint(column: 5, row: 5, x: 0.5, y: 0.25)),
            EdgeProbe(exterior: cellPoint(column: 3, row: 4, x: 0.25, y: 0.5), interior: cellPoint(column: 3, row: 4, x: 0.75, y: 0.5)),
            EdgeProbe(exterior: cellPoint(column: 7, row: 4, x: 0.75, y: 0.5), interior: cellPoint(column: 7, row: 4, x: 0.25, y: 0.5)),
        ]
        let strokePoints = [
            CGPoint(x: left + 2.5 * cellWidth, y: maskRects[0].minY),
            CGPoint(x: left + 2.5 * cellWidth, y: maskRects[1].maxY),
            CGPoint(x: maskRects[2].maxX, y: bottom + 2 * cellHeight),
            CGPoint(x: maskRects[3].minX, y: bottom + 2 * cellHeight),
        ]
        return Fixture(view: view, metalView: metalView, renderer: renderer, scale: scale,
                       maskRects: maskRects, cornerExterior: cornerExterior,
                       cornerInterior: cornerInterior, edgeProbes: edgeProbes,
                       strokePoints: strokePoints)
    }
}

private struct Fixture {
    // MetalTerminalRenderer intentionally owns these weakly in production.
    // The fixture retains both while XCTest asks it to build and render.
    let view: TerminalView
    let metalView: MTKView
    let renderer: MetalTerminalRenderer
    let scale: CGFloat
    let maskRects: [CGRect]
    let cornerExterior: [CGPoint]
    let cornerInterior: [CGPoint]
    let edgeProbes: [EdgeProbe]
    let strokePoints: [CGPoint]
}

private struct EdgeProbe {
    let exterior: CGPoint
    let interior: CGPoint
}

private struct Bitmap {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    init(texture: MTLTexture) throws {
        width = texture.width
        height = texture.height
        var output = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&output, bytesPerRow: width * 4,
                         from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        bytes = output
    }

    func isColor(_ expected: SimpleFrameBackgroundTests.RGB, at x: CGFloat, y: CGFloat) -> Bool {
        let pixel = color(at: x, y: y)
        switch expected {
        case .red: return pixel.r > 200 && pixel.g < 55 && pixel.b < 55
        case .green: return pixel.g > 180 && pixel.r < 70 && pixel.b < 70
        case .blue: return pixel.b > 200 && pixel.r < 55 && pixel.g < 55
        }
    }

    func hasColor(_ expected: SimpleFrameBackgroundTests.RGB, near point: CGPoint, radius: Int) -> Bool {
        for y in (Int(point.y) - radius)...(Int(point.y) + radius) {
            for x in (Int(point.x) - radius)...(Int(point.x) + radius)
            where x >= 0 && x < width && y >= 0 && y < height {
                if isColor(expected, at: CGFloat(x), y: CGFloat(y)) { return true }
            }
        }
        return false
    }

    private func color(at x: CGFloat, y: CGFloat) -> (r: UInt8, g: UInt8, b: UInt8) {
        let xx = min(max(Int(x.rounded()), 0), width - 1)
        let yy = height - 1 - min(max(Int(y.rounded()), 0), height - 1)
        let offset = (yy * width + xx) * 4
        return (bytes[offset + 2], bytes[offset + 1], bytes[offset]) // BGRA8
    }

    func writePNG(to url: URL) throws {
        let data = Data(bytes)
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(width: width, height: height,
                                  bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: width * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
                                      .union(.byteOrder32Little),
                                  provider: provider, decode: nil,
                                  shouldInterpolate: false, intent: .defaultIntent),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try png.write(to: url)
    }
}
#endif
