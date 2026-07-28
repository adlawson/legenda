import SwiftUI

/// Concentric progress rings.
///
/// - **Outer** — the current agenda item. Completes once per item, then laps in
///   red to show the overrun rather than sitting pinned at full.
/// - **Inner** — the whole meeting. Item handovers are faint ticks; buffer items
///   are dashed so slack reads as slack without needing its own colour.
struct DualRing: View {
    let itemBudgetArc: Double
    let itemOverrunArc: Double
    let meetingProgress: Double
    let bufferRanges: [ClosedRange<Double>]
    let boundaries: [Double]
    let isOvertime: Bool
    let isPaused: Bool
    let isFinished: Bool

    private let outerWidth: CGFloat = 10
    private let innerWidth: CGFloat = 4
    private let gap: CGFloat = 7

    var body: some View {
        Canvas { context, size in
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            let outerRadius = min(size.width, size.height) / 2 - outerWidth / 2
            let innerRadius = outerRadius - outerWidth / 2 - gap - innerWidth / 2

            // Outer: current item.
            context.stroke(
                arc(centre: centre, radius: outerRadius, from: 0, to: 1),
                with: .color(Palette.track), lineWidth: outerWidth)

            let isOver = itemOverrunArc > 0
            // Butt caps while split, so the handover between budgeted and overrun
            // is a clean edge rather than two rounded ends overlapping.
            let cap: CGLineCap = isOver ? .butt : .round

            let budgetArc = min(1, max(0, itemBudgetArc))
            if budgetArc > 0 {
                let colour = isFinished ? Palette.meeting : (isPaused ? Palette.dim : Palette.item)
                context.stroke(
                    arc(centre: centre, radius: outerRadius, from: 0, to: budgetArc),
                    with: .color(colour),
                    style: StrokeStyle(lineWidth: outerWidth, lineCap: cap))
            }
            if isOver {
                context.stroke(
                    arc(
                        centre: centre, radius: outerRadius,
                        from: budgetArc, to: min(1, budgetArc + itemOverrunArc)),
                    with: .color(Palette.over),
                    style: StrokeStyle(lineWidth: outerWidth, lineCap: cap))
            }

            // Inner: whole meeting.
            context.stroke(
                arc(centre: centre, radius: innerRadius, from: 0, to: 1),
                with: .color(Palette.track), lineWidth: innerWidth)

            for range in bufferRanges {
                context.stroke(
                    arc(centre: centre, radius: innerRadius, from: range.lowerBound, to: range.upperBound),
                    with: .color(Palette.buffer),
                    style: StrokeStyle(lineWidth: innerWidth, dash: [2, 2.5]))
            }

            let meetingLap = min(1, max(0, meetingProgress))
            if meetingLap > 0 {
                context.stroke(
                    arc(centre: centre, radius: innerRadius, from: 0, to: meetingLap),
                    with: .color(isOvertime ? Palette.over : Palette.meeting),
                    style: StrokeStyle(lineWidth: innerWidth, lineCap: .round))
            }

            // Item handovers.
            for boundary in boundaries {
                let angle = Angle.degrees(-90 + boundary * 360)
                let inner = point(centre: centre, radius: innerRadius - innerWidth / 2 - 2, angle: angle)
                let outer = point(centre: centre, radius: innerRadius + innerWidth / 2 + 2, angle: angle)
                var tick = Path()
                tick.move(to: inner)
                tick.addLine(to: outer)
                context.stroke(tick, with: .color(Palette.faint), lineWidth: 1)
            }
        }
    }

    private func arc(centre: CGPoint, radius: CGFloat, from: Double, to: Double) -> Path {
        var path = Path()
        path.addArc(
            center: centre, radius: radius,
            startAngle: .degrees(-90 + from * 360),
            endAngle: .degrees(-90 + to * 360),
            clockwise: false)
        return path
    }

    private func point(centre: CGPoint, radius: CGFloat, angle: Angle) -> CGPoint {
        CGPoint(
            x: centre.x + radius * cos(angle.radians),
            y: centre.y + radius * sin(angle.radians))
    }
}
