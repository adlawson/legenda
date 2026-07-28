import AppKit
import Combine
import SwiftUI

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = AgendaStore()
    private let sounds = SoundPlayer()
    private lazy var engine = MeetingEngine(items: store.load())

    private var statusItem: NSStatusItem?
    private var panel: FloatingPanel?
    private var ticker: Timer?
    private var saveSubscription: AnyCancellable?

    /// The panel is sized by its content, and AppKit anchors windows by their
    /// bottom-left. Without pinning, the panel would appear to crawl up the
    /// screen every time the agenda list collapsed on Start.
    private var pinnedTopLeft: CGPoint?
    private var isAdjustingFrame = false

    public override init() { super.init() }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        makeStatusItem()
        makePanel()
        startTicking()

        // `items` is only ever mutated on the main actor, so this publisher fires
        // there too; `assumeIsolated` traps loudly rather than quietly racing if
        // that ever stops being true.
        saveSubscription = engine.$items.sink { [weak self] items in
            MainActor.assumeIsolated {
                self?.store.save(items)
            }
        }

        showPanel()
        refreshStatusItem()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        store.save(engine.items)
        ticker?.invalidate()
    }

    // MARK: - Tick

    private func startTicking() {
        // `.common` so the clock keeps running while a menu is open or the panel
        // is being dragged.
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func tick() {
        engine.tick()
        for cue in engine.consumeCues() {
            sounds.play(cue)
        }
        refreshStatusItem()
    }

    // MARK: - Menubar

    private func makeStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.imagePosition = .imageLeading
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
    }

    private func refreshStatusItem() {
        guard let button = statusItem?.button else { return }

        let symbol: String
        switch engine.phase {
        case .setup: symbol = "timer"
        case .running: symbol = engine.isOvertime ? "exclamationmark.triangle.fill" : "timer"
        case .paused: symbol = "pause.fill"
        case .finished: symbol = "checkmark"
        }
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Legenda")

        // Idle states show the symbol alone; the time and item name only earn
        // menubar space while a meeting is actually running.
        let text: String
        switch engine.phase {
        case .setup:
            text = ""
        case .running, .paused:
            if let current = engine.currentItem {
                text = " \(engine.spent(current).clockString) · \(shortened(currentTitle(current)))"
            } else {
                text = ""
            }
        case .finished:
            text = " \(engine.totalSpent.clockString)"
        }

        // Attributed so the time can go red without tinting the whole menubar.
        button.attributedTitle = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular),
                .foregroundColor: engine.isOvertime ? NSColor.systemRed : NSColor.labelColor,
            ])
    }

    private func currentTitle(_ item: AgendaItem) -> String {
        item.title.isEmpty ? "Item \(engine.currentIndex + 1)" : item.title
    }

    private func shortened(_ title: String) -> String {
        title.count <= 18 ? title : String(title.prefix(17)) + "…"
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            presentMenu()
        } else {
            togglePanel()
        }
    }

    private func presentMenu() {
        let menu = NSMenu()

        let toggle = NSMenuItem(
            title: (panel?.isVisible ?? false) ? "Hide Legenda" : "Show Legenda",
            action: #selector(togglePanelFromMenu), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)

        if engine.phase != .setup {
            let pause = NSMenuItem(
                title: engine.phase == .paused ? "Resume" : "Pause",
                action: #selector(pauseFromMenu), keyEquivalent: "")
            pause.target = self
            pause.isEnabled = engine.phase != .finished
            menu.addItem(pause)

            let reset = NSMenuItem(
                title: "Reset to Agenda", action: #selector(resetFromMenu), keyEquivalent: "")
            reset.target = self
            menu.addItem(reset)
        }

        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(
                title: "Quit Legenda", action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"))

        // Attaching, clicking, then detaching is the standard way to show a menu
        // for a status item that also handles plain clicks.
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func togglePanelFromMenu() { togglePanel() }

    @objc private func pauseFromMenu() {
        engine.togglePause()
        refreshStatusItem()
    }

    @objc private func resetFromMenu() {
        engine.reset()
        refreshStatusItem()
        showPanel()
    }

    // MARK: - Panel

    private func makePanel() {
        let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 258, height: 300))

        let backdrop = NSVisualEffectView()
        backdrop.material = .hudWindow
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active

        let host = NSHostingView(rootView: RootView(engine: engine))
        host.translatesAutoresizingMaskIntoConstraints = false
        backdrop.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: backdrop.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: backdrop.trailingAnchor),
            host.topAnchor.constraint(equalTo: backdrop.topAnchor),
            host.bottomAnchor.constraint(equalTo: backdrop.bottomAnchor),
        ])

        panel.contentView = backdrop
        positionInitially(panel)
        self.panel = panel

        let centre = NotificationCenter.default
        centre.addObserver(
            self, selector: #selector(panelDidResize),
            name: NSWindow.didResizeNotification, object: panel)
        centre.addObserver(
            self, selector: #selector(panelDidMove),
            name: NSWindow.didMoveNotification, object: panel)
    }

    /// Top-right of the main screen, below the menubar — out of the way of a
    /// call window's controls, which sit centre-bottom.
    private func positionInitially(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let origin = CGPoint(
            x: visible.maxX - panel.frame.width - 20,
            y: visible.maxY - panel.frame.height - 20)
        panel.setFrameOrigin(origin)
        pinnedTopLeft = CGPoint(x: panel.frame.minX, y: panel.frame.maxY)
    }

    @objc private func panelDidResize() {
        guard let panel, let pinned = pinnedTopLeft, !isAdjustingFrame else { return }
        isAdjustingFrame = true
        panel.setFrameTopLeftPoint(pinned)
        isAdjustingFrame = false
    }

    @objc private func panelDidMove() {
        guard let panel, !isAdjustingFrame else { return }
        pinnedTopLeft = CGPoint(x: panel.frame.minX, y: panel.frame.maxY)
    }

    @objc private func showPanel() {
        panel?.orderFrontRegardless()
    }

    private func togglePanel() {
        guard let panel else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }
}
