import SwiftUI

struct RunningView: View {
    @ObservedObject var engine: MeetingEngine

    var body: some View {
        VStack(spacing: 11) {
            ZStack {
                DualRing(
                    itemBudgetArc: engine.itemBudgetArc,
                    itemOverrunArc: engine.itemOverrunArc,
                    meetingProgress: engine.meetingProgress,
                    bufferRanges: engine.bufferRanges,
                    boundaries: engine.boundaryFractions,
                    isOvertime: engine.isOvertime,
                    isPaused: engine.phase == .paused,
                    isFinished: engine.phase == .finished)
                centre
            }
            .frame(width: 148, height: 148)
            .contentShape(Rectangle())
            .onTapGesture {
                if engine.phase != .finished { engine.togglePause() }
            }
            .help(engine.phase == .paused ? "Resume" : "Pause")

            heading

            if engine.phase == .finished {
                // Reset also lives in the menubar menu, but without a button here
                // the finished panel would be a dead end.
                ControlButton(title: "New meeting", help: "Back to the agenda") {
                    engine.reset()
                }
            } else {
                controls
            }
        }
    }

    // MARK: - Centre

    private var centre: some View {
        VStack(spacing: 1) {
            if engine.phase == .finished {
                Text("Done")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                Text(engine.totalSpent.clockString)
                    .font(.system(size: 12, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Palette.dim)
            } else if let current = engine.currentItem {
                Text(engine.spent(current).clockString)
                    .font(.system(size: 30, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(engine.phase == .paused ? Palette.dim : Palette.item)

                if engine.itemOverrun > 0 {
                    Text("+\(engine.itemOverrun.clockString) over")
                        .font(.system(size: 10, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(engine.isOvertime ? Palette.over : Palette.dim)
                } else {
                    Text("of \(engine.allocation(of: current).clockString)")
                        .font(.system(size: 10, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Palette.faint)
                }
            }
        }
    }

    // MARK: - Heading

    private var heading: some View {
        VStack(spacing: 3) {
            if engine.phase == .paused {
                Text("Paused")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Palette.dim)
                    .textCase(.uppercase)
                    .tracking(0.6)
            }

            Text(currentTitle)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)

            HStack(spacing: 5) {
                if engine.phase == .finished {
                    Text("planned \(engine.plannedTotal.clockString)")
                } else {
                    Text("\(engine.currentIndex + 1) of \(engine.items.count)")
                    Text("·")
                    slack
                }
            }
            .font(.system(size: 10))
            .monospacedDigit()
            .foregroundStyle(Palette.faint)
        }
    }

    private var slack: some View {
        Group {
            // Overtime takes precedence: it can be true while buffer items are
            // still ahead of the playhead and unspent.
            if engine.meetingOvertime > 0 {
                Text("+\(engine.meetingOvertime.clockString) over")
                    .foregroundStyle(Palette.over)
            } else if engine.slackTotal == 0 {
                Text("no buffer")
            } else {
                Text("buffer \(engine.slackRemaining.clockString)")
                    .foregroundStyle(engine.slackRemaining == 0 ? Palette.over : Palette.faint)
            }
        }
    }

    private var currentTitle: String {
        guard let current = engine.currentItem else { return "—" }
        if current.title.isEmpty { return "Item \(engine.currentIndex + 1)" }
        return current.title
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 6) {
            // Never disabled: on the first item there is no previous item to step
            // to, so it returns to the agenda instead.
            ControlButton(
                systemImage: "arrow.uturn.backward",
                help: engine.canGoBack ? "Back to previous item" : "Back to the agenda"
            ) {
                engine.back()
            }

            ControlButton(title: "+1 min", help: "Give this item another minute, taken from the buffer") {
                engine.addMinute()
            }

            ControlButton(
                title: engine.currentIndex + 1 == engine.items.count ? "Finish" : "Next",
                help: "Move on; unused time goes back to the buffer"
            ) {
                engine.next()
            }
        }
    }
}

private struct ControlButton: View {
    var title: String?
    var systemImage: String?
    let help: String
    let action: () -> Void

    init(title: String? = nil, systemImage: String? = nil, help: String, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.help = help
        self.action = action
    }

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Group {
                if let title {
                    Text(title).font(.system(size: 11, weight: .medium))
                } else if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 10, weight: .medium))
                }
            }
            .frame(maxWidth: title == nil ? 26 : .infinity)
            .frame(height: 22)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Palette.track.opacity(isHovering ? 0.9 : 0.5)))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(help)
    }
}
