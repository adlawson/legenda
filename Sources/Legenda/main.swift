import AppKit
import LegendaCore

// Held in a global so the delegate outlives launch.
let delegate = AppDelegate()

let app = NSApplication.shared
app.delegate = delegate
// Menubar-only: no Dock icon, and a prerequisite for the non-activating panel.
app.setActivationPolicy(.accessory)
app.run()
