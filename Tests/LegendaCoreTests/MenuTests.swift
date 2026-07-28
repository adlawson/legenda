import AppKit
import Testing

@testable import LegendaCore

@MainActor
@Suite("Menubar menu")
struct MenuTests {

    @Test("The title row shows the version prefixed with v")
    func versionTitleFormatting() {
        #expect(AppDelegate.versionTitle("20260728-rc1") == "Legenda v20260728-rc1")
        #expect(AppDelegate.versionTitle("0.0.0-dev") == "Legenda v0.0.0-dev")
        // No bundle to read from, e.g. running the binary rather than the .app.
        #expect(AppDelegate.versionTitle(nil) == "Legenda")
        #expect(AppDelegate.versionTitle("") == "Legenda")
    }

    @Test("The first item is an inert title row")
    func firstItemIsInert() {
        let menu = AppDelegate().makeMenu()
        let first = menu.items[0]

        #expect(first.title.hasPrefix("Legenda"))
        // No action and not enabled, so it cannot be selected.
        #expect(first.action == nil)
        #expect(!first.isEnabled)
        #expect(menu.items[1].isSeparatorItem)
    }

    @Test("Opening is always offered as Open, never as Show or Hide")
    func openIsUnconditional() {
        let menu = AppDelegate().makeMenu()
        let titles = menu.items.map(\.title)

        #expect(titles.contains("Open Legenda"))
        #expect(!titles.contains("Show Legenda"))
        #expect(!titles.contains("Hide Legenda"))

        let open = menu.items.first { $0.title == "Open Legenda" }
        #expect(open?.isEnabled == true)
        #expect(open?.action != nil)
    }

    @Test("Quit is always present")
    func quitIsPresent() {
        let menu = AppDelegate().makeMenu()
        #expect(menu.items.map(\.title).contains("Quit Legenda"))
    }
}
