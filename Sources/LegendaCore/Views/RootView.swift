import SwiftUI

public struct RootView: View {
    /// The width the panel opens at. No longer a constraint — the panel is
    /// horizontally resizable — so it lives here for the app and the render harness
    /// to agree on.
    static let defaultWidth: CGFloat = 232

    @ObservedObject var engine: MeetingEngine

    public init(engine: MeetingEngine) {
        self.engine = engine
    }

    public var body: some View {
        Group {
            if engine.phase == .setup {
                SetupView(engine: engine)
            } else {
                RunningView(engine: engine)
            }
        }
        .padding(.horizontal, 13)
        // The frame reserves 24pt for the titlebar and the content centres in it,
        // so ~12pt of inset comes for free at each end. These paddings add to
        // that: ~18pt above, tucking the header up beside the close button, and
        // ~24pt below.
        .padding(.top, 6)
        .padding(.bottom, 12)
        // Flexible width, fixed-by-content height. NSHostingView still drives the
        // panel's height from the content — which is what keeps the panel exactly as
        // tall as its agenda — while a flexible width lets the window be widened,
        // lengthening the title fields. A `minWidth` is essential: without one the
        // intrinsic width collapses to the content's bare minimum (~34pt).
        .frame(minWidth: 200, maxWidth: .infinity)
    }
}
