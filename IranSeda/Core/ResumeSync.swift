import Foundation

/// Listening positions shared through iCloud between the iPhone and the watch: how far into
/// each file you are, and how much of each book you have heard. Per entry, the newest change wins.
@MainActor
enum ResumeSync {
    private struct Entry: Codable {
        var v: Double       // seconds or fraction; 0 means "cleared"
        var at: Double      // when it changed (seconds since 1970)
    }

    private static let cloudKey = "resume.v1"
    private static let localKey = "resume.sync"
    private static let limit = 400
    private static var entries: [String: Entry] = {
        guard let data = UserDefaults.standard.data(forKey: localKey),
              let saved = try? JSONDecoder().decode([String: Entry].self, from: data) else { return [:] }
        return saved
    }()
    private static var started = false
    private static var pushTask: Task<Void, Never>?

    static func start() {
        guard !started, !Demo.isOn else { return }
        started = true
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default, queue: .main
        ) { note in
            let keys = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []
            guard keys.contains(cloudKey) else { return }
            Task { @MainActor in pull() }
        }
        pull()
    }

    static func set(_ value: Double, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
        record(value, key)
    }

    static func remove(_ key: String) {
        UserDefaults.standard.removeObject(forKey: key)
        record(0, key)
    }

    private static func record(_ value: Double, _ key: String) {
        guard !Demo.isOn else { return }
        entries[key] = Entry(v: value, at: Date().timeIntervalSince1970)
        saveLocal()
        // Positions change every few seconds while playing; send them at most twice a minute.
        guard pushTask == nil else { return }
        pushTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            pushTask = nil
            push()
        }
    }

    private static func pull() {
        guard let data = NSUbiquitousKeyValueStore.default.data(forKey: cloudKey),
              let remote = try? JSONDecoder().decode([String: Entry].self, from: data) else {
            if !entries.isEmpty { push() }
            return
        }
        var changed = false
        for (key, entry) in remote where entry.at > (entries[key]?.at ?? 0) {
            entries[key] = entry
            if entry.v > 0 {
                UserDefaults.standard.set(entry.v, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
            changed = true
        }
        if changed { saveLocal() }
        // This device has something newer than iCloud: send it.
        if entries.contains(where: { key, entry in entry.at > (remote[key]?.at ?? 0) }) { push() }
    }

    private static func push() {
        trim()
        guard let data = try? JSONEncoder().encode(entries) else { return }
        let cloud = NSUbiquitousKeyValueStore.default
        cloud.set(data, forKey: cloudKey)
        cloud.synchronize()
    }

    private static func trim() {
        guard entries.count > limit else { return }
        let keep = entries.sorted { $0.value.at > $1.value.at }.prefix(limit)
        entries = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        saveLocal()
    }

    private static func saveLocal() {
        if let data = try? JSONEncoder().encode(entries) { UserDefaults.standard.set(data, forKey: localKey) }
    }
}
