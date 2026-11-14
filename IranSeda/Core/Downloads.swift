import Foundation
import SwiftUI

/// Offline files. Each track's `download` list carries a direct file link;
/// the file is saved in Documents/Downloads and indexed in downloads.json.
struct DownloadedItem: Codable, Identifiable {
    var id: String          // track key
    var title: String
    var album: String
    var image: String
    var fileName: String
    var durationMs: String
    var bytes: Int64?
}

@MainActor
final class DownloadStore: ObservableObject {
    static let shared = DownloadStore()

    @Published private(set) var items: [DownloadedItem] = []
    /// Fraction done (0...1) for every download in flight, by track key.
    @Published private(set) var progress: [String: Double] = [:]
    @Published var lastError: String?

    private let folder: URL
    private let indexFile: URL
    private var observations: [String: NSKeyValueObservation] = [:]
    private var tasks: [String: URLSessionDownloadTask] = [:]

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        folder = docs.appendingPathComponent("Downloads", isDirectory: true)
        indexFile = docs.appendingPathComponent("downloads.json")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if Demo.isOn {
            items = Demo.downloads
        } else if let data = try? Data(contentsOf: indexFile),
                  let saved = try? JSONDecoder().decode([DownloadedItem].self, from: data) {
            items = saved
        }
    }

    static func key(for track: Track) -> String {
        if !track.FileID.isEmpty { return track.FileID }
        if !track.FileKey.isEmpty { return track.FileKey }
        return String(track.playUrl.unicodeScalars.reduce(UInt64(5381)) { ($0 &* 33) &+ UInt64($1.value) })
    }

    var totalBytes: Int64 { items.reduce(0) { $0 + ($1.bytes ?? 0) } }

    func canDownload(_ track: Track) -> Bool { track.download.contains { !$0.downloadUrl.isEmpty } }
    func isDownloaded(_ track: Track) -> Bool { items.contains { $0.id == Self.key(for: track) } }
    func fraction(for track: Track) -> Double? { progress[Self.key(for: track)] }

    func localFile(for track: Track) -> URL? {
        guard let item = items.first(where: { $0.id == Self.key(for: track) }) else { return nil }
        let url = folder.appendingPathComponent(item.fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func fileURL(for item: DownloadedItem) -> URL { folder.appendingPathComponent(item.fileName) }

    func downloadAll(of album: PlayerDetail) {
        for track in album.items where canDownload(track) { download(track, from: album) }
    }

    func download(_ track: Track, from album: PlayerDetail) {
        let key = Self.key(for: track)
        guard progress[key] == nil, !isDownloaded(track), !Demo.isOn,
              let option = track.download.first(where: { !$0.downloadUrl.isEmpty }),
              let url = API.resolve(option.downloadUrl) else { return }
        let ext = option.`extension`.isEmpty ? "mp4" : option.`extension`
        let name = "\(key).\(ext)"
        let target = folder.appendingPathComponent(name)
        let entry = DownloadedItem(
            id: key,
            title: track.name.isEmpty ? album.displayTitle : track.name,
            album: album.displayTitle,
            image: album.cover,
            fileName: name,
            durationMs: track.duration,
            bytes: nil)

        progress[key] = 0
        let task = URLSession.shared.downloadTask(with: url) { [weak self] temp, response, error in
            // The temporary file disappears when this handler returns, so move it here.
            var failure: String?
            var size: Int64?
            if let error {
                failure = (error as NSError).code == NSURLErrorCancelled ? nil : error.localizedDescription
                if (error as NSError).code == NSURLErrorCancelled { failure = "" }
            } else if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                failure = "سرور پاسخ \(http.statusCode) داد"
            } else if let temp {
                do {
                    try? FileManager.default.removeItem(at: target)
                    try FileManager.default.moveItem(at: temp, to: target)
                    size = (try? FileManager.default.attributesOfItem(atPath: target.path)[.size] as? NSNumber)?.int64Value
                } catch {
                    failure = error.localizedDescription
                }
            } else {
                failure = "دانلود ناموفق بود"
            }
            let outcome = failure
            let bytes = size
            Task { @MainActor in self?.finish(key: key, entry: entry, bytes: bytes, failure: outcome) }
        }
        observations[key] = task.progress.observe(\.fractionCompleted) { [weak self] value, _ in
            let fraction = value.fractionCompleted
            Task { @MainActor in
                if self?.progress[key] != nil { self?.progress[key] = fraction }
            }
        }
        tasks[key] = task
        task.resume()
    }

    func cancel(_ track: Track) {
        tasks[Self.key(for: track)]?.cancel()
    }

    private func finish(key: String, entry: DownloadedItem, bytes: Int64?, failure: String?) {
        progress[key] = nil
        observations[key] = nil
        tasks[key] = nil
        if let failure {
            if !failure.isEmpty { lastError = failure }   // empty = cancelled by the user
            return
        }
        var done = entry
        done.bytes = bytes
        items.removeAll { $0.id == key }
        items.append(done)
        save()
    }

    func delete(_ item: DownloadedItem) {
        try? FileManager.default.removeItem(at: fileURL(for: item))
        items.removeAll { $0.id == item.id }
        save()
    }

    func deleteAll() {
        for item in items { try? FileManager.default.removeItem(at: fileURL(for: item)) }
        items = []
        save()
    }

    private func save() {
        guard !Demo.isOn else { return }
        if let data = try? JSONEncoder().encode(items) { try? data.write(to: indexFile, options: .atomic) }
    }
}
