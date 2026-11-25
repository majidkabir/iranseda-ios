import SwiftUI

// MARK: - Shared rows

/// Picture, title and a small second line: the row used in every list on the watch.
struct ItemRow: View {
    let image: String
    let title: String
    var subtitle: String = ""
    var symbol: String = "headphones"
    var round = false

    var body: some View {
        HStack(spacing: 10) {
            Artwork(link: image, title: title, symbol: symbol)
                .frame(width: 40, height: 40)
                .clipShape(round ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 8)))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.footnote.weight(.medium)).lineLimit(2)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}

/// Opens whatever a server link points at.
struct WatchLink: View {
    let urlType: String
    let url: String
    let title: String

    var body: some View {
        switch urlType {
        case "9": DetailScreen(url: url)
        case "7": SeriesScreen(url: url, title: title)
        default: FeedScreen(url: url, title: title)
        }
    }
}

/// Opens a favourite or recent item's own page.
struct SavedDestination: View {
    let item: SavedItem

    var body: some View {
        switch item.kind {
        case .channel: ChannelLoader(id: item.ref)
        case .home: SeriesScreen(url: item.url, title: item.title)
        case .detail, .play: DetailScreen(url: item.url)
        }
    }
}

/// Plays a recent item right away, with how far you got.
struct PlaySavedButton: View {
    let item: SavedItem
    @EnvironmentObject private var nav: WatchNav

    var body: some View {
        AsyncButton {
            try await nav.play { try await Playback.play(saved: item) }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                ItemRow(image: item.image, title: item.title, subtitle: item.subtitle,
                        symbol: item.kind == .channel ? "dot.radiowaves.left.and.right" : "headphones")
                if let done = Player.progress(for: item), done < 0.99 {
                    ProgressView(value: done)
                        .tint(.accentColor)
                        .environment(\.layoutDirection, .leftToRight)
                }
            }
        }
    }
}

/// A heart button row for the end of a page.
struct FavoriteRow: View {
    let item: SavedItem
    @EnvironmentObject private var library: Library

    var body: some View {
        let on = library.isFavorite(item)
        Button {
            Haptics.tap()
            library.toggleFavorite(item)
        } label: {
            Label(on ? "حذف از علاقه‌مندی‌ها" : "افزودن به علاقه‌مندی‌ها", systemImage: on ? "heart.fill" : "heart")
                .foregroundStyle(on ? Color.pink : Color.primary)
        }
    }
}

// MARK: - Radio

struct StationsScreen: View {
    @EnvironmentObject private var library: Library
    @State private var pageFor: String?

    var body: some View {
        Loader(load: { try await API.get(RadioList.self, API.radioPath) }) { list in
            let favorites = list.channels.filter { library.isFavorite(Self.saved($0)) }
            List {
                if !favorites.isEmpty {
                    Section("شبکه‌های من") {
                        ForEach(favorites) { channel in StationRow(channel: channel) { pageFor = channel.id } }
                    }
                }
                ForEach(grouped(list.channels), id: \.name) { group in
                    Section(group.name) {
                        ForEach(group.channels) { channel in StationRow(channel: channel) { pageFor = channel.id } }
                    }
                }
            }
            .navigationDestination(item: $pageFor) { id in
                if let channel = list.channels.first(where: { $0.id == id }) { ChannelScreen(channel: channel) }
            }
        }
        .navigationTitle("رادیو")
    }

    static func saved(_ channel: Channel) -> SavedItem {
        SavedItem(kind: .channel, url: API.radioPath, ref: channel.id, title: channel.title, subtitle: channel.typeTitle, image: channel.logo)
    }

    private func grouped(_ channels: [Channel]) -> [(name: String, channels: [Channel])] {
        var order: [String] = []
        var map: [String: [Channel]] = [:]
        for channel in channels {
            if map[channel.typeTitle] == nil { order.append(channel.typeTitle) }
            map[channel.typeTitle, default: []].append(channel)
        }
        return order.map { (name: $0, channels: map[$0] ?? []) }
    }
}

/// Tap plays the station live; swipe for its page or to keep it as a favourite.
private struct StationRow: View {
    let channel: Channel
    let openPage: () -> Void
    @EnvironmentObject private var player: Player
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var nav: WatchNav

    var body: some View {
        let on = player.isOn(channel: channel.id)
        let saved = StationsScreen.saved(channel)
        AsyncButton {
            if on { nav.showPlayer = true } else { try await nav.play { try await Playback.playLive(channel) } }
        } label: {
            HStack(spacing: 6) {
                ItemRow(image: channel.logo, title: channel.title, subtitle: channel.name,
                        symbol: "dot.radiowaves.left.and.right", round: true)
                if on {
                    Image(systemName: "waveform")
                        .symbolEffect(.variableColor.iterative, isActive: player.isPlaying)
                        .foregroundStyle(Color.accentColor)
                        .accessibilityLabel("در حال پخش")
                }
            }
        }
        .swipeActions(edge: .trailing) {
            Button { openPage() } label: { Label("برنامه‌ها", systemImage: "list.bullet") }
                .tint(.blue)
            Button {
                Haptics.tap()
                library.toggleFavorite(saved)
            } label: {
                Label("علاقه‌مندی", systemImage: library.isFavorite(saved) ? "heart.slash" : "heart")
            }
            .tint(.pink)
        }
        .accessibilityHint("برای پخش زنده بزنید")
    }
}

/// Finds a station by id (favourites, history).
struct ChannelLoader: View {
    let id: String

    var body: some View {
        Loader(load: { try await API.get(RadioList.self, API.radioPath) }) { list in
            if let channel = list.channels.first(where: { $0.id == id }) {
                ChannelScreen(channel: channel)
            } else {
                ContentUnavailableView("این شبکه پیدا نشد", systemImage: "dot.radiowaves.left.and.right")
            }
        }
    }
}

/// One station: what is on air with a play button, then its schedule, programmes and archive.
struct ChannelScreen: View {
    let channel: Channel
    @EnvironmentObject private var nav: WatchNav

    var body: some View {
        let tabs = channel.tabs.filter { !$0.feedAddress.isEmpty }
        List {
            if let live = channel.liveTab {
                Section {
                    Loader(load: { try await API.get(LiveInfo.self, live.feedAddress) }) { info in
                        VStack(alignment: .leading, spacing: 6) {
                            Label("روی آنتن", systemImage: "circle.fill")
                                .font(.caption2.bold())
                                .foregroundStyle(.red)
                            Text(info.name).font(.headline).lineLimit(3)
                            if !info.desc2.isEmpty {
                                Text(info.desc2).font(.caption2).foregroundStyle(.secondary).lineLimit(3)
                            }
                        }
                    }
                    .frame(minHeight: 44)
                    AsyncButton {
                        try await nav.play { try await Playback.playLive(channel) }
                    } label: {
                        Label("پخش زنده", systemImage: "play.fill").font(.headline)
                    }
                    .listItemTint(Color.accentColor)
                }
            }
            Section {
                ForEach(tabs.filter { $0.type != "1" }) { tab in
                    NavigationLink {
                        switch tab.type {
                        case "2": ScheduleScreen(url: tab.feedAddress, title: tab.title)
                        case "3": ProgramsScreen(url: tab.feedAddress, title: tab.title)
                        case "4": ArchiveScreen(url: tab.feedAddress, title: tab.title)
                        default: FeedScreen(url: tab.feedAddress, title: tab.title)
                        }
                    } label: {
                        Label(tab.title, systemImage: symbol(for: tab.type))
                    }
                }
                FavoriteRow(item: StationsScreen.saved(channel))
            }
        }
        .navigationTitle(channel.title)
    }

    private func symbol(for type: String) -> String {
        switch type {
        case "2": return "calendar"
        case "3": return "mic.fill"
        case "4": return "clock.arrow.circlepath"
        default: return "list.bullet"
        }
    }
}

struct ScheduleScreen: View {
    let url: String
    let title: String
    @EnvironmentObject private var nav: WatchNav

    var body: some View {
        Loader(load: { try await API.get(Schedule.self, url) }) { schedule in
            if schedule.EPGRecords.isEmpty {
                ContentUnavailableView("جدول پخش خالی است", systemImage: "calendar")
            } else {
                List {
                    ForEach(Array(schedule.EPGRecords.enumerated()), id: \.offset) { _, record in
                        let live = record.status == "live"
                        AsyncButton {
                            try await nav.play { try await Playback.play(link: record.epgDesc) }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(live ? "اکنون" : Format.time(epochMs: record.start))
                                    .font(.caption2.monospacedDigit().weight(.semibold))
                                    .foregroundStyle(live ? Color.red : Color.secondary)
                                Text(record.programname).font(.footnote.weight(live ? .semibold : .regular)).lineLimit(2)
                            }
                        }
                        .disabled(record.epgDesc.isEmpty)
                    }
                }
            }
        }
        .navigationTitle(title)
    }
}

struct ProgramsScreen: View {
    let url: String
    let title: String

    var body: some View {
        Loader(load: { try await API.get(LossyList<ProgramItem>.self, url).wrappedValue }) { programs in
            if programs.isEmpty {
                ContentUnavailableView("برنامه‌ای پیدا نشد", systemImage: "mic")
            } else {
                List {
                    ForEach(Array(programs.enumerated()), id: \.offset) { _, program in
                        NavigationLink {
                            SeriesScreen(url: program.programHome, title: program.title)
                        } label: {
                            ItemRow(image: program.imageUrl, title: program.title, symbol: "mic.fill")
                        }
                        .disabled(program.programHome.isEmpty)
                    }
                }
            }
        }
        .navigationTitle(title)
    }
}

struct ArchiveScreen: View {
    let url: String
    let title: String

    var body: some View {
        Loader(load: { try await API.get(TimeArchive.self, url) }) { archive in
            if archive.items.isEmpty {
                ContentUnavailableView("آرشیوی موجود نیست", systemImage: "clock")
            } else {
                List {
                    Section(archive.dateStr) {
                        ForEach(Array(archive.items.enumerated()), id: \.offset) { _, slot in
                            NavigationLink {
                                ArchivePartScreen(url: slot.TimeArchivePart, title: slot.timeStr)
                            } label: {
                                Text(slot.timeStr).font(.body.monospacedDigit())
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
    }
}

private struct ArchivePartScreen: View {
    let url: String
    let title: String
    @EnvironmentObject private var nav: WatchNav

    var body: some View {
        Loader(load: { try await API.get(TimeArchivePart.self, url) }) { part in
            List {
                if !part.PlayUrlByTime.isEmpty {
                    AsyncButton {
                        try await nav.play { try await Playback.play(link: part.PlayUrlByTime) }
                    } label: {
                        Label("پخش از ساعت \(part.timeStr)", systemImage: "play.fill")
                    }
                    .listItemTint(Color.accentColor)
                }
                ForEach(Array(part.programs.enumerated()), id: \.offset) { _, program in
                    AsyncButton {
                        try await nav.play { try await Playback.play(link: program.PlayUrl) }
                    } label: {
                        ItemRow(image: program.progCoverUrl, title: program.progName,
                                subtitle: program.progStart, symbol: "mic.fill")
                    }
                    .disabled(program.PlayUrl.isEmpty)
                }
            }
        }
        .navigationTitle(title)
    }
}

// MARK: - Hubs and feeds

struct HubsScreen: View {
    var body: some View {
        Loader(load: { try await API.get(InitConfig.self, API.initPath) }) { config in
            List {
                ForEach(config.Base.filter { $0.UrlType == "base" && !$0.tabs.isEmpty }) { hub in
                    NavigationLink { HubScreen(hub: hub) } label: {
                        ItemRow(image: hub.LogoImage, title: hub.title, symbol: "square.stack.fill")
                    }
                }
            }
        }
        .navigationTitle("پایگاه‌ها")
    }
}

/// Opens the first hub; only used for screenshots.
struct HubLoader: View {
    var body: some View {
        Loader(load: { try await API.get(InitConfig.self, API.initPath) }) { config in
            if let hub = config.Base.first(where: { $0.UrlType == "base" }) {
                HubScreen(hub: hub)
            }
        }
    }
}

/// A hub's tabs (home, new, categories…). With one tab, its feed opens directly.
struct HubScreen: View {
    let hub: Hub

    private var tabs: [HubTab] {
        let usable = hub.tabs.filter { !$0.FeedAddress.isEmpty }
        let enabled = usable.filter { $0.TabEnabled == "1" }
        return enabled.isEmpty ? usable : enabled
    }

    var body: some View {
        if tabs.count == 1, let only = tabs.first {
            FeedScreen(url: only.FeedAddress, title: hub.title)
        } else {
            List {
                ForEach(tabs) { tab in
                    NavigationLink { FeedScreen(url: tab.FeedAddress, title: tab.Title) } label: {
                        Text(tab.Title)
                    }
                }
            }
            .navigationTitle(hub.title)
        }
    }
}

/// A server feed as a list: one section per shelf, with further pages on request.
struct FeedScreen: View {
    let url: String
    let title: String

    var body: some View {
        Loader(load: { try await API.get(FeedPage.self, url) }) { page in
            FeedList(url: url, first: page)
        }
        .navigationTitle(title)
    }
}

private struct FeedList: View {
    let url: String
    @State private var containers: [FeedContainer]
    @State private var page = 1
    @State private var hasMore: Bool
    @State private var loading = false
    @State private var failed = false
    @State private var seen: Set<String>

    init(url: String, first: FeedPage) {
        self.url = url
        // Banners are pictures only; on a watch they are just noise.
        let shown = first.Containers.filter { !$0.boxes.isEmpty && !$0.isBanner }
        _containers = State(initialValue: shown)
        _hasMore = State(initialValue: first.hasMore && !shown.isEmpty)
        _seen = State(initialValue: Set(shown.flatMap { $0.boxes.map(\.URL) }))
    }

    var body: some View {
        if containers.isEmpty {
            ContentUnavailableView("چیزی برای نمایش نیست", systemImage: "tray")
        } else {
            List {
                ForEach(Array(containers.enumerated()), id: \.offset) { _, container in
                    Section {
                        ForEach(Array(container.boxes.enumerated()), id: \.offset) { _, box in
                            NavigationLink {
                                WatchLink(urlType: box.URLType, url: box.URL, title: box.title)
                            } label: {
                                ItemRow(image: box.image, title: box.title, subtitle: box.subtitle,
                                        round: container.isCircle == "1")
                            }
                            .disabled(box.URL.isEmpty)
                        }
                        if !container.MoreLink.isEmpty {
                            NavigationLink {
                                FeedScreen(url: container.MoreLink, title: container.Title)
                            } label: {
                                Text(container.MoreTitle.isEmpty ? "همه" : container.MoreTitle)
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    } header: {
                        if !container.Title.isEmpty { Text(container.Title) }
                    }
                }
                if hasMore {
                    Button {
                        Task { await loadMore() }
                    } label: {
                        HStack {
                            Spacer()
                            if loading { ProgressView() } else { Text(failed ? "تلاش دوباره" : "بیشتر") }
                            Spacer()
                        }
                    }
                    .disabled(loading)
                }
            }
        }
    }

    private func loadMore() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        let next = page + 1
        let link = url + (url.contains("?") ? "&" : "?") + "pn=\(next)"
        guard let more = try? await API.get(FeedPage.self, link) else { failed = true; return }
        failed = false
        var added = false
        for var container in more.Containers where !container.isBanner {
            container.boxes = container.boxes.filter { !$0.URL.isEmpty && !seen.contains($0.URL) }
            guard !container.boxes.isEmpty else { continue }
            added = true
            seen.formUnion(container.boxes.map(\.URL))
            if let last = containers.indices.last, containers[last].Title == container.Title {
                containers[last].boxes += container.boxes
            } else {
                containers.append(container)
            }
        }
        if added { page = next } else { hasMore = false }
    }
}

// MARK: - Items

/// A book, episode or album: credits, play, the files (each can be downloaded for offline).
struct DetailScreen: View {
    let url: String
    @EnvironmentObject private var player: Player
    @EnvironmentObject private var downloads: DownloadStore
    @EnvironmentObject private var nav: WatchNav

    var body: some View {
        Loader(load: { try await API.get(PlayerDetail.self, url) }) { detail in
            let saved = SavedItem(kind: .detail, url: url, title: detail.displayTitle, subtitle: detail.chTitle, image: detail.cover)
            List {
                Section {
                    VStack(spacing: 6) {
                        Artwork(link: detail.cover, title: detail.displayTitle, symbol: "headphones")
                            .frame(width: 84, height: 84)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        Text(detail.displayTitle).font(.headline).multilineTextAlignment(.center)
                        ForEach(detail.creditLines, id: \.self) { line in
                            Text(line).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)

                    Button {
                        Haptics.tap()
                        player.play(detail, source: saved)
                        nav.showPlayer = true
                    } label: {
                        Label(Player.progress(for: saved) == nil ? "پخش" : "ادامه", systemImage: "play.fill")
                            .font(.headline)
                    }
                    .listItemTint(Color.accentColor)
                    .disabled(detail.items.isEmpty)
                }

                Section(Format.fa(detail.items.count) + " فایل") {
                    ForEach(Array(detail.items.enumerated()), id: \.offset) { index, track in
                        WatchTrackRow(detail: detail, index: index, track: track, source: saved)
                    }
                }

                Section {
                    FavoriteRow(item: saved)
                    let left = detail.items.filter { downloads.canDownload($0) && !downloads.isDownloaded($0) }
                    if !left.isEmpty {
                        Button {
                            Haptics.tap()
                            downloads.downloadAll(of: detail)
                        } label: {
                            Label("دانلود همه", systemImage: "arrow.down.circle")
                        }
                    }
                }

                if !detail.related.isEmpty {
                    Section("مرتبط") {
                        ForEach(Array(detail.related.enumerated()), id: \.offset) { _, item in
                            NavigationLink {
                                WatchLink(urlType: item.urlType.isEmpty ? "9" : item.urlType, url: item.URL, title: item.title)
                            } label: {
                                ItemRow(image: item.image, title: item.title)
                            }
                        }
                    }
                }
            }
            .navigationTitle(detail.displayTitle)
        }
    }
}

/// One file: tap plays; swipe to download. Shows what is left of a started file.
private struct WatchTrackRow: View {
    let detail: PlayerDetail
    let index: Int
    let track: Track
    let source: SavedItem
    @EnvironmentObject private var player: Player
    @EnvironmentObject private var downloads: DownloadStore
    @EnvironmentObject private var nav: WatchNav

    private var isCurrent: Bool {
        player.album?.itemid == detail.itemid && player.index == index && !detail.itemid.isEmpty
    }

    var body: some View {
        Button {
            Haptics.tap()
            if !isCurrent { player.play(detail, at: index, source: source) }
            nav.showPlayer = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isCurrent && player.isPlaying ? "waveform" : "play.fill")
                    .font(.caption)
                    .symbolEffect(.variableColor.iterative, isActive: isCurrent && player.isPlaying)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(track.name.isEmpty ? detail.displayTitle : track.name)
                        .font(.footnote.weight(isCurrent ? .semibold : .regular))
                        .lineLimit(2)
                    Text(meta).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                status
            }
        }
        .swipeActions(edge: .trailing) {
            if downloads.canDownload(track) && !downloads.isDownloaded(track) && downloads.fraction(for: track) == nil {
                Button {
                    Haptics.tap()
                    downloads.download(track, from: detail)
                } label: {
                    Label("دانلود", systemImage: "arrow.down.circle")
                }
                .tint(.green)
            }
        }
    }

    private var meta: String {
        let total = (Double(track.duration) ?? 0) / 1000
        if !isCurrent, total > 0, let heard = player.resumePosition(for: track), heard > 5 {
            return Format.clock(max(total - heard, 0)) + " مانده"
        }
        return Format.duration(ms: track.duration)
    }

    @ViewBuilder private var status: some View {
        if downloads.isDownloaded(track) {
            Image(systemName: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
                .accessibilityLabel("دانلود شده")
        } else if let fraction = downloads.fraction(for: track) {
            ProgressView(value: fraction)
                .progressViewStyle(.circular)
                .frame(width: 18, height: 18)
        }
    }
}

/// A series or radio programme: its sections (episodes, on air, lists).
struct SeriesScreen: View {
    let url: String
    let title: String

    var body: some View {
        Loader(load: { try await API.get(HomeInfo.self, url) }) { info in
            let name = info.title.isEmpty ? title : info.title
            let tabs = info.tabs.filter { !$0.feedAddress.isEmpty && ["7", "1", "6"].contains($0.type) }
            List {
                Section {
                    VStack(spacing: 6) {
                        Artwork(link: info.imageurl, title: name, symbol: "square.stack.fill")
                            .frame(width: 84, height: 84)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        Text(name).font(.headline).multilineTextAlignment(.center)
                        if !info.radioName.isEmpty {
                            Text(info.radioName).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
                Section {
                    ForEach(tabs) { tab in
                        NavigationLink {
                            switch tab.type {
                            case "1": EpisodesScreen(url: tab.feedAddress, title: tab.title)
                            case "7": OnAirScreen(url: tab.feedAddress, title: tab.title)
                            default: FeedScreen(url: tab.feedAddress, title: tab.title)
                            }
                        } label: {
                            Label(tab.title, systemImage: tab.type == "7" ? "dot.radiowaves.left.and.right" : (tab.type == "1" ? "clock.arrow.circlepath" : "list.bullet"))
                        }
                    }
                    FavoriteRow(item: SavedItem(kind: .home, url: url, title: name, subtitle: info.radioName, image: info.imageurl))
                }
            }
            .navigationTitle(name)
        }
    }
}

/// A programme on air now (a series' "live" tab).
private struct OnAirScreen: View {
    let url: String
    let title: String
    @EnvironmentObject private var nav: WatchNav

    var body: some View {
        Loader(load: { try await API.get(LiveInfo.self, url) }) { info in
            List {
                VStack(alignment: .leading, spacing: 4) {
                    Text(info.name).font(.headline)
                    if !info.desc2.isEmpty { Text(info.desc2).font(.caption2).foregroundStyle(.secondary) }
                }
                AsyncButton {
                    try await nav.play { try await Playback.play(link: info.PlayURL) }
                } label: {
                    Label("پخش زنده", systemImage: "play.fill")
                }
                .listItemTint(Color.accentColor)
                .disabled(info.PlayURL.isEmpty)
            }
        }
        .navigationTitle(title)
    }
}

struct EpisodesScreen: View {
    let url: String
    let title: String
    @EnvironmentObject private var nav: WatchNav

    var body: some View {
        Loader(load: { try await API.get(ProgramEpisodes.self, url) }) { list in
            if list.episodes.isEmpty {
                ContentUnavailableView("قسمتی پیدا نشد", systemImage: "clock.arrow.circlepath")
            } else {
                List {
                    ForEach(Array(list.episodes.enumerated()), id: \.offset) { _, episode in
                        AsyncButton {
                            try await nav.play { try await Playback.play(link: episode.PlayURL) }
                        } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(episode.title).font(.footnote.weight(.medium))
                                let seconds = Double(episode.duration) ?? 0
                                if seconds > 0 {
                                    Text(Format.clock(seconds)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
    }
}

// MARK: - Search

struct SearchScreen: View {
    @StateObject private var model = SearchModel()
    @State private var query: String

    init(initialQuery: String = "") {
        _query = State(initialValue: initialQuery)
    }

    var body: some View {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let stations = model.matchingChannels(trimmed)
        let found = model.hubs.filter { !$0.boxes.isEmpty }
        List {
            if trimmed.count < 2 {
                Text("نام کتاب، راوی، برنامه یا شبکه را بگویید یا بنویسید.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
            if !stations.isEmpty {
                Section("شبکه‌ها") {
                    ForEach(stations) { channel in
                        NavigationLink { ChannelScreen(channel: channel) } label: {
                            ItemRow(image: channel.logo, title: channel.title, subtitle: channel.name,
                                    symbol: "dot.radiowaves.left.and.right", round: true)
                        }
                    }
                }
            }
            ForEach(found) { hub in
                Section(hub.title) {
                    ForEach(Array(hub.boxes.prefix(8).enumerated()), id: \.offset) { _, box in
                        NavigationLink {
                            WatchLink(urlType: box.URLType, url: box.URL, title: box.title)
                        } label: {
                            ItemRow(image: box.image, title: box.title, subtitle: box.subtitle)
                        }
                    }
                    if hub.boxes.count > 8 || hub.hasMore {
                        NavigationLink {
                            FeedScreen(url: hub.link, title: hub.title)
                        } label: {
                            Text("همه نتایج").foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
            if model.isSearching {
                HStack(spacing: 6) {
                    ProgressView().frame(width: 20, height: 20)
                    Text(model.hubs.first(where: \.isLoading).map { "در \($0.title)…" } ?? "در حال جست‌وجو…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(Color.clear)
            } else if trimmed.count >= 2, model.searched == trimmed, found.isEmpty, stations.isEmpty {
                ContentUnavailableView.search(text: trimmed)
            }
        }
        .searchable(text: $query, prompt: "جست‌وجو")
        .navigationTitle("جست‌وجو")
        .task { await model.prepare() }
        .task(id: query) {
            try? await Task.sleep(nanoseconds: 600_000_000)
            if !Task.isCancelled { model.search(query) }
        }
    }
}

// MARK: - Library

struct SavedScreen: View {
    enum Part { case favorites, recents }
    let part: Part
    @EnvironmentObject private var library: Library

    var body: some View {
        let items = part == .favorites ? library.favorites : library.recents
        Group {
            if items.isEmpty {
                ContentUnavailableView(part == .favorites ? "هنوز چیزی اضافه نکرده‌اید" : "هنوز چیزی گوش نکرده‌اید",
                                       systemImage: part == .favorites ? "heart" : "clock")
            } else {
                List {
                    if part == .favorites {
                        ForEach(items) { item in
                            NavigationLink { SavedDestination(item: item) } label: {
                                ItemRow(image: item.image, title: item.title, subtitle: item.subtitle,
                                        symbol: item.kind == .channel ? "dot.radiowaves.left.and.right" : "headphones",
                                        round: item.kind == .channel)
                            }
                        }
                        .onDelete { library.removeFavorites(at: $0) }
                    } else {
                        ForEach(items) { item in
                            if item.kind == .home {
                                NavigationLink { SavedDestination(item: item) } label: {
                                    ItemRow(image: item.image, title: item.title, subtitle: item.subtitle, symbol: "square.stack.fill")
                                }
                            } else {
                                PlaySavedButton(item: item)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(part == .favorites ? "علاقه‌مندی‌ها" : "اخیر")
    }
}

struct DownloadsScreen: View {
    @EnvironmentObject private var downloads: DownloadStore
    @EnvironmentObject private var player: Player
    @EnvironmentObject private var nav: WatchNav

    var body: some View {
        Group {
            if downloads.items.isEmpty {
                ContentUnavailableView("دانلودی ندارید", systemImage: "arrow.down.circle",
                                       description: Text("در صفحه هر کتاب، فایل را به چپ بکشید و «دانلود» را بزنید."))
            } else {
                List {
                    Section {
                        ForEach(downloads.items) { item in
                            Button { play(item) } label: {
                                ItemRow(image: item.image, title: item.title,
                                        subtitle: [item.album, item.bytes.map(Format.bytes) ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                            }
                        }
                        .onDelete { offsets in
                            for item in offsets.map({ downloads.items[$0] }) { downloads.delete(item) }
                        }
                    } footer: {
                        Text(Format.fa(downloads.items.count) + " فایل · " + Format.bytes(downloads.totalBytes))
                    }
                }
            }
        }
        .navigationTitle("دانلودها")
    }

    /// Plays a saved file with the other files of the same album queued around it.
    private func play(_ item: DownloadedItem) {
        Haptics.tap()
        let album = downloads.items.filter { $0.album == item.album }
        let tracks: [[String: String]] = album.map {
            ["name": $0.title, "duration": $0.durationMs, "FileID": $0.id, "playUrl": downloads.fileURL(for: $0).absoluteString]
        }
        let json: [String: Any] = ["itemid": "download-" + item.album, "title": item.album, "chTitle": "دانلودها", "items": tracks]
        guard let data = try? JSONSerialization.data(withJSONObject: json),
              let detail = try? JSONDecoder().decode(PlayerDetail.self, from: data) else { return }
        player.play(detail, at: album.firstIndex { $0.id == item.id } ?? 0)
        nav.showPlayer = true
    }
}

struct WatchSettings: View {
    @EnvironmentObject private var player: Player
    @EnvironmentObject private var downloads: DownloadStore
    @AppStorage("watch.speaker") private var speaker = false

    var body: some View {
        List {
            Section {
                Toggle("پخش از بلندگوی ساعت", isOn: $speaker)
                    .onChange(of: speaker) { _, _ in player.configureWatchSession() }
            } footer: {
                Text("خاموش: صدا به هدفون یا بلندگوی بلوتوثی می‌رود.")
            }
            Section("سرعت پخش") {
                Picker("سرعت", selection: Binding(get: { player.rate }, set: { player.setRate($0) })) {
                    ForEach(Player.speeds, id: \.self) { speed in
                        Text(Format.fa(speed == 1 ? "1" : String(format: "%g", speed)) + "×").tag(speed)
                    }
                }
            }
            Section {
                LabeledContent("فضای دانلودها", value: Format.bytes(downloads.totalBytes))
                if !downloads.items.isEmpty {
                    Button("حذف همه دانلودها", role: .destructive) { downloads.deleteAll() }
                }
            }
            Section {
                Text("برنامه‌ای غیررسمی برای شنیدن ایران‌صدا. همه چیز فقط روی همین ساعت نگه داشته می‌شود.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("تنظیمات")
    }
}
