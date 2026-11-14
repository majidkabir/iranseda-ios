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
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
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

    private var symbol: String {
        switch hub.Id {
        case "1021": return "book.fill"
        case "1027": return "mic.fill"
        case "1023": return "music.note"
        case "1026": return "teddybear.fill"
        case "1022": return "book.closed.fill"
        case "1024": return "person.wave.2.fill"
        case "1025": return "moon.stars.fill"
        case "1029": return "clock.arrow.circlepath"
        default: return "square.stack.fill"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Theme.gradient(for: hub.title), in: RoundedRectangle(cornerRadius: 12))
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
        VStack(spacing: 0) {
            if tabs.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(tabs) { tab in
                            let on = tab.id == current?.id
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
                    .padding(.vertical, 8)
                }
            }
            if let current {
                FeedView(url: current.FeedAddress).id(current.id)
            } else {
                ContentUnavailableView("چیزی برای نمایش نیست", systemImage: "tray")
            }
        }
        .navigationTitle(hub.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct FeedScreen: View {
    let url: String
    let title: String
    var body: some View {
        FeedView(url: url)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
}

/// A server feed: titled containers, each a horizontal shelf or a vertical list of boxes.
struct FeedView: View {
    let url: String

    var body: some View {
        Loader(load: { try await API.get(FeedPage.self, url) }) { page in
            let containers = page.Containers.filter { !$0.boxes.isEmpty }
            if containers.isEmpty {
                ContentUnavailableView("چیزی برای نمایش نیست", systemImage: "tray",
                                       description: Text("این بخش هنوز در برنامه پشتیبانی نمی‌شود یا خالی است."))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 28) {
                        ForEach(Array(containers.enumerated()), id: \.offset) { _, container in
                            ContainerView(container: container)
                        }
                    }
                    .padding(.vertical, 12)
                }
            }
        }
    }
}

private struct ContainerView: View {
    let container: FeedContainer

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !container.Title.isEmpty {
                SectionHeader(title: container.Title,
                              more: container.MoreLink.isEmpty ? "" : (container.MoreTitle.isEmpty ? "بیشتر" : container.MoreTitle)) {
                    FeedScreen(url: container.MoreLink, title: container.Title)
                }
            }
            if container.isHorizontal == "1" {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(Array(container.boxes.enumerated()), id: \.offset) { _, box in
                            BoxLink(box: box) { BoxCard(box: box, circle: container.isCircle == "1") }
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

    var body: some View {
        let size: CGFloat = circle ? 96 : 132
        VStack(alignment: circle ? .center : .leading, spacing: 6) {
            Artwork(link: box.image, title: box.title, symbol: circle ? "person.fill" : (box.URLType == "7" ? "square.stack.fill" : "headphones"))
                .frame(width: size, height: size)
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
