import Foundation

/// What the home-screen widget shows. The app writes it into the shared App Group;
/// the widget only reads it, so the widget never touches the network.
struct WidgetSnapshot: Codable {
    struct Entry: Codable, Identifiable {
        var id: String          // SavedItem.id, used in the deep link
        var title: String
        var subtitle: String
        var isStation: Bool

        var url: URL {
            var parts = URLComponents()
            parts.scheme = WidgetSnapshot.scheme
            parts.host = "open"
            parts.queryItems = [URLQueryItem(name: "id", value: id)]
            return parts.url ?? URL(string: WidgetSnapshot.scheme + "://open")!
        }
    }

    var recent: Entry?
    var stations: [Entry] = []

    static let group = "group.com.majidkabir.iranseda"
    static let scheme = "sedaplus"
    static let kind = "SedaWidget"
    private static let key = "widget.snapshot"

    static func load() -> WidgetSnapshot {
        guard let data = UserDefaults(suiteName: group)?.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else { return WidgetSnapshot() }
        return snapshot
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults(suiteName: Self.group)?.set(data, forKey: Self.key)
    }

    static let sample = WidgetSnapshot(
        recent: Entry(id: "r", title: "نام من سرخ", subtitle: "کتاب گویا", isStation: false),
        stations: [
            Entry(id: "a", title: "رادیو پیام", subtitle: "", isStation: true),
            Entry(id: "b", title: "رادیو ایران", subtitle: "", isStation: true),
            Entry(id: "c", title: "رادیو نمایش", subtitle: "", isStation: true),
        ])
}
