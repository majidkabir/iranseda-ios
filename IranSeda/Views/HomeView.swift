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
                // The tab row travels inside the feed's own scroll view, as its first row. A separate
                // horizontal scroll view directly under the navigation bar came out blank on iOS 26
                // whenever the tabs were wide enough to scroll.
                FeedView(url: current.FeedAddress, header: tabs.count > 1 ? AnyView(tabRow(current: current)) : nil)
                    .id(current.id)
            } else {
                ContentUnavailableView("چیزی برای نمایش نیست", systemImage: "tray")
            }
        }
        .navigationTitle(hub.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Always reachable, also while a tab is loading or failed to load.
            if tabs.count > 1 {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("بخش", selection: Binding(get: { current?.id ?? "" }, set: { selected = $0 })) {
                            ForEach(tabs) { tab in Text(tab.Title).tag(tab.id) }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease")
                    }
                    .accessibilityLabel("انتخاب بخش")
                }
            }
        }
    }

    private func tabRow(current: HubTab) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 8) {
                ForEach(tabs) { tab in
                    let on = tab.id == current.id
                    Button {
                        Haptics.tap()
                        selected = tab.id
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
                }
            }
            .padding(.horizontal, Theme.gutter)
        }
        .frame(height: 40)
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
    /// Shown as the first row of the scrolling content (a hub's tab row).
    var header: AnyView?

    var body: some View {
        Loader(load: { try await API.get(FeedPage.self, url) }) { page in
            FeedContent(url: url, first: page, asList: asList, header: header).id(page.ServerTime)
        }
    }
}

/// The containers of a feed, loading further pages (`pn=2`, `pn=3`, ...) as the end comes into view.
private struct FeedContent: View {
    let url: String
    let asList: Bool
    let header: AnyView?
    @State private var containers: [FeedContainer]
    @State private var page = 1
    @State private var hasMore: Bool
    @State private var loadFailed = false
    @State private var isLoading = false
    @State private var spinnerVisible = false
    @State private var bannerReady: [Int: Set<Int>] = [:]
    @State private var seen: Set<String>

    init(url: String, first: FeedPage, asList: Bool, header: AnyView?) {
        self.url = url
        self.asList = asList
        self.header = header
        let shown = first.Containers.filter { !$0.boxes.isEmpty }
        _containers = State(initialValue: shown)
        _hasMore = State(initialValue: first.hasMore && !shown.isEmpty)
        _seen = State(initialValue: Set(shown.flatMap { $0.boxes.map(\.URL) }))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                if let header { header }
                if containers.isEmpty {
                    ContentUnavailableView("چیزی برای نمایش نیست", systemImage: "tray",
                                           description: Text("این بخش هنوز در برنامه پشتیبانی نمی‌شود یا خالی است."))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                }
                ForEach(Array(containers.enumerated()), id: \.offset) { index, container in
                    if !container.isBanner {
                        ContainerView(container: container, asList: asList)
                    } else if let ready = bannerReady[index], !ready.isEmpty {
                        // A banner is only a picture. It joins the page once that picture has loaded,
                        // so a broken one never flashes an empty tile first.
                        ContainerView(container: container, asList: asList, only: ready)
                            .transition(.opacity)
                    }
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
                            .onAppear { spinnerVisible = true; loadWhileVisible() }
                            .onDisappear { spinnerVisible = false }
                    }
                } else if containers.count == 1, let only = containers.first, only.boxes.count > 5 {
                    // The end of a plain list: say so, with the count, so it is clear nothing is missing.
                    Text("پایان فهرست · " + Format.fa(only.boxes.count) + " مورد")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
            }
            .padding(.vertical, 12)
        }
        .task(id: containers.count) { await preloadBanners() }
    }

    /// Fetches banner pictures before their shelves are shown.
    private func preloadBanners() async {
        guard !Demo.isOn else { return }
        for (index, container) in containers.enumerated() where container.isBanner && bannerReady[index] == nil {
            var ready = Set<Int>()
            for (position, box) in container.boxes.enumerated() {
                guard let url = API.resolve(box.image) else { continue }
                if await ImageStore.shared.image(for: url) != nil { ready.insert(position) }
                if Task.isCancelled { return }
            }
            withAnimation(.easeOut(duration: 0.25)) { bannerReady[index] = ready }
        }
    }

    /// Loads page after page for as long as the spinner at the end of the list is on screen.
    /// The work runs in its own task, so the spinner scrolling away never cancels a request.
    private func loadWhileVisible() {
        guard !isLoading else { return }
        isLoading = true
        Task { @MainActor in
            defer { isLoading = false }
            var pages = 0
            repeat {
                await loadMore()
                pages += 1
            } while hasMore && !loadFailed && spinnerVisible && pages < 50
        }
    }

    private func loadMore() async {
        let next = page + 1
        let link = url + (url.contains("?") ? "&" : "?") + "pn=\(next)"
        let more: FeedPage
        do {
            more = try await API.get(FeedPage.self, link)
        } catch {
            loadFailed = true
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
    /// For banner shelves: the boxes whose picture is known to load. Nil shows every box.
    var only: Set<Int>?

    var body: some View {
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
                            if only?.contains(index) ?? true {
                                BoxLink(box: box) {
                                    BoxCard(box: box, circle: container.isCircle == "1", banner: container.isBanner)
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

    var body: some View {
        let size: CGFloat = banner ? 288 : (circle ? 96 : 132)
        VStack(alignment: circle ? .center : .leading, spacing: 6) {
            Artwork(link: box.image, title: box.title, symbol: circle ? "person.fill" : (box.URLType == "9" ? "headphones" : "square.stack.fill"))
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
            if !circle && !banner {
                VoiceLine(urlType: box.URLType, link: box.URL, reserveSpace: true)
                    .padding(.top, -3)
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
                VoiceLine(urlType: box.URLType, link: box.URL)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.forward").font(.caption.bold()).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
