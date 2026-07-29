import SwiftUI

struct SetupView: View {
    @ObservedObject var engine: MeetingEngine

    /// The time shown in the picker. Only a placeholder until armed — the arm
    /// button recomputes it, so a panel left open for hours doesn't offer a stale
    /// guess.
    @State private var startTime: Date = SetupView.nextHalfHour()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                // Left intentionally empty: the titlebar's close button sits here.
                Spacer()
                scheduleControl
                Button(action: engine.start) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11))
                        .frame(width: 26, height: 20)
                        .background(Palette.track, in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .disabled(engine.items.isEmpty || engine.plannedTotal == 0)
                .help("Start the meeting")
            }

            VStack(spacing: 3) {
                ForEach(Array(engine.items.enumerated()), id: \.element.id) { index, item in
                    AgendaRow(engine: engine, item: item, index: index)
                }
            }

            Button {
                engine.addItem(minutes: 5)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11))
                    .frame(width: 26, height: 20)
                    .background(Palette.track, in: RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .help("Add an agenda item")

            Divider()

            HStack {
                Text("Total")
                Spacer()
                Text(engine.plannedTotal.clockString)
                    .monospacedDigit()
            }
            .font(.system(size: 11))
            .foregroundStyle(Palette.dim)

            if !engine.items.contains(where: \.isBuffer) {
                Text("No buffer item — overruns will run the meeting long.")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Scheduled start

    /// Scheduling is entirely opt-in: until it's armed, the only sign of it is a
    /// single alarm button. The on/off state is read from the engine rather than
    /// tracked separately here, so the two can't drift apart.
    @ViewBuilder private var scheduleControl: some View {
        if engine.isScheduled {
            // The toggle leads the inputs it governs, and stays put as the picker
            // appears and disappears around it.
            Button(action: engine.cancelSchedule) {
                Image(systemName: "alarm.fill")
                    .font(.system(size: 10))
                    .frame(width: 20, height: 20)
                    .background(Palette.track, in: RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .help("Scheduled for \(Self.clockFormatter.string(from: engine.scheduledStart ?? Date())) — click to cancel")

            // A DatePicker reads the Mac's locale and timezone with no extra work.
            DatePicker("", selection: $startTime, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.field)
                .font(.system(size: 11))
                .fixedSize()
                .onChange(of: startTime) { _, _ in rearm() }

            if let remaining = engine.secondsUntilStart {
                Text(remaining.clockString)
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(Palette.dim)
            }
        } else {
            Button {
                // Arm at the next half hour; the picker then appears so the time
                // can be adjusted from there. The instant is passed directly
                // rather than read back from `startTime`, which within this
                // closure would still hold its previous value.
                let boundary = Self.nextHalfHour()
                startTime = boundary
                engine.schedule(at: boundary)
            } label: {
                Image(systemName: "alarm")
                    .font(.system(size: 10))
                    .frame(width: 20, height: 20)
                    .background(Palette.track, in: RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .disabled(engine.items.isEmpty)
            .help("Start automatically at a set time")
        }
    }

    /// Arm for the picked time, or disarm if it has already passed — so editing the
    /// picker to a past time can't silently leave the old schedule armed.
    private func rearm() {
        if let instant = resolvedStart {
            engine.schedule(at: instant)
        } else {
            engine.cancelSchedule()
        }
    }

    /// Today's date at the picked time, in the Mac's own calendar and timezone.
    /// `nil` once that moment has passed, which disables arming rather than
    /// silently rolling over to tomorrow.
    private var resolvedStart: Date? {
        let calendar = Calendar.current
        let picked = calendar.dateComponents([.hour, .minute], from: startTime)
        guard
            let candidate = calendar.date(
                bySettingHour: picked.hour ?? 0, minute: picked.minute ?? 0, second: 0,
                of: Date())
        else { return nil }
        return candidate > Date() ? candidate : nil
    }

    /// The next `:00` or `:30`, which is when meetings actually start. Always
    /// strictly in the future, including when called exactly on a boundary, so
    /// `MeetingEngine.schedule(at:)`'s `instant > now()` guard can't reject it.
    private static func nextHalfHour() -> Date {
        let calendar = Calendar.current
        let now = Date()
        // Truncate to the minute first, so the result is a clean boundary.
        let truncated =
            calendar.date(
                from: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: now))
            ?? now
        let step = 30 - (calendar.component(.minute, from: now) % 30)
        return truncated.addingTimeInterval(TimeInterval(step * 60))
    }

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct AgendaRow: View {
    @ObservedObject var engine: MeetingEngine
    let item: AgendaItem
    let index: Int

    @State private var isHovering = false
    @State private var isDropTarget = false
    /// The minutes field is backed by a string rather than bound straight to an
    /// Int. A `format:`-based binding reparses on every keystroke, so clearing
    /// the field fails to parse and SwiftUI writes the old number back — typing
    /// "2" over a deleted "5" would leave you with 52.
    @State private var minutesText: String
    @FocusState private var isEditingMinutes: Bool

    @State private var titleFieldWidth: CGFloat = 0
    @FocusState private var isEditingTitle: Bool

    private static let titleFont = NSFont.systemFont(ofSize: 12)

    /// While editing, AppKit's field editor drops the 2pt lead inset that the
    /// non-editing cell draws with — but only once the text overflows and the
    /// editor becomes horizontally scrollable, which is why a short title never
    /// shifts. Measured at 2pt; putting it back keeps the text still.
    ///
    /// Switching this on narrows the field, which can only make the text overflow
    /// harder, so the condition can't oscillate.
    private var editingInsetFix: CGFloat {
        guard isEditingTitle, titleFieldWidth > 0 else { return 0 }
        let measured = (item.title as NSString)
            .size(withAttributes: [.font: Self.titleFont]).width
        // The cell reserves 2pt of lead inset, so that much less is drawable.
        // Measured against a sweep of widths: this is where AppKit actually
        // starts scrolling, and being a couple of points early over-corrects.
        return measured > titleFieldWidth - 2 ? 2 : 0
    }

    init(engine: MeetingEngine, item: AgendaItem, index: Int) {
        self.engine = engine
        self.item = item
        self.index = index
        _minutesText = State(initialValue: String(item.plannedSeconds / 60))
    }

    var body: some View {
        HStack(spacing: 5) {
            // A dedicated handle rather than dragging the row itself: a drag
            // starting in either TextField has to keep selecting text.
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 9))
                // Palette.item, matching an active buffer diamond: this is the only
                // way to reorder, so it needs to read at full contrast.
                .foregroundStyle(Palette.item)
                .frame(width: 11, height: 14)
                .opacity(isHovering ? 1 : 0)
                .draggable(item.id.uuidString)
                .help("Drag to reorder")

            TextField("Item", text: titleBinding)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($isEditingTitle)
                // Measured before the padding, so this is the field's own width.
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onChange(of: geo.size.width, initial: true) { _, width in
                                titleFieldWidth = width
                            }
                    }
                )
                .padding(.leading, editingInsetFix)

            TextField("", text: $minutesText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .frame(width: 26)
                .focused($isEditingMinutes)
                .onChange(of: minutesText) { _, new in
                    let digits = String(new.filter(\.isNumber).prefix(3))
                    if digits != new {
                        minutesText = digits
                        return
                    }
                    // An empty field is a legitimate step on the way to typing a
                    // new number, so nothing is written back until there is one.
                    if let minutes = Int(digits) {
                        engine.setSeconds(minutes * 60, for: item.id)
                    }
                }
                .onChange(of: isEditingMinutes) { _, editing in
                    // On leaving the field, show the canonical value. That both
                    // restores a field left empty and tidies "05" into "5".
                    if !editing { minutesText = String(item.plannedSeconds / 60) }
                }
                .onChange(of: item.plannedSeconds) { _, seconds in
                    // Track changes made elsewhere, but never fight a live edit.
                    if !isEditingMinutes { minutesText = String(seconds / 60) }
                }

            Text("min")
                .font(.system(size: 10))
                .foregroundStyle(Palette.faint)

            Button {
                engine.toggleBuffer(for: item.id)
            } label: {
                Image(systemName: item.isBuffer ? "diamond.fill" : "diamond")
                    .font(.system(size: 9))
                    .foregroundStyle(item.isBuffer ? Palette.item : Palette.faint)
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)
            .help(item.isBuffer ? "Buffer: absorbs overruns" : "Mark as buffer")

            Button {
                engine.removeItem(id: item.id)
            } label: {
                Image(systemName: "minus.circle")
                    .font(.system(size: 9))
                    .foregroundStyle(Palette.faint)
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)
            .opacity(isHovering ? 1 : 0)
            .help("Remove item")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Palette.track.opacity(item.isBuffer ? 0.5 : 0.25))
        )
        // Outlining the whole row says "this row's position", which is
        // unambiguous in a way that an edge rule between rows is not.
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(Palette.item, lineWidth: 1)
                .opacity(isDropTarget ? 1 : 0)
        )
        .onHover { isHovering = $0 }
        .dropDestination(for: String.self) { ids, _ in
            guard let raw = ids.first, let dragged = UUID(uuidString: raw) else { return false }
            engine.moveItem(id: dragged, to: index)
            return true
        } isTargeted: { targeted in
            isDropTarget = targeted
        }
    }

    private var titleBinding: Binding<String> {
        Binding(
            get: { item.title },
            set: { engine.setTitle($0, for: item.id) })
    }
}
