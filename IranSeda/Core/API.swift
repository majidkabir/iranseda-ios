import Foundation

/// Client for the Iran Seda app API (apisec.iranseda.ir).
/// The API is server-driven: every screen is reached by following a URL the
/// previous response handed out, so URLs are never built by hand here.
enum API {
    static let base = "https://apisec.iranseda.ir"
    static let initPath = "/initv8/?VALID=TRUE"
    static let radioPath = "/radio/"

    enum Failure: LocalizedError {
        case badURL(String)
        case http(Int)
        case empty

        var errorDescription: String? {
            switch self {
            case .badURL: return "نشانی نامعتبر است"
            case .http(let code): return "سرور پاسخ \(code) داد"
            case .empty: return "پاسخی دریافت نشد"
            }
        }
    }

    /// Turns any link found in a response into a loadable URL.
    /// - `http://api.iranseda.ir/...` is the same API over plain HTTP; use the HTTPS host.
    /// - links starting with `/` are relative to the API host.
    static func resolve(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if s.hasPrefix("http://api.iranseda.ir") {
            s = base + s.dropFirst("http://api.iranseda.ir".count)
        } else if s.hasPrefix("/") {
            s = base + s
        } else if !s.contains("://") {
            s = base + "/" + s
        }
        if let url = URL(string: s) { return url }
        let allowed = CharacterSet.urlQueryAllowed.union(.urlPathAllowed).union(CharacterSet(charactersIn: "#%"))
        return s.addingPercentEncoding(withAllowedCharacters: allowed).flatMap(URL.init(string:))
    }

    /// The server sends JSON with raw tabs/newlines inside strings and the odd
    /// trailing comma, which `JSONDecoder` rejects. Clean both before decoding.
    static func sanitize(_ data: Data) -> Data {
        guard var text = String(data: data, encoding: .utf8) else { return data }
        text = String(String.UnicodeScalarView(text.unicodeScalars.map { $0.value < 0x20 ? " " : $0 }))
        text = text.replacingOccurrences(of: ",(\\s*[\\]}])", with: "$1", options: .regularExpression)
        return Data(text.utf8)
    }

    /// No cookies: with a session cookie the server answers one request at a time.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 25
        return URLSession(configuration: config)
    }()

    /// Set while the user pulls to refresh: skip the short-lived cache.
    @TaskLocal static var wantsFresh = false

    /// Links whose answer changes by the minute or carries a stream address: never served from cache.
    private static func isVolatile(_ link: String) -> Bool {
        let l = link.lowercased()
        return ["liveplayer", "playby", "currentprogdata", "programlastepisode", "epgarchivelist"].contains { l.contains($0) }
    }

    static func get<T: Decodable>(_ type: T.Type, _ link: String) async throws -> T {
        if Demo.isOn {
            return try JSONDecoder().decode(T.self, from: sanitize(Demo.data(for: link)))
        }
        guard let url = resolve(link) else { throw Failure.badURL(link) }
        let key = url.absoluteString
        let volatile = isVolatile(link)

        if !volatile, !wantsFresh, let data = await ResponseCache.shared.recent(key),
           let value = try? JSONDecoder().decode(T.self, from: data) {
            return value
        }
        do {
            let (raw, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw Failure.http(http.statusCode)
            }
            guard !raw.isEmpty else { throw Failure.empty }
            let data = sanitize(raw)
            let value = try JSONDecoder().decode(T.self, from: data)
            if !volatile { await ResponseCache.shared.store(data, for: key) }
            return value
        } catch {
            // Offline or the server is down: show the last good answer rather than an error.
            let cancelled = error is CancellationError || (error as? URLError)?.code == .cancelled
            if !cancelled, !volatile, let data = await ResponseCache.shared.any(key),
               let value = try? JSONDecoder().decode(T.self, from: data) {
                return value
            }
            throw error
        }
    }
}

/// Answers kept for two minutes in memory (so going back and forth is instant) and on disk
/// as a fallback for when the network fails.
actor ResponseCache {
    static let shared = ResponseCache()

    private var memory: [String: (data: Data, at: Date)] = [:]
    private let folder: URL
    private let lifetime: TimeInterval = 120

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        folder = caches.appendingPathComponent("API", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func recent(_ key: String) -> Data? {
        guard let hit = memory[key], Date().timeIntervalSince(hit.at) < lifetime else { return nil }
        return hit.data
    }

    func any(_ key: String) -> Data? {
        memory[key]?.data ?? (try? Data(contentsOf: file(for: key)))
    }

    func store(_ data: Data, for key: String) {
        if memory.count > 80 { memory.removeAll() }
        memory[key] = (data, Date())
        if data.count < 3_000_000 { try? data.write(to: file(for: key), options: .atomic) }
    }

    private func file(for key: String) -> URL {
        let hash = key.unicodeScalars.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1.value)) &* 1099511628211 }
        return folder.appendingPathComponent(String(hash, radix: 16) + ".json")
    }
}
