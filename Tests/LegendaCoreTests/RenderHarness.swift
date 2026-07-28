import AppKit
import SwiftUI
import Testing

@testable import LegendaCore

/// Throwaway visual harness: renders the panel content offscreen to PNGs so the
/// layout can be eyeballed without Screen Recording permission.
@MainActor
@Suite("Render", .disabled(if: ProcessInfo.processInfo.environment["LEGENDA_RENDER"] == nil))
struct RenderHarness {

    private func render(_ engine: MeetingEngine, _ name: String, dark: Bool) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 232, height: 400),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)

        let backdrop = NSVisualEffectView()
        backdrop.material = .hudWindow
        backdrop.blendingMode = .withinWindow
        backdrop.state = .active
        backdrop.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)

        let host = NSHostingView(rootView: RootView(engine: engine))
        // Render at the panel's real frame height: AppKit reserves 24pt for the
        // titlebar on top of the content's intrinsic height, and the content is
        // laid out across the whole thing.
        let titlebarReservation: CGFloat = 24
        var size = host.fittingSize
        size.height += titlebarReservation
        host.frame = NSRect(origin: .zero, size: size)
        backdrop.frame = host.frame
        backdrop.addSubview(host)
        window.contentView = backdrop
        window.setContentSize(size)
        backdrop.layoutSubtreeIfNeeded()

        guard let rep = backdrop.bitmapImageRepForCachingDisplay(in: backdrop.bounds) else { return }
        backdrop.cacheDisplay(in: backdrop.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        let suffix = dark ? "dark" : "light"
        try? png.write(to: URL(fileURLWithPath: "/tmp/legenda-\(name)-\(suffix).png"))
        print("rendered \(name)-\(suffix) at \(size)")
    }

    private func engine(advance: Int, agenda: [(String, Int, Bool)]? = nil) -> MeetingEngine {
        let clock = FakeClock()
        let spec =
            agenda ?? [
                ("Intro", 2, false), ("Updates", 8, false),
                ("Discussion", 15, false), ("Buffer", 5, true),
            ]
        let items = spec.map { AgendaItem(title: $0.0, plannedSeconds: $0.1 * 60, isBuffer: $0.2) }
        let engine = MeetingEngine(items: items, now: clock.now)
        if advance >= 0 {
            engine.start()
            clock.advance(advance)
            engine.tick()
        }
        return engine
    }

    @Test func renderAll() {
        for dark in [true, false] {
            render(engine(advance: -1), "setup", dark: dark)
            render(engine(advance: 45), "running", dark: dark)
            render(engine(advance: 195), "overrun", dark: dark)

            // Slack fully exhausted: 2 min budget blown by 6 against 5 of buffer.
            render(engine(advance: 120 + 360), "overtime", dark: dark)

            let paused = engine(advance: 45)
            paused.togglePause()
            render(paused, "paused", dark: dark)

            let done = engine(advance: 60, agenda: [("Standup", 1, false)])
            done.next()
            render(done, "finished", dark: dark)
        }
    }
}
