import AppKit
import Testing

@testable import LegendaCore

/// Guards the panel's configuration. Several of these were arrived at the hard way
/// and are invisible in normal use until they break.
@MainActor
@Suite("Floating panel")
struct FloatingPanelTests {

    private func panel() -> FloatingPanel {
        FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 267, height: 283))
    }

    @Test("Resizable, with the width bounded and the height left to the content")
    func resizableWidthOnly() {
        let subject = panel()
        #expect(subject.styleMask.contains(.resizable))
        #expect(subject.contentMinSize.width == 200)
        #expect(subject.contentMaxSize.width == 640)
        // Height is governed by the content's own constraint, so bounding it here
        // would fight that. A bottom-edge drag springs back instead.
        #expect(subject.contentMinSize.height == 0)
        #expect(subject.contentMaxSize.height >= 10_000)
    }

    @Test("Not movable by its background, or the reorder handles never see the drag")
    func notMovableByBackground() {
        // NSHostingView reports mouseDownCanMoveWindow = true across its whole
        // surface, so with this on, AppKit starts a window drag on mouse-down and
        // SwiftUI's .draggable is never consulted.
        #expect(!panel().isMovableByWindowBackground)
        // Still movable by the titlebar strip.
        #expect(panel().isMovable)
    }

    @Test("Floats over other apps without stealing their focus")
    func floatsWithoutActivating() {
        let subject = panel()
        #expect(subject.level == .floating)
        #expect(subject.styleMask.contains(.nonactivatingPanel))
        #expect(subject.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(subject.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(!subject.hidesOnDeactivate)
        // Needed so the agenda's text fields can take keystrokes.
        #expect(subject.canBecomeKey)
        #expect(!subject.canBecomeMain)
    }
}
