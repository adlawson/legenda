import AppKit

/// Remembers the panel's size and position between launches. Mirrors `AgendaStore`
/// rather than introducing a second persistence pattern.
struct PanelStore {
    private static let key = "legenda.panelFrame.v1"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> NSRect? {
        guard let values = defaults.array(forKey: Self.key) as? [Double], values.count == 4 else {
            return nil
        }
        return NSRect(x: values[0], y: values[1], width: values[2], height: values[3])
    }

    func save(_ frame: NSRect) {
        defaults.set(
            [frame.origin.x, frame.origin.y, frame.size.width, frame.size.height], forKey: Self.key)
    }

    /// Whether enough of `frame` overlaps a screen to be grabbable.
    ///
    /// A frame saved on a monitor that is no longer attached would otherwise restore
    /// offscreen, leaving the panel unreachable. Takes the screen rectangles as an
    /// argument so it can be tested without a display.
    static func isUsable(_ frame: NSRect, onScreens screens: [NSRect]) -> Bool {
        guard frame.width > 0, frame.height > 0 else { return false }
        let minimumVisible: CGFloat = 40
        return screens.contains { screen in
            let overlap = screen.intersection(frame)
            return overlap.width >= minimumVisible && overlap.height >= minimumVisible
        }
    }

    /// The restored frame, or `nil` if there isn't a usable one for the current
    /// display arrangement.
    func usableFrame(screens: [NSRect] = NSScreen.screens.map(\.visibleFrame)) -> NSRect? {
        guard let frame = load(), Self.isUsable(frame, onScreens: screens) else { return nil }
        return frame
    }
}
