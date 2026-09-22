#if os(macOS)
import Foundation
import Testing
@testable import SwiftTerm

struct SimpleFrameDetectionTests {
    @Test func recognizesActualTslimeOutput() throws {
        // Captured from the bundled tslime in a 40x20 PTY, seed 7, Simple
        // frame, red inner / blue outer / green accent, after warmup.
        let (terminal, delegate) = TerminalTestHarness.makeTerminal(cols: 40, rows: 20)
        let fixture = try #require(Bundle.module.url(forResource: "simple-frame", withExtension: "ansi"))
        let text = try String(contentsOf: fixture, encoding: .utf8)
        withExtendedLifetime(delegate) {
            terminal.feed(text: text)
            #expect(SimpleFrameBounds.find(in: terminal.displayBuffer, rows: 0...19)
                    == SimpleFrameBounds(left: 2, right: 37, top: 3, bottom: 15))
        }
    }

    @Test func followsCompleteFrameAndRejectsBrokenEdges() {
        let (terminal, delegate) = TerminalTestHarness.makeTerminal(cols: 16, rows: 9)
        withExtendedLifetime(delegate) {
            func draw(left: Int, top: Int) {
                for (offset, text) in ["┌────┐", "│    │", "│    │", "└────┘"].enumerated() {
                    terminal.feed(text: "\u{1b}[\(top + offset + 1);\(left + 1)H\(text)")
                }
            }
            func find() -> SimpleFrameBounds? {
                SimpleFrameBounds.find(in: terminal.displayBuffer, rows: 0...8)
            }
            draw(left: 2, top: 1)
            #expect(find() == SimpleFrameBounds(left: 2, right: 7, top: 1, bottom: 4))
            // No mask while the lower edge is incomplete, including midway
            // through a resize/repaint of the source terminal application.
            terminal.feed(text: "\u{1b}[5;5H ")
            #expect(find() == nil)
            terminal.feed(text: "\u{1b}[2J")
            draw(left: 7, top: 4)
            #expect(find() == SimpleFrameBounds(left: 7, right: 12, top: 4, bottom: 7))
            terminal.feed(text: "\u{1b}[6;8H ")
            #expect(find() == nil)
            // Glow/block borders have no thin box to mask.
            terminal.feed(text: "\u{1b}[2J\u{1b}[1;1H██████\r\n█    █\r\n██████")
            #expect(find() == nil)
        }
    }

    @Test func requiresMatchingCornersAndSingleWidthRows() {
        let (terminal, delegate) = TerminalTestHarness.makeTerminal(cols: 12, rows: 5)
        withExtendedLifetime(delegate) {
            terminal.feed(text: "┌───┐\r\n│   │\r\n└───┘")
            #expect(SimpleFrameBounds.find(in: terminal.displayBuffer, rows: 0...4) != nil)
            terminal.feed(text: "\u{1b}[2;1H\u{1b}#6")
            #expect(SimpleFrameBounds.find(in: terminal.displayBuffer, rows: 0...4) == nil)
        }
    }
}
#endif
