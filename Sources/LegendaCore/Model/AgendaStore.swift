import Foundation

/// Remembers the last agenda so a recurring meeting doesn't have to be retyped.
public struct AgendaStore {
    private static let key = "legenda.agenda.v1"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> [AgendaItem] {
        guard
            let data = defaults.data(forKey: Self.key),
            let items = try? JSONDecoder().decode([AgendaItem].self, from: data),
            !items.isEmpty
        else { return Self.starterAgenda }
        return items
    }

    public func save(_ items: [AgendaItem]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: Self.key)
    }

    /// First-run agenda, mostly to show what a Buffer item is for.
    public static var starterAgenda: [AgendaItem] {
        [
            AgendaItem(title: "Intro", plannedSeconds: 2 * 60),
            AgendaItem(title: "Updates", plannedSeconds: 8 * 60),
            AgendaItem(title: "Discussion", plannedSeconds: 15 * 60),
            AgendaItem(title: "Buffer", plannedSeconds: 5 * 60, isBuffer: true),
        ]
    }
}
