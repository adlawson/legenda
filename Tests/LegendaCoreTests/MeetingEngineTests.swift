import Foundation
import Testing

@testable import LegendaCore

/// A hand-cranked clock, so elapsed time is exact rather than wall-clock flaky.
@MainActor
final class FakeClock {
    private(set) var current = Date(timeIntervalSince1970: 1_000_000)
    func advance(_ seconds: Int) { current = current.addingTimeInterval(TimeInterval(seconds)) }
    var now: () -> Date { { [self] in current } }
}

@MainActor
private func makeEngine(
    _ spec: [(String, Int, Bool)] = [("Intro", 2, false), ("Updates", 8, false), ("Buffer", 5, true)]
) -> (MeetingEngine, FakeClock) {
    let clock = FakeClock()
    let items = spec.map { AgendaItem(title: $0.0, plannedSeconds: $0.1 * 60, isBuffer: $0.2) }
    return (MeetingEngine(items: items, now: clock.now), clock)
}

@MainActor
@Suite("Meeting engine")
struct MeetingEngineTests {

    @Test("Setup edits are frozen once the meeting starts")
    func editsFreezeOnStart() {
        let (engine, _) = makeEngine()
        #expect(engine.isEditable)
        engine.start()
        #expect(!engine.isEditable)

        let originalCount = engine.items.count
        engine.addItem(title: "Sneaky", minutes: 3)
        engine.setSeconds(999, for: engine.items[0].id)
        #expect(engine.items.count == originalCount)
        #expect(engine.items[0].plannedSeconds == 120)
    }

    // MARK: - Reordering

    @Test("Moving an item lands it exactly at the requested position")
    func moveItemPositions() {
        // Four distinct titles, so an off-by-one cannot hide behind a symmetry.
        func fresh() -> MeetingEngine {
            makeEngine([("A", 1, false), ("B", 2, false), ("C", 3, false), ("D", 4, false)]).0
        }
        func titles(_ e: MeetingEngine) -> [String] { e.items.map(\.title) }

        // Down one place: the case that silently no-ops without the +1.
        let down = fresh()
        down.moveItem(id: down.items[0].id, to: 1)
        #expect(titles(down) == ["B", "A", "C", "D"])

        // Up one place.
        let up = fresh()
        up.moveItem(id: up.items[2].id, to: 1)
        #expect(titles(up) == ["A", "C", "B", "D"])

        // To the very end, and to the very front.
        let last = fresh()
        last.moveItem(id: last.items[0].id, to: 3)
        #expect(titles(last) == ["B", "C", "D", "A"])

        let first = fresh()
        first.moveItem(id: first.items[3].id, to: 0)
        #expect(titles(first) == ["D", "A", "B", "C"])
    }

    @Test("Moving to its own position, or to a bogus one, changes nothing")
    func moveItemNoOps() {
        let (engine, _) = makeEngine()
        let before = engine.items.map(\.title)

        engine.moveItem(id: engine.items[1].id, to: 1)
        engine.moveItem(id: engine.items[0].id, to: 99)
        engine.moveItem(id: UUID(), to: 0)
        #expect(engine.items.map(\.title) == before)
    }

    @Test("Reordering is frozen once the meeting starts")
    func moveItemFrozenWhenRunning() {
        let (engine, _) = makeEngine()
        engine.start()
        let before = engine.items.map(\.title)
        engine.moveItem(id: engine.items[0].id, to: 2)
        #expect(engine.items.map(\.title) == before)
    }

    @Test("Slack is positional, so moving the buffer earlier withdraws it")
    func movingBufferChangesSlack() {
        // Buffer last: its 5 minutes are available to the first item.
        let (engine, _) = makeEngine()
        engine.start()
        #expect(engine.slackTotal == 5 * 60)

        // Buffer first: nothing ahead of the playhead can fund an overrun.
        let (moved, _) = makeEngine()
        moved.moveItem(id: moved.items[2].id, to: 0)
        #expect(moved.items.map(\.title) == ["Buffer", "Intro", "Updates"])
        moved.start()
        #expect(moved.slackTotal == 0)
    }

    // MARK: - Scheduled start

    @Test("An armed schedule fires once the clock reaches it")
    func scheduleFires() {
        let (engine, clock) = makeEngine()
        engine.schedule(at: clock.current.addingTimeInterval(60))
        #expect(engine.isScheduled)
        #expect(engine.secondsUntilStart == 60)

        clock.advance(59)
        engine.tick()
        #expect(engine.phase == .setup)  // not yet

        clock.advance(1)
        engine.tick()
        #expect(engine.phase == .running)
        #expect(!engine.isScheduled)
        #expect(engine.secondsUntilStart == nil)
    }

    @Test("A start that fires late is already elapsed, rather than starting at zero")
    func lateStartCatchesUp() {
        let (engine, clock) = makeEngine()
        let scheduled = clock.current.addingTimeInterval(60)
        engine.schedule(at: scheduled)

        // Nothing ticks for six minutes — a sleeping Mac, say — so the schedule
        // fires five minutes after the instant it was armed for.
        clock.advance(360)
        engine.tick()

        #expect(engine.phase == .running)
        #expect(engine.spent(engine.items[0]) == 300)
        // Intro is budgeted 2 min, so it is already 3 min over.
        #expect(engine.itemOverrun == 180)
    }

    @Test("The pre-start countdown ticks once each at 3, 2 and 1 seconds")
    func preStartCountdownCues() {
        let (engine, clock) = makeEngine()
        engine.schedule(at: clock.current.addingTimeInterval(10))
        _ = engine.consumeCues()

        clock.advance(7)  // 3 seconds to go
        engine.tick()
        engine.tick()  // repeated ticks in the same second must not double-fire
        #expect(engine.consumeCues().filter { $0 == .warning }.count == 1)

        clock.advance(1)  // 2
        engine.tick()
        #expect(engine.consumeCues().filter { $0 == .warning }.count == 1)

        clock.advance(1)  // 1
        engine.tick()
        #expect(engine.consumeCues().filter { $0 == .warning }.count == 1)

        clock.advance(1)  // fires
        engine.tick()
        let atStart = engine.consumeCues()
        #expect(atStart.contains(.itemChange))
        #expect(engine.phase == .running)
    }

    @Test("No countdown cues fire while the start is still far off")
    func noCuesLongBeforeStart() {
        let (engine, clock) = makeEngine()
        engine.schedule(at: clock.current.addingTimeInterval(600))
        _ = engine.consumeCues()

        clock.advance(300)
        engine.tick()
        #expect(engine.consumeCues().isEmpty)
    }

    @Test("Cancelling stops it firing")
    func cancelSchedule() {
        let (engine, clock) = makeEngine()
        engine.schedule(at: clock.current.addingTimeInterval(10))
        engine.cancelSchedule()
        #expect(!engine.isScheduled)

        clock.advance(60)
        engine.tick()
        #expect(engine.phase == .setup)
        #expect(engine.consumeCues().isEmpty)
    }

    @Test("A time already in the past is refused, since there is nothing to wait for")
    func pastTimeIsRefused() {
        let (engine, clock) = makeEngine()
        engine.schedule(at: clock.current.addingTimeInterval(-60))
        #expect(!engine.isScheduled)
        engine.tick()
        #expect(engine.phase == .setup)
    }

    @Test("Arming is refused once running, and reset disarms")
    func scheduleOnlyDuringSetup() {
        let (engine, clock) = makeEngine()
        engine.start()
        engine.schedule(at: clock.current.addingTimeInterval(60))
        #expect(!engine.isScheduled)

        engine.reset()
        engine.schedule(at: clock.current.addingTimeInterval(60))
        #expect(engine.isScheduled)
        engine.reset()
        #expect(!engine.isScheduled)
    }

    @Test("A manual start produces no countdown cues")
    func manualStartIsSilentBeforehand() {
        let (engine, _) = makeEngine()
        engine.start()
        #expect(!engine.consumeCues().contains(.warning))
    }

    @Test("An overrun is covered by slack and leaves the meeting total untouched")
    func overrunBorrowsFromSlack() {
        let (engine, clock) = makeEngine()
        engine.start()
        let plannedBefore = engine.plannedTotal
        #expect(plannedBefore == 15 * 60)

        // Intro is budgeted 2 min; run it to 3.
        clock.advance(180)
        engine.tick()

        #expect(engine.itemOverrun == 60)
        #expect(engine.liveBorrow == 60)
        #expect(engine.slackRemaining == 4 * 60)
        #expect(!engine.isOvertime)
        // Provisional borrowing must not move the total.
        #expect(engine.plannedTotal == plannedBefore)

        // Settling on Next makes it permanent, still without changing the total.
        engine.next()
        #expect(engine.plannedTotal == plannedBefore)
        #expect(engine.allocation(of: engine.items[0]) == 180)
        #expect(engine.allocation(of: engine.items[2]) == 4 * 60)
    }

    @Test("The item ring tracks the item's own budget, not the borrowed extension")
    func itemProgressIgnoresBorrowing() {
        let (engine, clock) = makeEngine()
        engine.start()
        clock.advance(120)
        engine.tick()
        // Exactly at the 2 min budget: the ring has completed one lap.
        #expect(abs(engine.itemProgress - 1.0) < 0.001)

        // Borrowing must not stretch the ring and stop it ever completing.
        clock.advance(60)
        engine.tick()
        #expect(engine.itemProgress > 1.0)
    }

    @Test("The outer ring splits proportionally when over, so it never saturates")
    func outerRingSplitsOnOverrun() {
        let (engine, clock) = makeEngine()
        engine.start()

        clock.advance(60)  // halfway through a 2 min item
        #expect(abs(engine.itemBudgetArc - 0.5) < 0.001)
        #expect(engine.itemOverrunArc == 0)

        clock.advance(60)  // exactly on budget
        #expect(abs(engine.itemBudgetArc - 1.0) < 0.001)
        #expect(engine.itemOverrunArc == 0)

        clock.advance(360)  // 8:00 spent against a 2:00 budget
        // The ring now shows the item's whole elapsed time, quartered.
        #expect(abs(engine.itemBudgetArc - 0.25) < 0.001)
        #expect(abs(engine.itemOverrunArc - 0.75) < 0.001)
        #expect(abs(engine.itemBudgetArc + engine.itemOverrunArc - 1.0) < 0.001)

        // Going further over must keep moving the split rather than clamping.
        let overrunBefore = engine.itemOverrunArc
        clock.advance(600)
        #expect(engine.itemOverrunArc > overrunBefore)
    }

    @Test("Overrunning past exhausted slack produces climbing overtime")
    func overtimeAfterSlackExhausted() {
        let (engine, clock) = makeEngine()
        engine.start()

        // Blow 2 min budget by 6 min, against only 5 min of slack.
        clock.advance(120 + 360)
        engine.tick()

        #expect(engine.itemOverrun == 360)
        #expect(engine.liveBorrow == 300)
        #expect(engine.slackRemaining == 0)
        #expect(engine.isOvertime)

        engine.next()
        // One unfunded minute grows the total by exactly that minute.
        #expect(engine.plannedTotal == 16 * 60)
    }

    @Test("Finishing early hands the unspent remainder back to slack")
    func skippingEarlyReturnsTimeToSlack() {
        let (engine, clock) = makeEngine()
        engine.start()
        clock.advance(30)
        engine.next()

        #expect(engine.allocation(of: engine.items[0]) == 30)
        // 90 unspent seconds go to the buffer.
        #expect(engine.allocation(of: engine.items[2]) == 5 * 60 + 90)
        #expect(engine.plannedTotal == 15 * 60)
        #expect(engine.currentIndex == 1)
    }

    @Test("+1 min extends the item and is funded from slack")
    func addMinuteDrawsFromSlack() {
        let (engine, _) = makeEngine()
        engine.start()
        let plannedBefore = engine.plannedTotal

        engine.addMinute()
        #expect(engine.allocation(of: engine.items[0]) == 180)
        #expect(engine.allocation(of: engine.items[2]) == 4 * 60)
        #expect(engine.plannedTotal == plannedBefore)
    }

    @Test("+1 min with no slack left grows the meeting instead of being refused")
    func addMinuteWithoutSlackGrowsTotal() {
        let (engine, _) = makeEngine([("Talk", 5, false)])
        engine.start()
        #expect(engine.slackTotal == 0)

        engine.addMinute()
        #expect(engine.allocation(of: engine.items[0]) == 6 * 60)
        #expect(engine.plannedTotal == 6 * 60)
    }

    @Test("Previous restores the prior state exactly, including elapsed time")
    func previousIsAFaithfulUndo() {
        let (engine, clock) = makeEngine()
        engine.start()
        clock.advance(180)  // 1 min over on Intro

        engine.next()
        #expect(engine.currentIndex == 1)
        let bufferAfterSettle = engine.allocation(of: engine.items[2])
        #expect(bufferAfterSettle == 4 * 60)

        clock.advance(30)
        engine.previous()

        #expect(engine.currentIndex == 0)
        // The borrow is unwound...
        #expect(engine.allocation(of: engine.items[2]) == 5 * 60)
        #expect(engine.allocation(of: engine.items[0]) == 120)
        // ...and Intro keeps the three minutes it had really used, rather than
        // restarting from zero.
        #expect(engine.spent(engine.items[0]) == 180)
    }

    @Test("With no buffer item at all, an overrun is immediately overtime")
    func noBufferMeansImmediateOvertime() {
        let (engine, clock) = makeEngine([("One", 1, false), ("Two", 1, false)])
        engine.start()
        clock.advance(75)
        engine.tick()

        #expect(engine.slackTotal == 0)
        #expect(engine.itemOverrun == 15)
        #expect(engine.liveBorrow == 0)
        #expect(engine.isOvertime)
    }

    @Test("A buffer item cannot fund its own overrun")
    func bufferDoesNotBorrowFromItself() {
        // Two buffers, so slack demonstrably exists while the running buffer
        // still refuses to draw on it. With a single buffer this would pass
        // merely because there was no slack anywhere.
        let (engine, clock) = makeEngine([("Talk", 1, false), ("First", 5, true), ("Second", 5, true)])
        engine.start()
        // Spend Talk's budget exactly, so nothing is donated forward and the
        // first buffer stays at its planned 5 minutes.
        clock.advance(60)
        engine.next()
        #expect(engine.currentItem?.isBuffer == true)
        #expect(engine.allocation(of: engine.items[1]) == 5 * 60)

        clock.advance(6 * 60)
        engine.tick()

        #expect(engine.slackTotal == 5 * 60)  // the second buffer is available...
        #expect(engine.itemOverrun == 60)
        #expect(engine.liveBorrow == 0)  // ...but a buffer will not fund itself
        #expect(engine.isOvertime)
    }

    @Test("Pausing stops the clock and resuming does not backfill the gap")
    func pauseHoldsTheClock() {
        let (engine, clock) = makeEngine()
        engine.start()
        clock.advance(60)
        engine.togglePause()
        #expect(engine.phase == .paused)
        #expect(engine.spent(engine.items[0]) == 60)

        clock.advance(600)  // long interruption
        #expect(engine.spent(engine.items[0]) == 60)

        engine.togglePause()
        clock.advance(30)
        #expect(engine.spent(engine.items[0]) == 90)
    }

    @Test("A clock jump, as after sleep, lands on the right elapsed time")
    func survivesClockJump() {
        let (engine, clock) = makeEngine()
        engine.start()
        // No ticks at all during the jump: elapsed is derived, not accumulated.
        clock.advance(3600)
        engine.tick()
        #expect(engine.spent(engine.items[0]) == 3600)
        #expect(engine.itemOverrun == 3600 - 120)
    }

    @Test("The meeting finishes after the last item and can be reset")
    func finishAndReset() {
        let (engine, clock) = makeEngine([("One", 1, false)])
        engine.start()
        clock.advance(60)
        engine.next()

        #expect(engine.phase == .finished)
        engine.reset()
        #expect(engine.phase == .setup)
        #expect(engine.isEditable)
        #expect(engine.currentIndex == 0)
    }

    @Test("Cues fire once per moment, on the edge")
    func cuesAreEdgeTriggered() {
        let (engine, clock) = makeEngine()
        engine.start()
        _ = engine.consumeCues()

        // 3 seconds left on a 120s item.
        clock.advance(117)
        engine.tick()
        engine.tick()  // repeated ticks in the same second must not double-fire
        #expect(engine.consumeCues().filter { $0 == .warning }.count == 1)

        clock.advance(1)
        engine.tick()
        #expect(engine.consumeCues().filter { $0 == .warning }.count == 1)

        engine.next()
        let cues = engine.consumeCues()
        #expect(cues.contains(.itemChange))
    }

    @Test("Reaching a buffer item announces itself")
    func bufferStartCue() {
        let (engine, _) = makeEngine([("Talk", 1, false), ("Buffer", 5, true)])
        engine.start()
        _ = engine.consumeCues()
        engine.next()
        #expect(engine.consumeCues().contains(.bufferStart))
    }

    @Test("Buffer ranges are placed where the buffer actually sits")
    func bufferRangesArePositional() {
        let (engine, _) = makeEngine([("A", 5, false), ("Buffer", 5, true), ("B", 10, false)])
        engine.start()
        let ranges = engine.bufferRanges
        #expect(ranges.count == 1)
        // 5 min into a 20 min meeting, ending 10 min in.
        #expect(abs(ranges[0].lowerBound - 0.25) < 0.001)
        #expect(abs(ranges[0].upperBound - 0.5) < 0.001)
    }
}
