import Foundation

public enum MeetingPhase: Sendable, Equatable {
    case setup
    case running
    case paused
    case finished
}

/// The agenda clock and its buffer accounting.
///
/// Two rules keep this correct and testable:
///
/// 1. **Only user actions mutate stored state.** Everything time-dependent is
///    derived from `now()` on read, so a dropped tick, a slow tick, or the Mac
///    going to sleep can't put the numbers out of step.
///
/// 2. **Borrowing is meeting-level, not item-level.** An overrunning item keeps
///    its own allocation (so its ring completes on schedule and then visibly
///    overruns) while the *meeting's* slack quietly absorbs the cost. The borrow
///    is provisional until the user advances, at which point it's settled into
///    stored allocations.
///
/// Items never advance on their own. The app can't know that a conversation has
/// moved on, and silently resetting the ring while someone is still talking
/// would misreport where the meeting actually is — so advancing is always a
/// deliberate press of Next.
@MainActor
public final class MeetingEngine: ObservableObject {

    // MARK: - Stored state

    @Published public private(set) var items: [AgendaItem]
    @Published public private(set) var phase: MeetingPhase = .setup
    @Published public private(set) var currentIndex: Int = 0

    /// Planned time ± explicit adjustments ± settled borrowing. Not time-derived.
    private var base: [UUID: Int] = [:]
    /// Seconds settled into an item before the currently running segment.
    private var banked: [UUID: Int] = [:]
    /// Start of the live segment. `nil` means the clock is not running.
    private var segmentStart: Date?

    private var undoStack: [Snapshot] = []
    private var pendingCues: [SoundCue] = []

    /// When armed, the absolute instant the meeting should begin. Resolved once
    /// when armed rather than held as a wall-clock time, so changing timezone
    /// afterwards cannot silently move it.
    @Published public private(set) var scheduledStart: Date?

    /// Cue edge-detection state.
    private var lastWarningSecond: Int?
    private var wasOverrunning = false
    /// Separate from `lastWarningSecond`: that one belongs to the running item,
    /// this one to the pre-start countdown.
    private var lastCountdownSecond: Int?

    private let now: () -> Date

    public init(items: [AgendaItem] = [], now: @escaping () -> Date = Date.init) {
        self.items = items
        self.now = now
    }

    private struct Snapshot {
        var items: [AgendaItem]
        var base: [UUID: Int]
        var banked: [UUID: Int]
        var currentIndex: Int
        var segmentStart: Date?
        var phase: MeetingPhase
    }

    private var snapshot: Snapshot {
        Snapshot(items: items, base: base, banked: banked,
                 currentIndex: currentIndex, segmentStart: segmentStart, phase: phase)
    }

    private func restore(_ s: Snapshot) {
        items = s.items
        base = s.base
        banked = s.banked
        currentIndex = s.currentIndex
        segmentStart = s.segmentStart
        phase = s.phase
    }

    // MARK: - Setup editing (frozen once running)

    public var isEditable: Bool { phase == .setup }

    public func replaceItems(_ newItems: [AgendaItem]) {
        guard isEditable else { return }
        items = newItems
    }

    public func addItem(title: String = "", minutes: Int = 5) {
        guard isEditable else { return }
        items.append(AgendaItem(title: title, plannedSeconds: max(0, minutes) * 60))
    }

    public func removeItem(id: UUID) {
        guard isEditable else { return }
        items.removeAll { $0.id == id }
    }

    public func setTitle(_ title: String, for id: UUID) {
        guard isEditable, let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].title = title
    }

    public func setSeconds(_ seconds: Int, for id: UUID) {
        guard isEditable, let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].plannedSeconds = max(0, seconds)
    }

    public func toggleBuffer(for id: UUID) {
        guard isEditable, let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].isBuffer.toggle()
    }

    public func move(fromOffsets: IndexSet, toOffset: Int) {
        guard isEditable else { return }
        items.move(fromOffsets: fromOffsets, toOffset: toOffset)
    }

    /// Move the item with `id` so that it ends up at `destination`.
    ///
    /// `Array.move(fromOffsets:toOffset:)` inserts *before* `toOffset`, which means
    /// a downward move needs `destination + 1`; passing the raw destination
    /// silently no-ops a move down by one place. Keeping that arithmetic here means
    /// the drag-and-drop code never has to think about it.
    public func moveItem(id: UUID, to destination: Int) {
        guard isEditable,
            let from = items.firstIndex(where: { $0.id == id }),
            items.indices.contains(destination),
            from != destination
        else { return }
        let offset = destination > from ? destination + 1 : destination
        items.move(fromOffsets: IndexSet(integer: from), toOffset: offset)
    }

    // MARK: - Derived reads

    public var currentItem: AgendaItem? {
        items.indices.contains(currentIndex) ? items[currentIndex] : nil
    }

    public var canGoBack: Bool { !undoStack.isEmpty }

    /// The item's own time budget. Deliberately excludes provisional borrowing so
    /// that the item ring completes when the *planned* time is up.
    public func allocation(of item: AgendaItem) -> Int {
        base[item.id] ?? item.plannedSeconds
    }

    public func spent(_ item: AgendaItem) -> Int {
        let settled = banked[item.id] ?? 0
        guard item.id == currentItem?.id, let start = segmentStart else { return settled }
        return settled + max(0, Int(now().timeIntervalSince(start)))
    }

    /// Slack still ahead of the playhead. Buffer items already passed are spent,
    /// and an item can't borrow from itself.
    public var slackTotal: Int {
        items.enumerated()
            .filter { $0.offset > currentIndex && $0.element.isBuffer }
            .reduce(0) { $0 + max(0, allocation(of: $1.element)) }
    }

    /// How much of the current overrun the slack is currently covering. Provisional
    /// until `next()` settles it.
    public var liveBorrow: Int {
        guard let current = currentItem, !current.isBuffer else { return 0 }
        return min(itemOverrun, slackTotal)
    }

    public var slackRemaining: Int { max(0, slackTotal - liveBorrow) }

    /// True when the overrun is no longer fully covered by slack. Note this is
    /// `> liveBorrow` rather than `slackRemaining == 0`: a buffer item that
    /// overruns borrows nothing (it can't fund itself), so it is over the moment
    /// it overruns even though later slack may still exist.
    public var isOvertime: Bool { itemOverrun > liveBorrow }

    public var itemOverrun: Int {
        guard let current = currentItem else { return 0 }
        return max(0, spent(current) - allocation(of: current))
    }

    public var itemRemaining: Int {
        guard let current = currentItem else { return 0 }
        return max(0, allocation(of: current) - spent(current))
    }

    /// Constant while slack lasts: borrowing moves seconds between items without
    /// changing the sum. Grows only on a genuine overrun or an unfunded +1 min.
    public var plannedTotal: Int {
        items.reduce(0) { $0 + allocation(of: $1) }
    }

    public var totalSpent: Int {
        items.reduce(0) { $0 + spent($1) }
    }

    public var meetingOvertime: Int { max(0, totalSpent - plannedTotal) }

    /// The budgeted share of the outer ring.
    ///
    /// Within budget this is ordinary progress. Once over, the ring instead
    /// represents the item's *whole* elapsed time, split between the part that
    /// was planned and the part that wasn't — so 2 minutes over and 20 minutes
    /// over never look the same, which a second red lap clamped at full circle
    /// could not manage.
    public var itemBudgetArc: Double {
        guard let current = currentItem else { return 0 }
        let allocated = allocation(of: current)
        let used = spent(current)
        guard allocated > 0 else { return 0 }
        guard used > allocated else { return Double(used) / Double(allocated) }
        return Double(allocated) / Double(used)
    }

    /// The overrun share of the outer ring; `itemBudgetArc + itemOverrunArc == 1`
    /// whenever the item is over.
    public var itemOverrunArc: Double {
        guard let current = currentItem else { return 0 }
        let allocated = allocation(of: current)
        let used = spent(current)
        guard used > allocated, used > 0 else { return 0 }
        return Double(used - allocated) / Double(used)
    }

    /// 0…1 through the current item, then laps.
    public var itemProgress: Double {
        guard let current = currentItem else { return 0 }
        let allocated = allocation(of: current)
        guard allocated > 0 else { return 1 }
        return Double(spent(current)) / Double(allocated)
    }

    public var meetingProgress: Double {
        guard plannedTotal > 0 else { return 0 }
        return Double(totalSpent) / Double(plannedTotal)
    }

    /// Fractions round the circle where one item hands over to the next.
    public var boundaryFractions: [Double] {
        guard plannedTotal > 0 else { return [] }
        var out: [Double] = []
        var running = 0
        for item in items.dropLast() {
            running += allocation(of: item)
            out.append(Double(running) / Double(plannedTotal))
        }
        return out
    }

    /// Where the buffer items actually sit on the meeting ring, so the dashed
    /// slack segments are drawn in position rather than assumed to be trailing.
    public var bufferRanges: [ClosedRange<Double>] {
        guard plannedTotal > 0 else { return [] }
        var out: [ClosedRange<Double>] = []
        var running = 0
        for item in items {
            let start = Double(running) / Double(plannedTotal)
            running += allocation(of: item)
            let end = Double(running) / Double(plannedTotal)
            if item.isBuffer, end > start { out.append(start...end) }
        }
        return out
    }

    // MARK: - Actions

    public func start() {
        start(at: now())
    }

    /// Begins the meeting as though it had started at `instant`.
    ///
    /// Passing an instant in the past is how a scheduled start catches up: elapsed
    /// time is derived as `now() - segmentStart`, so firing at 14:35 for a 14:30
    /// schedule yields a meeting already five minutes in, with a projected finish
    /// that reflects what actually happened. There is no separate catch-up path.
    public func start(at instant: Date) {
        guard phase == .setup, !items.isEmpty else { return }
        base = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.plannedSeconds) })
        banked = [:]
        currentIndex = 0
        undoStack = []
        wasOverrunning = false
        lastWarningSecond = nil
        lastCountdownSecond = nil
        scheduledStart = nil
        segmentStart = instant
        phase = .running
        if items[0].isBuffer { pendingCues.append(.bufferStart) }
    }

    // MARK: - Scheduling

    /// Arm an automatic start. Ignored outside setup, or for an instant that has
    /// already passed — there would be nothing to wait for.
    public func schedule(at instant: Date) {
        guard phase == .setup, instant > now() else { return }
        scheduledStart = instant
        lastCountdownSecond = nil
    }

    public func cancelSchedule() {
        scheduledStart = nil
        lastCountdownSecond = nil
    }

    public var isScheduled: Bool { scheduledStart != nil }

    /// Whole seconds until an armed start, floored at zero. `nil` when not armed.
    public var secondsUntilStart: Int? {
        guard let scheduledStart else { return nil }
        return max(0, Int(scheduledStart.timeIntervalSince(now()).rounded(.up)))
    }

    public func togglePause() {
        switch phase {
        case .running:
            bankSegment()
            phase = .paused
        case .paused:
            segmentStart = now()
            phase = .running
        default:
            break
        }
    }

    /// Advance, settling the current item's over- or under-run against the slack.
    public func next() {
        guard phase == .running || phase == .paused, let current = currentItem else { return }
        // Bank *before* snapshotting, so Previous restores the time this item had
        // actually accrued rather than resetting it to the start of the segment.
        bankSegment()
        undoStack.append(snapshot)

        settle(current)

        if currentIndex + 1 < items.count {
            currentIndex += 1
            lastWarningSecond = nil
            wasOverrunning = false
            pendingCues.append(.itemChange)
            if items[currentIndex].isBuffer { pendingCues.append(.bufferStart) }
            if phase == .running { segmentStart = now() }
        } else {
            phase = .finished
            segmentStart = nil
            pendingCues.append(.complete)
        }
    }

    /// The back control. Steps to the previous item, or — on the first item, where
    /// there is nothing to step back to — returns to the agenda, exactly as
    /// "Reset to Agenda" does. So back always undoes the last thing you did,
    /// whether that was advancing an item or starting the meeting.
    public func back() {
        if canGoBack {
            previous()
        } else {
            reset()
        }
    }

    public func previous() {
        guard let restored = undoStack.popLast() else { return }
        restore(restored)
        lastWarningSecond = nil
        wasOverrunning = false
        if phase == .running { segmentStart = now() }
    }

    /// Buy a minute for the current item, funded from slack where there is any.
    public func addMinute() {
        guard phase == .running || phase == .paused, let current = currentItem else { return }
        base[current.id] = allocation(of: current) + 60
        // Unfunded minutes are allowed — they extend the meeting rather than being
        // silently refused — but they are drawn from slack first.
        withdrawFromSlack(min(60, slackTotal))
        wasOverrunning = false
    }

    public func reset() {
        base = [:]
        banked = [:]
        segmentStart = nil
        currentIndex = 0
        undoStack = []
        pendingCues = []
        lastWarningSecond = nil
        lastCountdownSecond = nil
        scheduledStart = nil
        wasOverrunning = false
        phase = .setup
    }

    // MARK: - Tick

    /// Drives redraws and emits the cues whose moment has just passed. Safe to
    /// call at any cadence; all state here is edge-detected, not accumulated.
    public func tick() {
        objectWillChange.send()

        // An armed start counts down with the same three Tinks an item uses as its
        // time runs out, then fires.
        if phase == .setup, let scheduled = scheduledStart {
            let untilStart = max(0, Int(scheduled.timeIntervalSince(now()).rounded(.up)))
            if (1...3).contains(untilStart), lastCountdownSecond != untilStart {
                lastCountdownSecond = untilStart
                pendingCues.append(.warning)
            }
            if untilStart > 3 { lastCountdownSecond = nil }

            if now() >= scheduled {
                // Backdated deliberately, so a start delayed past the scheduled
                // instant (a late tick, or waking from sleep) is already elapsed.
                start(at: scheduled)
                pendingCues.append(.itemChange)
            }
        }

        guard phase == .running, currentItem != nil else { return }

        let remaining = itemRemaining
        if (1...3).contains(remaining), lastWarningSecond != remaining {
            lastWarningSecond = remaining
            pendingCues.append(.warning)
        }
        if remaining > 3 { lastWarningSecond = nil }

        let overrunning = isOvertime
        if overrunning, !wasOverrunning { pendingCues.append(.overtime) }
        wasOverrunning = overrunning
    }

    public func consumeCues() -> [SoundCue] {
        defer { pendingCues.removeAll() }
        return pendingCues
    }

    // MARK: - Internals

    private func bankSegment() {
        guard let current = currentItem, let start = segmentStart else { return }
        banked[current.id] = (banked[current.id] ?? 0) + max(0, Int(now().timeIntervalSince(start)))
        segmentStart = nil
    }

    /// Reconcile the item's actual spend with its allocation:
    /// overruns draw from slack, early finishes hand time back to it.
    private func settle(_ item: AgendaItem) {
        let delta = spent(item) - allocation(of: item)
        guard delta != 0 else { return }

        // The item's allocation becomes what it actually used, either way.
        let funded = delta > 0 ? min(delta, slackTotal) : 0
        base[item.id] = spent(item)

        if delta > 0 {
            // Slack pays what it can; anything beyond `funded` is real overtime
            // and legitimately grows the meeting total.
            withdrawFromSlack(funded)
        } else {
            depositToSlack(-delta)
        }
    }

    /// Take from buffer items ahead of the playhead, nearest first.
    private func withdrawFromSlack(_ seconds: Int) {
        var remaining = seconds
        for (offset, item) in items.enumerated()
        where offset > currentIndex && item.isBuffer && remaining > 0 {
            let available = max(0, allocation(of: item))
            let taken = min(available, remaining)
            base[item.id] = available - taken
            remaining -= taken
        }
    }

    /// Hand reclaimed time to the next buffer item. With no buffer ahead the
    /// meeting simply finishes early.
    private func depositToSlack(_ seconds: Int) {
        guard seconds > 0 else { return }
        guard let target = items.enumerated()
            .first(where: { $0.offset > currentIndex && $0.element.isBuffer })?.element
        else { return }
        base[target.id] = allocation(of: target) + seconds
    }
}
