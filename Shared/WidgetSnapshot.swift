import Foundation

/// What the iPhone widgets show. Written by the app, read by the widget extension
/// through the shared App Group container.
struct WidgetSnapshot: Codable {
    struct Point: Codable {
        var date: Date
        var rating: Double
    }

    var rating: Double
    var level: Double
    var change30d: Double
    var points: [Point]
    var nextGameTitle: String?
    var nextGameDate: Date?
    var updatedAt: Date

    static let appGroup = "group.com.marvinjulius.pointcheck"
    private static let key = "widget.snapshot"

    static func load() -> WidgetSnapshot? {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func save() {
        guard let defaults = UserDefaults(suiteName: Self.appGroup),
              let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.key)
    }

    static let placeholder = WidgetSnapshot(
        rating: 1534, level: 3.7, change30d: 24,
        points: (0..<8).map { Point(date: Date.now.addingTimeInterval(Double($0 - 7) * 4 * 86_400), rating: 1500 + Double($0) * 5) },
        nextGameTitle: "Padel mit Lena", nextGameDate: Date.now.addingTimeInterval(2 * 86_400), updatedAt: .now
    )
}
