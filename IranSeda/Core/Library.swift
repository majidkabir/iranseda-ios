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
/// Favourites are also kept in iCloud, so the iPhone and the watch share them.
@MainActor
final class Library: ObservableObject {
    static let shared = Library()

    @Published private(set) var favorites: [SavedItem] = []
    @Published private(set) var recents: [SavedItem] = []

    private let file: URL
    /// When each recent item was last played, for merging history from the other device.
    private var recentTimes: [String: Double] = [:]
    private var recentsClearedAt: Double = 0

    private struct Stored: Codable {
        var favorites: [SavedItem]
        var recents: [SavedItem]
        var recentTimes: [String: Double]?
        var recentsClearedAt: Double?
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
            recentTimes = stored.recentTimes ?? [:]
            recentsClearedAt = stored.recentsClearedAt ?? 0
        }
        // History saved before syncing existed has no times: keep its order, older than anything new.
        let base = Date().timeIntervalSince1970 - 30_000_000
        for (index, item) in recents.enumerated() where recentTimes[item.id] == nil {
            recentTimes[item.id] = base - Double(index)
        }
        startCloudSync()
    }

    func isFavorite(_ item: SavedItem) -> Bool { favorites.contains { $0.id == item.id } }

    func toggleFavorite(_ item: SavedItem) {
        if let index = favorites.firstIndex(where: { $0.id == item.id }) {
            favorites.remove(at: index)
        } else {
            favorites.insert(item, at: 0)
        }
        save()
        pushFavoritesToCloud()
    }

    func removeFavorites(at offsets: IndexSet) {
        favorites.remove(atOffsets: offsets)
        save()
        pushFavoritesToCloud()
    }

    /// Hand-arranged order; the widget shows favourite stations in this order too.
    func moveFavorites(from offsets: IndexSet, to destination: Int) {
        favorites.move(fromOffsets: offsets, toOffset: destination)
        save()
        pushFavoritesToCloud()
    }

    func addRecent(_ item: SavedItem) {
        recents.removeAll { $0.id == item.id }
        recents.insert(item, at: 0)
        if recents.count > 30 { recents.removeLast(recents.count - 30) }
        recentTimes[item.id] = Date().timeIntervalSince1970
        recentTimes = recentTimes.filter { id, _ in recents.contains { $0.id == id } }
        save()
        pushRecentsToCloud()
    }

    func clearRecents() {
        recents = []
        recentTimes = [:]
        recentsClearedAt = Date().timeIntervalSince1970
        save()
        pushRecentsToCloud()
    }

    /// Any favourite or recent item by its id; used by widget deep links.
    func item(withID id: String) -> SavedItem? {
        favorites.first { $0.id == id } ?? recents.first { $0.id == id }
    }

    // MARK: iCloud

    private static let cloudKey = "favorites.v1"
    private static let joinedKey = "favorites.joinedCloud"
    private var cloudObserver: NSObjectProtocol?

    private func startCloudSync() {
        guard !Demo.isOn else { return }
        let cloud = NSUbiquitousKeyValueStore.default
        cloudObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: cloud, queue: .main
        ) { [weak self] note in
            let keys = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []
            Task { @MainActor in
                if keys.contains(Self.cloudKey) { self?.pullFavoritesFromCloud() }
                if keys.contains(Self.recentsKey) { self?.pullRecentsFromCloud() }
            }
        }
        cloud.synchronize()
        pullFavoritesFromCloud()
        pullRecentsFromCloud()
        ResumeSync.start()
    }

    // History: both devices' items, newest first; clearing on one clears both.
    private static let recentsKey = "recents.v1"
    private struct CloudRecents: Codable {
        var items: [SavedItem]
        var times: [String: Double]
        var clearedAt: Double
    }

    private func pullRecentsFromCloud() {
        guard let data = NSUbiquitousKeyValueStore.default.data(forKey: Self.recentsKey),
              let remote = try? JSONDecoder().decode(CloudRecents.self, from: data) else {
            if !recents.isEmpty { pushRecentsToCloud() }
            return
        }
        let cleared = max(recentsClearedAt, remote.clearedAt)
        var times = recentTimes
        var byID: [String: SavedItem] = Dictionary(recents.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for item in remote.items {
            let t = remote.times[item.id] ?? 0
            if t >= (times[item.id] ?? 0) { byID[item.id] = item; times[item.id] = t }
        }
        let merged = byID.values
            .filter { (times[$0.id] ?? 0) > cleared }
            .sorted { (times[$0.id] ?? 0) > (times[$1.id] ?? 0) }
            .prefix(30)
        let newRecents = Array(merged)
        recentsClearedAt = cleared
        recentTimes = times.filter { id, _ in newRecents.contains { $0.id == id } }
        if newRecents != recents {
            recents = newRecents
            save()
        }
        if newRecents != remote.items || cleared != remote.clearedAt { pushRecentsToCloud() }
    }

    private func pushRecentsToCloud() {
        guard !Demo.isOn,
              let data = try? JSONEncoder().encode(CloudRecents(items: recents, times: recentTimes, clearedAt: recentsClearedAt))
        else { return }
        let cloud = NSUbiquitousKeyValueStore.default
        cloud.set(data, forKey: Self.recentsKey)
        cloud.synchronize()
    }

    /// The first time on a device its own favourites are added to the shared list;
    /// after that the shared list is the truth, so a removal on one device removes everywhere.
    private func pullFavoritesFromCloud() {
        let defaults = UserDefaults.standard
        let joined = defaults.bool(forKey: Self.joinedKey)
        guard let data = NSUbiquitousKeyValueStore.default.data(forKey: Self.cloudKey),
              let remote = try? JSONDecoder().decode([SavedItem].self, from: data) else {
            if !joined, !favorites.isEmpty { pushFavoritesToCloud() }
            return
        }
        let merged = joined ? remote : remote + favorites.filter { mine in !remote.contains { $0.id == mine.id } }
        defaults.set(true, forKey: Self.joinedKey)
        if merged != favorites {
            favorites = merged
            save()
        }
        if merged != remote { pushFavoritesToCloud() }
    }

    private func pushFavoritesToCloud() {
        guard !Demo.isOn, let data = try? JSONEncoder().encode(favorites) else { return }
        let cloud = NSUbiquitousKeyValueStore.default
        cloud.set(data, forKey: Self.cloudKey)
        cloud.synchronize()
        UserDefaults.standard.set(true, forKey: Self.joinedKey)
    }

    private func save() {
        guard !Demo.isOn else { return }
        if let data = try? JSONEncoder().encode(Stored(favorites: favorites, recents: recents, recentTimes: recentTimes, recentsClearedAt: recentsClearedAt)) {
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
