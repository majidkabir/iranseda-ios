import SwiftUI

/// One thing search can find in a hub's shelves.
struct SearchEntry: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let image: String
    let url: String
    let urlType: String
    let group: String
    let key: String
}

/// Search index built on the device.
///
/// The service's own search call is not known, so this searches what the app can
/// already see: every station, plus everything on the front shelves of each hub.
@MainActor
final class SearchIndex: ObservableObject {
    static let shared = SearchIndex()

    @Published private(set) var entries: [SearchEntry] = []
    @Published private(set) var channels: [Channel] = []
    @Published private(set) var isLoading = false
    private var loaded = false

    func load() async {
        guard !loaded, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        async let radio = try? API.get(RadioList.self, API.radioPath)
        guard let config = try? await API.get(InitConfig.self, API.initPath) else {
            channels = await radio?.channels ?? []
            return
        }
        channels = await radio?.channels ?? []

        // One request per hub: the first tab is the hub's front page.
        let hubs: [(title: String, feed: String)] = config.Base
            .filter { $0.UrlType == "base" }
            .compactMap { hub in
                let usable = hub.tabs.filter { !$0.FeedAddress.isEmpty }
                let tab = usable.first { $0.TabEnabled == "1" } ?? usable.first
                return tab.map { (hub.title, $0.FeedAddress) }
            }

        var found: [SearchEntry] = []
        var seen = Set<String>()
        await withTaskGroup(of: (String, FeedPage?).self) { group in
            for hub in hubs {
                let title = hub.title, feed = hub.feed
                group.addTask { (title, try? await API.get(FeedPage.self, feed)) }
            }
            for await (hubTitle, page) in group {
                for box in page?.Containers.flatMap(\.boxes) ?? [] where !box.URL.isEmpty && !box.title.isEmpty {
                    guard seen.insert(box.URL).inserted else { continue }
                    found.append(SearchEntry(
                        id: box.URL, title: box.title, subtitle: box.subtitle, image: box.image,
                        url: box.URL, urlType: box.URLType, group: hubTitle,
                        key: Self.normalize(box.title + " " + box.subtitle)))
                }
            }
        }
        entries = found
        loaded = true
    }

    /// Makes Arabic and Persian spellings of the same word compare equal.
    static func normalize(_ text: String) -> String {
        var out = text.lowercased()
        for (from, to) in [("ي", "ی"), ("ى", "ی"), ("ك", "ک"), ("ة", "ه"), ("أ", "ا"), ("إ", "ا"), ("آ", "ا"), ("\u{200C}", " "), ("\u{200F}", "")] {
            out = out.replacingOccurrences(of: from, with: to)
        }
        return out.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }

    func matchingChannels(_ query: String) -> [Channel] {
        let needle = Self.normalize(query)
        guard !needle.isEmpty else { return [] }
        return channels.filter { Self.normalize($0.title + " " + $0.name).contains(needle) }
    }

    /// Matches grouped by hub, in the order hubs were first seen, capped per hub.
    func matches(_ query: String) -> [(group: String, items: [SearchEntry])] {
        let words = Self.normalize(query).components(separatedBy: " ").filter { !$0.isEmpty }
        guard !words.isEmpty else { return [] }
        var order: [String] = []
        var map: [String: [SearchEntry]] = [:]
        for entry in entries where words.allSatisfy({ entry.key.contains($0) }) {
            if map[entry.group] == nil { order.append(entry.group) }
            if (map[entry.group]?.count ?? 0) < 25 { map[entry.group, default: []].append(entry) }
        }
        return order.map { (group: $0, items: map[$0] ?? []) }
    }
}

struct SearchView: View {
    @StateObject private var index = SearchIndex.shared
    @State private var query: String

    init(initialQuery: String = "") {
        _query = State(initialValue: initialQuery)
    }

    var body: some View {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let stations = index.matchingChannels(trimmed)
        let groups = index.matches(trimmed)
        Group {
            if trimmed.isEmpty {
                ContentUnavailableView {
                    Label("جست‌وجو در ایران‌صدا", systemImage: "magnifyingglass")
                } description: {
                    Text("نام شبکه، کتاب، پادکست یا برنامه را بنویسید. جست‌وجو میان شبکه‌ها و قفسه‌های صفحه اول هر پایگاه انجام می‌شود.")
                }
            } else if stations.isEmpty && groups.isEmpty {
                if index.isLoading {
                    ProgressView("در حال آماده‌سازی جست‌وجو…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView.search(text: trimmed)
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
                    ForEach(groups, id: \.group) { group in
                        Section(group.group) {
                            ForEach(group.items) { entry in
                                NavigationLink {
                                    LinkDestination(urlType: entry.urlType, url: entry.url, title: entry.title)
                                } label: {
                                    row(image: entry.image, title: entry.title, subtitle: entry.subtitle, symbol: "headphones")
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "شبکه، کتاب، پادکست…")
        .autocorrectionDisabled()
        .navigationTitle("جست‌وجو")
        .navigationBarTitleDisplayMode(.inline)
        .task { await index.load() }
    }

    private func row(image: String, title: String, subtitle: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Artwork(link: image, title: title, symbol: symbol)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium)).lineLimit(2)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }
}
