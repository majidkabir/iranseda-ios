import Foundation
import SwiftUI
import WidgetKit

/// Something the user can come back to: a favourite or a recently played item.
struct SavedItem: Codable, Identifiable, Hashable {
    enum Kind: String, Codable {
        case detail     // opens an item page (audiobook, episode, ...)
        case home       // opens a serial or programme home
        case channel    // opens a radio station; `ref` is the channel id
        case play       // starts playing right away (live stream, archive slot)
    }

    var kind: Kind
    var url: String
    var ref: String = ""
    var title: String
    var subtitle: String = ""
    var image: String = ""

    var id: String { kind.rawValue + "|" + url + "|" + ref }
}

/// Favourites and listening history, kept in Application Support.
@MainActor
final class Library: ObservableObject {
    static let shared = Library()

    @Published private(set) var favorites: [SavedItem] = []
    @Published private(set) var recents: [SavedItem] = []

    private let file: URL
    private struct Stored: Codable {
        var favorites: [SavedItem]
        var recents: [SavedItem]
    }

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        file = dir.appendingPathComponent("library.json")
        if Demo.isOn {
            favorites = Demo.favorites
            recents = Demo.recents
        } else if let data = try? Data(contentsOf: file), let stored = try? JSONDecoder().decode(Stored.self, from: data) {
            favorites = stored.favorites
            recents = stored.recents
        }
    }

    func isFavorite(_ item: SavedItem) -> Bool { favorites.contains { $0.id == item.id } }

    func toggleFavorite(_ item: SavedItem) {
        if let index = favorites.firstIndex(where: { $0.id == item.id }) {
            favorites.remove(at: index)
        } else {
            favorites.insert(item, at: 0)
        }
        save()
    }

    func removeFavorites(at offsets: IndexSet) {
        favorites.remove(atOffsets: offsets)
        save()
    }

    /// Hand-arranged order; the widget shows favourite stations in this order too.
    func moveFavorites(from offsets: IndexSet, to destination: Int) {
        favorites.move(fromOffsets: offsets, toOffset: destination)
        save()
    }

    func addRecent(_ item: SavedItem) {
        recents.removeAll { $0.id == item.id }
        recents.insert(item, at: 0)
        if recents.count > 30 { recents.removeLast(recents.count - 30) }
        save()
    }

    func clearRecents() {
        recents = []
        save()
    }

    /// Any favourite or recent item by its id; used by widget deep links.
    func item(withID id: String) -> SavedItem? {
        favorites.first { $0.id == id } ?? recents.first { $0.id == id }
    }

    private func save() {
        guard !Demo.isOn else { return }
        if let data = try? JSONEncoder().encode(Stored(favorites: favorites, recents: recents)) {
            try? data.write(to: file, options: .atomic)
        }
        updateWidget()
    }

    /// Hands the widget the last played item and up to three stations (favourites first).
    private func updateWidget() {
        func entry(_ item: SavedItem) -> WidgetSnapshot.Entry {
            WidgetSnapshot.Entry(id: item.id, title: item.title, subtitle: item.subtitle, isStation: item.kind == .channel)
        }
        var stations = favorites.filter { $0.kind == .channel }
        for item in recents where item.kind == .channel && !stations.contains(where: { $0.id == item.id }) {
            stations.append(item)
        }
        let recent = recents.first { $0.kind != .home }
        WidgetSnapshot(recent: recent.map(entry), stations: stations.prefix(3).map(entry)).save()
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshot.kind)
    }
}

extension FeedBox {
    /// The favourite this box stands for, when it is a book/episode page or a series home.
    var saved: SavedItem? {
        guard !URL.isEmpty else { return nil }
        switch URLType {
        case "9": return SavedItem(kind: .detail, url: URL, title: title, subtitle: subtitle, image: image)
        case "7": return SavedItem(kind: .home, url: URL, title: title, subtitle: subtitle, image: image)
        default: return nil
        }
    }
}
