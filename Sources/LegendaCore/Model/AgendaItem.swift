import Foundation

public struct AgendaItem: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var plannedSeconds: Int
    /// Slack. Overruns elsewhere are paid for out of buffer items that are still
    /// ahead of the playhead, which keeps the projected end time still.
    public var isBuffer: Bool

    public init(id: UUID = UUID(), title: String, plannedSeconds: Int, isBuffer: Bool = false) {
        self.id = id
        self.title = title
        self.plannedSeconds = plannedSeconds
        self.isBuffer = isBuffer
    }
}

public extension Int {
    /// `mm:ss`, or `h:mm:ss` past an hour.
    var clockString: String {
        let total = abs(self)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
