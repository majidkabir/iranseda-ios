import SwiftUI

private struct HomeData {
    var config: InitConfig
    var channels: [Channel]
}

/// First screen: continue listening, favourite stations, live radio, and the content hubs.
struct HomeView: View {
    @EnvironmentObject private var library: Library

    var body: some View {
        Loader(load: load) { data in
            let hubs = data.config.Base.filter { $0.UrlType == "base" && !$0.tabs.isEmpty }
            let national = data.channels.filter { $0.typeTitle == (data.channels.first?.typeTitle ?? "") }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    if !library.recents.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "ادامه شنیدن")
                            shelf(library.recents.prefix(10).map { $0 }) { item in
                                SavedCard(item: item)
                            }
                        }
                    }

                    if !national.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "پخش زنده", more: "همه شبکه‌ها") { RadioView() }
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(alignment: .top, spacing: 14) {
                                    ForEach(national) { channel in
                                        NavigationLink { ChannelView(channel: channel) } label: {
                                            StationBubble(channel: channel)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, Theme.gutter)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "پایگاه‌ها")
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                            ForEach(hubs) { hub in
                                NavigationLink { HubView(hub: hub) } label: { HubTile(hub: hub) }
                                    .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, Theme.gutter)
                    }
                }
                .padding(.vertical, 12)
            }
        }
        .navigationTitle("ایران‌صدا")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { SearchView() } label: { Image(systemName: "magnifyingglass") }
                    .accessibilityLabel("جست‌وجو")
            }
        }
    }

    private func load() async throws -> HomeData {
        async let config = API.get(InitConfig.self, API.initPath)
        async let radio = try? API.get(RadioList.self, API.radioPath)
        let loadedConfig = try await config
        let loadedRadio = await radio
        return HomeData(config: loadedConfig, channels: loadedRadio?.channels ?? [])
    }

    private func shelf<Item: Identifiable, Card: View>(_ items: [Item], @ViewBuilder card: @escaping (Item) -> Card) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 12) {
                ForEach(items) { card($0) }
            }
            .padding(.horizontal, Theme.gutter)
        }
    }
}

/// A recently played or favourite item as a small card.
struct SavedCard: View {
    let item: SavedItem

    var body: some View {
        NavigationLink { SavedItemDestination(item: item) } label: {
            VStack(alignment: .leading, spacing: 6) {
                Artwork(link: item.image, title: item.title, symbol: item.kind == .channel ? "dot.radiowaves.left.and.right" : "headphones")
                    .frame(width: 132, height: 132)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
                Text(item.title).font(.subheadline.weight(.medium)).lineLimit(1)
                Text(item.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(width: 132, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}

private struct StationBubble: View {
    let channel: Channel

    var body: some View {
        VStack(spacing: 8) {
            Artwork(link: channel.logo, title: channel.title, symbol: "dot.radiowaves.left.and.right")
                .frame(width: 72, height: 72)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(.quaternary))
            Text(channel.title.replacingOccurrences(of: "رادیو ", with: ""))
                .font(.caption.weight(.medium))
                .lineLimit(1)
        }
        .frame(width: 80)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(channel.title)
    }
}

private struct HubTile: View {
    let hub: Hub

    private var symbol: String? {
        switch hub.Id {
        case "1021": return "book.fill"
        case "1027": return "mic.fill"
        case "1023": return "music.note"
        case "1026": return "teddybear.fill"
        case "1022": return "book.closed.fill"
        case "1024": return "person.wave.2.fill"
        case "1025": return "moon.stars.fill"
        case "1029": return "clock.arrow.circlepath"
        default: return nil
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Theme.gradient(for: hub.title), in: RoundedRectangle(cornerRadius: 12))
            } else {
                // Hubs the app has no symbol for (station sites and the like) show the service's own logo.
                Artwork(link: hub.LogoImage, title: hub.title, symbol: "square.stack.fill")
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            Text(hub.title).font(.body.weight(.medium)).lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Theme.corner))
        .overlay(RoundedRectangle(cornerRadius: Theme.corner).strokeBorder(.quaternary))
        .contentShape(RoundedRectangle(cornerRadius: Theme.corner))
    }
}

/// Opens the first hub; only used for screenshots.
struct HubLoader: View {
    var body: some View {
        Loader(load: { try await API.get(InitConfig.self, API.initPath) }) { config in
            if let hub = config.Base.first(where: { $0.UrlType == "base" }) {
                HubView(hub: hub)
            }
        }
    }
}

/// One hub (audiobooks, podcasts, ...): a row of tabs, each a feed.
struct HubView: View {
    let hub: Hub
    @State private var selected: String?

    private var tabs: [HubTab] {
        let usable = hub.tabs.filter { !$0.FeedAddress.isEmpty }
        let enabled = usable.filter { $0.TabEnabled == "1" }
        return enabled.isEmpty ? usable : enabled
    }

    var body: some View {
        let current = tabs.first { $0.id == selected } ?? tabs.first
        Group {
            if let current {
                FeedView(url: current.FeedAddress).id(current.id)
            } else {
                ContentUnavailableView("چیزی برای نمایش نیست", systemImage: "tray")
            }
        }
        // The tab row is pinned as a top inset, so the list below stays the screen's main scroll view.
        .safeAreaInset(edge: .top, spacing: 0) {
            if tabs.count > 1 { tabRow(current: current) }
        }
        .navigationTitle(hub.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Horizontally scrolling tabs. The row scrolls in a left-to-right frame with the tabs reversed
    /// and anchored at its right end: a right-to-left scroll row wider than the screen can open at
    /// the wrong end, so the first tab would be out of sight.
    private func tabRow(current: HubTab?) -> some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(tabs.reversed())) { tab in
                            let on = tab.id == current?.id
                            Button {
                                Haptics.tap()
                                selected = tab.id
                                withAnimation(.snappy) { proxy.scrollTo(tab.id, anchor: .center) }
                            } label: {
                                Text(tab.Title)
                                    .font(.subheadline.weight(on ? .semibold : .regular))
                                    .padding(.horizontal, 14)
                                    .frame(minHeight: 36)
                                    .background(on ? Color.accentColor : Color(.secondarySystemFill), in: Capsule())
                                    .foregroundStyle(on ? Color.white : Color.primary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(on ? .isSelected : [])
                            .id(tab.id)
                        }
                    }
                    .padding(.horizontal, Theme.gutter)
                    .padding(.vertical, 8)
                }
                .defaultScrollAnchor(.trailing)
                // iOS 26 fades scrolling content that sits right under the navigation bar; on this
                // row that hid the tabs entirely whenever they were wide enough to scroll.
                .withoutScrollEdgeEffect()
            }
            .environment(\.layoutDirection, .leftToRight)
            Divider()
        }
        .background(.bar)
    }
}

struct FeedScreen: View {
    let url: String
    let title: String
    var asList = false
    var body: some View {
        FeedView(url: url, asList: asList)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
}

/// A server feed: titled containers, each a horizontal shelf or a vertical list of boxes.
struct FeedView: View {
    let url: String
    /// Show every container as a vertical list (search results), whatever the server says.
    var asList = false

    var body: some View {
        Loader(load: { try await API.get(FeedPage.self, url) }) { page in
            FeedContent(url: url, first: page, asList: asList).id(page.ServerTime)
        }
    }
}

/// The containers of a feed, loading further pages (`pn=2`, `pn=3`, ...) as the end comes into view.
private struct FeedContent: View {
    let url: String
    let asList: Bool
    @State private var containers: [FeedContainer]
    @State private var page = 1
    @State private var hasMore: Bool
    @State private var loadFailed = false
    @State private var seen: Set<String>

    init(url: String, first: FeedPage, asList: Bool) {
        self.url = url
        self.asList = asList
        let shown = first.Containers.filter { !$0.boxes.isEmpty }
        _containers = State(initialValue: shown)
        _hasMore = State(initialValue: first.hasMore && !shown.isEmpty)
        _seen = State(initialValue: Set(shown.flatMap { $0.boxes.map(\.URL) }))
    }

    var body: some View {
        if containers.isEmpty {
            ContentUnavailableView("چیزی برای نمایش نیست", systemImage: "tray",
                                   description: Text("این بخش هنوز در برنامه پشتیبانی نمی‌شود یا خالی است."))
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    ForEach(Array(containers.enumerated()), id: \.offset) { _, container in
                        ContainerView(container: container, asList: asList)
                    }
                    if hasMore {
                        if loadFailed {
                            Button("بارگیری بیشتر") { loadFailed = false }
                                .buttonStyle(.bordered)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        } else {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .task(id: page) { await loadMore() }
                        }
                    }
                }
                .padding(.vertical, 12)
            }
        }
    }

    private func loadMore() async {
        let next = page + 1
        let link = url + (url.contains("?") ? "&" : "?") + "pn=\(next)"
        let more: FeedPage
        do {
            more = try await API.get(FeedPage.self, link)
        } catch {
            // The spinner scrolling off screen cancels the request; that is not the end of the list.
            // It simply starts again when the spinner comes back into view.
            let cancelled = Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled
            if !cancelled { loadFailed = true }
            return
        }
        var added = false
        for var container in more.Containers {
            // A page that repeats what is already shown means the list has ended.
            container.boxes = container.boxes.filter { !$0.URL.isEmpty && !seen.contains($0.URL) }
            guard !container.boxes.isEmpty else { continue }
            added = true
            seen.formUnion(container.boxes.map(\.URL))
            if let last = containers.indices.last,
               containers[last].Title == container.Title, containers[last].isHorizontal == container.isHorizontal {
                containers[last].boxes += container.boxes
            } else {
                containers.append(container)
            }
        }
        if added { page = next } else { hasMore = false }
    }
}

private struct ContainerView: View {
    let container: FeedContainer
    var asList = false
    @State private var missing: Set<Int> = []

    var body: some View {
        // Banners carry no title, so one whose picture is broken on the server has nothing to show.
        if container.isBanner && missing.count >= container.boxes.count {
            EmptyView()
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !container.Title.isEmpty {
                SectionHeader(title: container.Title,
                              more: container.MoreLink.isEmpty ? "" : (container.MoreTitle.isEmpty ? "بیشتر" : container.MoreTitle)) {
                    FeedScreen(url: container.MoreLink, title: container.Title)
                }
            }
            if container.isHorizontal == "1" && !asList {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(Array(container.boxes.enumerated()), id: \.offset) { index, box in
                            if !(container.isBanner && missing.contains(index)) {
                                BoxLink(box: box) {
                                    BoxCard(box: box, circle: container.isCircle == "1", banner: container.isBanner) {
                                        if container.isBanner { missing.insert(index) }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Theme.gutter)
                }
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(container.boxes.enumerated()), id: \.offset) { index, box in
                        BoxLink(box: box) { BoxRow(box: box) }
                        if index < container.boxes.count - 1 { Divider().padding(.leading, 76) }
                    }
                }
                .padding(.horizontal, Theme.gutter)
            }
        }
    }
}

private struct BoxLink<Label: View>: View {
    let box: FeedBox
    @ViewBuilder let label: () -> Label

    var body: some View {
        NavigationLink {
            LinkDestination(urlType: box.URLType, url: box.URL, title: box.title)
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .disabled(box.URL.isEmpty)
    }
}

private struct BoxCard: View {
    let box: FeedBox
    let circle: Bool
    var banner = false
    var onMissingPicture: () -> Void = {}

    var body: some View {
        let size: CGFloat = banner ? 288 : (circle ? 96 : 132)
        VStack(alignment: circle ? .center : .leading, spacing: 6) {
            Artwork(link: box.image, title: box.title, symbol: circle ? "person.fill" : (box.URLType == "9" ? "headphones" : "square.stack.fill"),
                    onMissing: onMissingPicture)
                .frame(width: size, height: banner ? 150 : size)
                .clipShape(circle ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: Theme.corner)))
            if !box.title.isEmpty {
                Text(box.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(circle ? .center : .leading)
            }
            if !box.subtitle.isEmpty {
                Text(box.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(width: size, alignment: circle ? .center : .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct BoxRow: View {
    let box: FeedBox

    var body: some View {
        HStack(spacing: 12) {
            Artwork(link: box.image, title: box.title, symbol: "headphones")
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                Text(box.title).font(.body.weight(.medium)).lineLimit(2)
                let meta = [box.subtitle, Format.duration(ms: box.duration)].filter { !$0.isEmpty }.joined(separator: " · ")
                if !meta.isEmpty {
                    Text(meta).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.forward").font(.caption.bold()).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
