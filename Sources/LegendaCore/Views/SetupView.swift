import SwiftUI

struct SetupView: View {
    @ObservedObject var engine: MeetingEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                // Left intentionally empty: the titlebar's close button sits here.
                Spacer()
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
                ForEach(engine.items) { item in
                    AgendaRow(engine: engine, item: item)
                }
            }

            Button {
                engine.addItem(minutes: 5)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                    Text("Add item")
                }
                .font(.system(size: 11))
                .foregroundStyle(Palette.dim)
            }
            .buttonStyle(.plain)

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
}

private struct AgendaRow: View {
    @ObservedObject var engine: MeetingEngine
    let item: AgendaItem

    @State private var isHovering = false
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

    init(engine: MeetingEngine, item: AgendaItem) {
        self.engine = engine
        self.item = item
        _minutesText = State(initialValue: String(item.plannedSeconds / 60))
    }

    var body: some View {
        HStack(spacing: 5) {
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
        .onHover { isHovering = $0 }
    }

    private var titleBinding: Binding<String> {
        Binding(
            get: { item.title },
            set: { engine.setTitle($0, for: item.id) })
    }

    /// Minutes is the right granularity for planning an agenda; the engine keeps
    /// seconds internally so that borrowing and settling stay exact.
    private var minutesBinding: Binding<Int> {
        Binding(
            get: { item.plannedSeconds / 60 },
            set: { engine.setSeconds(max(0, $0) * 60, for: item.id) })
    }
}
