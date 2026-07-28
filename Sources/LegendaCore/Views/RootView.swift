import SwiftUI

public struct RootView: View {
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
        // A declared width is essential: NSHostingView drives the panel's size
        // from its content, so without this the window collapses to fit.
        .frame(width: 232)
    }
}
