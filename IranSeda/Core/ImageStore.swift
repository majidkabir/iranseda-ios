import CryptoKit
import ImageIO
import UIKit

/// Image cache: memory first, then files in Caches/Images, then the network.
/// The server's own cache headers are ignored, because covers and logos rarely change.
actor ImageStore {
    static let shared = ImageStore()

    /// Thread-safe, so views can check it synchronously and skip the placeholder flash.
    nonisolated static let memory: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 64 << 20
        return cache
    }()

    private let folder: URL
    private var inflight: [URL: Task<UIImage?, Never>] = [:]
    private static let maxAge: TimeInterval = 30 * 24 * 3600

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        folder = caches.appendingPathComponent("Images", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    nonisolated static func cached(_ url: URL) -> UIImage? {
        memory.object(forKey: url.absoluteString as NSString)
    }

    func image(for url: URL) async -> UIImage? {
        let key = url.absoluteString as NSString
        if let hit = Self.memory.object(forKey: key) { return hit }

        let file = fileURL(for: url)
        if let data = try? Data(contentsOf: file), let image = Self.decode(data) {
            Self.remember(image, key: key)
            return image
        }

        if let running = inflight[url] { return await running.value }
        let task = Task<UIImage?, Never> {
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
                  let image = Self.decode(data) else { return nil }
            try? data.write(to: file, options: .atomic)
            Self.remember(image, key: key)
            return image
        }
        inflight[url] = task
        let image = await task.value
        inflight[url] = nil
        return image
    }

    /// Bytes used on disk.
    func diskBytes() -> Int64 {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    func clear() {
        Self.memory.removeAllObjects()
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    /// Drops files not touched for a month. Called once at launch.
    func prune() {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? []
        let cutoff = Date().addingTimeInterval(-Self.maxAge)
        for file in files {
            if let date = try? file.resourceValues(forKeys: Set(keys)).contentModificationDate, date < cutoff {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    private func fileURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        return folder.appendingPathComponent(digest.map { String(format: "%02x", $0) }.joined())
    }

    /// Decodes no larger than the app ever shows a picture, so big covers do not eat memory.
    private static func decode(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return UIImage(data: data)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 900,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return UIImage(data: data)
        }
        return UIImage(cgImage: cgImage)
    }

    private static func remember(_ image: UIImage, key: NSString) {
        let cost = (image.cgImage.map { $0.bytesPerRow * $0.height }) ?? 1
        memory.setObject(image, forKey: key, cost: cost)
    }
}
