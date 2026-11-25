import Combine
import Foundation

/// Search across the service: stations are matched on the device, and every hub is asked
/// through its own search call (`<hub>/search/?t=<text>`), the same one the website uses.
@MainActor
final class SearchModel: ObservableObject {
    struct HubResult: Identifiable {
        let id: String
        let title: String
        let link: String          // the hub's search link, for "show all"
        var boxes: [FeedBox] = []
        var hasMore = false
        var isLoading = true
        var failed = false
    }

    @Published private(set) var hubs: [HubResult] = []
    @Published private(set) var channels: [Channel] = []
    @Published private(set) var searched = ""
    @Published private(set) var isSearching = false
    private var sources: [(id: String, title: String, base: String)] = []
    private var run: Task<Void, Never>?

    /// Stations and the list of hubs; loaded once.
    func prepare() async {
        guard sources.isEmpty else { return }
        async let radio = try? API.get(RadioList.self, API.radioPath)
        if let config = try? await API.get(InitConfig.self, API.initPath) {
            sources = config.Base
                .filter { $0.UrlType == "base" && !$0.UrlAddress.isEmpty }
                .map { (id: $0.Id, title: $0.title, base: $0.UrlAddress.hasSuffix("/") ? $0.UrlAddress : $0.UrlAddress + "/") }
        }
        channels = await radio?.channels ?? []
    }

    func matchingChannels(_ query: String) -> [Channel] {
        let needle = Self.normalize(query)
        guard !needle.isEmpty else { return [] }
        return channels.filter { Self.normalize($0.title + " " + $0.name).contains(needle) }
    }

    func search(_ text: String) {
        let query = text.trimmingCharacters(in: .whitespaces)
        guard query != searched else { return }
        run?.cancel()
        searched = query
        hubs = []
        guard query.count >= 2 else { isSearching = false; return }

        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?#")
        let term = query.addingPercentEncoding(withAllowedCharacters: allowed) ?? query
        isSearching = true

        run = Task {
            await prepare()
            if Task.isCancelled { return }
            hubs = sources.map { HubResult(id: $0.id, title: $0.title, link: $0.base + "search/?t=" + term) }
            // The server answers searches slowly and one at a time, so ask hub by hub.
            for hub in hubs {
                let page = try? await API.get(FeedPage.self, hub.link)
                if Task.isCancelled { return }
                guard let index = hubs.firstIndex(where: { $0.id == hub.id }) else { continue }
                hubs[index].isLoading = false
                if let page {
                    var seen = Set<String>()
                    hubs[index].boxes = page.Containers.flatMap(\.boxes).filter { !$0.URL.isEmpty && seen.insert($0.URL).inserted }
                    hubs[index].hasMore = page.hasMore
                } else {
                    hubs[index].failed = true
                }
            }
            isSearching = false
        }
    }

    /// Makes Arabic and Persian spellings of the same word compare equal.
    static func normalize(_ text: String) -> String {
        var out = text.lowercased()
        for (from, to) in [("ي", "ی"), ("ى", "ی"), ("ك", "ک"), ("ة", "ه"), ("أ", "ا"), ("إ", "ا"), ("آ", "ا"), ("\u{200C}", " "), ("\u{200F}", "")] {
            out = out.replacingOccurrences(of: from, with: to)
        }
        return out.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }
}
