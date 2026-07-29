import AppKit

/// A panel that stays above other applications' windows without stealing their
/// focus — the Google Meet pop-over behaviour.
///
/// Two details do the heavy lifting:
///  - `.nonactivatingPanel` + `NSApp.setActivationPolicy(.accessory)` means
///    clicking a button here does not deactivate Chrome.
///  - `.canJoinAllSpaces` + `.fullScreenAuxiliary` lets it ride over a
///    full-screen window instead of being left behind on another Space.
///
/// `.fullSizeContentView` makes the content view span the whole frame, so the
/// background material runs behind the titlebar too. The frame still reserves
/// 24pt for the titlebar, which is where the close button sits — the panel's top
/// row is deliberately left empty to make room for it.
public final class FloatingPanel: NSPanel {
    public init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [
                .nonactivatingPanel, .titled, .fullSizeContentView, .closable, .utilityWindow,
                .resizable,
            ],
            backing: .buffered,
            defer: false
        )

        // Horizontal only, in effect: the content's own height constraint pins the
        // vertical size, so a drag on the bottom edge springs back. Only the width
        // is bounded here; bounding the height would fight that constraint.
        contentMinSize = NSSize(width: 200, height: 0)
        contentMaxSize = NSSize(width: 640, height: 10_000)

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false

        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        animationBehavior = .utilityWindow

        // Deliberately NOT movable by window background. `NSHostingView` reports
        // mouseDownCanMoveWindow = true for its whole surface, and a plain SwiftUI
        // Image creates no AppKit view of its own, so AppKit would begin a window
        // drag on mouse-down and the agenda's reorder handles would never receive
        // it. Only real AppKit views (the TextFields) opt out on their own.
        // The titlebar strip remains a drag region, so the panel can still be moved.
        isMovableByWindowBackground = false

        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
    }

    /// Needed so the agenda's text fields can take keystrokes. A non-activating
    /// panel can be key while another app stays active, which is the point.
    public override var canBecomeKey: Bool { true }

    public override var canBecomeMain: Bool { false }
}
