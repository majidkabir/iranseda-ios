import SwiftUI

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

struct SearchView: View {
    @StateObject private var model = SearchModel()
    @State private var query: String
    private let preview = 5

    init(initialQuery: String = "") {
        _query = State(initialValue: initialQuery)
    }

    var body: some View {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let stations = model.matchingChannels(trimmed)
        let found = model.hubs.filter { !$0.boxes.isEmpty }
        let failed = model.hubs.filter(\.failed)
        Group {
            if trimmed.count < 2 {
                ContentUnavailableView {
                    Label("جست‌وجو در ایران‌صدا", systemImage: "magnifyingglass")
                } description: {
                    Text("نام کتاب، نویسنده، راوی، برنامه یا شبکه را بنویسید.")
                }
            } else if stations.isEmpty && found.isEmpty && !model.isSearching && model.searched == trimmed {
                if failed.isEmpty {
                    ContentUnavailableView.search(text: trimmed)
                } else {
                    ContentUnavailableView {
                        Label("جست‌وجو انجام نشد", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text("سرور پاسخ نداد. دوباره تلاش کنید.")
                    } actions: {
                        Button("تلاش دوباره") { retry(trimmed) }.buttonStyle(.borderedProminent)
                    }
                }
            } else {
                List {
                    if !stations.isEmpty {
                        Section("شبکه‌های رادیویی") {
                            ForEach(stations) { channel in
                                NavigationLink { ChannelView(channel: channel) } label: {
                                    row(image: channel.logo, title: channel.title, subtitle: channel.name, symbol: "dot.radiowaves.left.and.right")
                                }
                            }
                        }
                    }
                    ForEach(found) { hub in
                        Section(hub.title) {
                            ForEach(Array(hub.boxes.prefix(preview).enumerated()), id: \.offset) { _, box in
                                NavigationLink {
                                    LinkDestination(urlType: box.URLType, url: box.URL, title: box.title)
                                } label: {
                                    row(image: box.image, title: box.title, subtitle: box.subtitle, symbol: "headphones",
                                        urlType: box.URLType, link: box.URL)
                                }
                                .favoriteSwipe(box)
                            }
                            if hub.boxes.count > preview || hub.hasMore {
                                NavigationLink {
                                    FeedScreen(url: hub.link, title: "«\(trimmed)» در \(hub.title)", asList: true)
                                } label: {
                                    Label(hub.hasMore ? "همه نتایج" : "همه \(Format.fa(hub.boxes.count)) نتیجه", systemImage: "list.bullet")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                    if model.isSearching || model.searched != trimmed {
                        Section {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text(progressText).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .listRowBackground(Color.clear)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "کتاب، راوی، برنامه، شبکه…")
        .autocorrectionDisabled()
        .onSubmit(of: .search) { model.search(query) }
        .navigationTitle("جست‌وجو")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.prepare() }
        // Search a moment after typing stops, so each keystroke is not a request.
        .task(id: query) {
            try? await Task.sleep(nanoseconds: 700_000_000)
            if !Task.isCancelled { model.search(query) }
        }
    }

    private var progressText: String {
        if let hub = model.hubs.first(where: \.isLoading) { return "در حال جست‌وجو در \(hub.title)…" }
        return "در حال جست‌وجو…"
    }

    private func retry(_ text: String) {
        model.search("")
        model.search(text)
    }

    private func row(image: String, title: String, subtitle: String, symbol: String,
                     urlType: String = "", link: String = "") -> some View {
        HStack(spacing: 12) {
            Artwork(link: image, title: title, symbol: symbol)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium)).lineLimit(2)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                VoiceLine(urlType: urlType, link: link)
            }
        }
    }
}
