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
}

@MainActor
final class DownloadStore: ObservableObject {
    static let shared = DownloadStore()

    @Published private(set) var items: [DownloadedItem] = []
    @Published private(set) var inProgress: Set<String> = []
    @Published var lastError: String?

    private let folder: URL
    private let indexFile: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        folder = docs.appendingPathComponent("Downloads", isDirectory: true)
        indexFile = docs.appendingPathComponent("downloads.json")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: indexFile),
           let saved = try? JSONDecoder().decode([DownloadedItem].self, from: data) {
            items = saved
        }
    }

    static func key(for track: Track) -> String {
        if !track.FileID.isEmpty { return track.FileID }
        if !track.FileKey.isEmpty { return track.FileKey }
        return String(track.playUrl.hashValue)
    }

    func canDownload(_ track: Track) -> Bool {
        track.download.contains { !$0.downloadUrl.isEmpty }
    }

    func isDownloaded(_ track: Track) -> Bool {
        items.contains { $0.id == Self.key(for: track) }
    }

    func localFile(for track: Track) -> URL? {
        guard let item = items.first(where: { $0.id == Self.key(for: track) }) else { return nil }
        let url = folder.appendingPathComponent(item.fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func fileURL(for item: DownloadedItem) -> URL { folder.appendingPathComponent(item.fileName) }

    func download(_ track: Track, from album: PlayerDetail) {
        let key = Self.key(for: track)
        guard !inProgress.contains(key), !isDownloaded(track),
              let option = track.download.first(where: { !$0.downloadUrl.isEmpty }),
              let url = API.resolve(option.downloadUrl) else { return }
        inProgress.insert(key)
        Task {
            defer { inProgress.remove(key) }
            do {
                let (temp, response) = try await URLSession.shared.download(from: url)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    throw API.Failure.http(http.statusCode)
                }
                let ext = option.`extension`.isEmpty ? "mp4" : option.`extension`
                let name = "\(key).\(ext)"
                let target = folder.appendingPathComponent(name)
                try? FileManager.default.removeItem(at: target)
                try FileManager.default.moveItem(at: temp, to: target)
                items.append(DownloadedItem(
                    id: key,
                    title: track.name.isEmpty ? album.displayTitle : track.name,
                    album: album.displayTitle,
                    image: album.cover,
                    fileName: name,
                    durationMs: track.duration))
                save()
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func delete(_ item: DownloadedItem) {
        try? FileManager.default.removeItem(at: fileURL(for: item))
        items.removeAll { $0.id == item.id }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) { try? data.write(to: indexFile, options: .atomic) }
    }
}
