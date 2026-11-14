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

    static func get<T: Decodable>(_ type: T.Type, _ link: String) async throws -> T {
        if Demo.isOn {
            return try JSONDecoder().decode(T.self, from: sanitize(Demo.data(for: link)))
        }
        guard let url = resolve(link) else { throw Failure.badURL(link) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw Failure.http(http.statusCode)
        }
        guard !data.isEmpty else { throw Failure.empty }
        return try JSONDecoder().decode(T.self, from: sanitize(data))
    }
}
