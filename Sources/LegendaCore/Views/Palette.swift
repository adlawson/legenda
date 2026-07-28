import SwiftUI

/// Deliberately neutral, and built from AppKit's semantic colours so light and
/// dark both work without a second palette. The only hue in the app is the red
/// used for overrun — everything else is greyscale, and the buffer is
/// distinguished by a dashed stroke rather than a colour.
enum Palette {
    static let track = Color(nsColor: .quaternaryLabelColor)
    static let item = Color(nsColor: .labelColor)
    static let meeting = Color(nsColor: .tertiaryLabelColor)
    static let buffer = Color(nsColor: .secondaryLabelColor)
    static let over = Color(nsColor: .systemRed).opacity(0.85)
    static let dim = Color(nsColor: .secondaryLabelColor)
    static let faint = Color(nsColor: .tertiaryLabelColor)
}
