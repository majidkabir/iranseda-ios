import SwiftUI

/// First screen: live radio plus every content hub the server lists.
struct HomeView: View {
    var body: some View {
        Loader(load: { try await API.get(InitConfig.self, API.initPath) }) { config in
            let radio = config.Base.first { $0.UrlType == "radio" && !$0.UrlAddress.isEmpty }
            let hubs = config.Base.filter { $0.UrlType == "base" && !$0.tabs.isEmpty }
            List {
                if let radio {
                    NavigationLink {
                        RadioView(url: radio.UrlAddress)
                    } label: {
                        Label("رادیو (پخش زنده و آرشیو)", systemImage: "dot.radiowaves.left.and.right")
                    }
                }
                Section("پایگاه‌ها") {
                    ForEach(hubs) { hub in
                        NavigationLink {
                            HubView(hub: hub)
                        } label: {
                            HStack(spacing: 12) {
                                RemoteImage(link: hub.LogoImage)
                                    .frame(width: 36, height: 36)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                Text(hub.title)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("ایران‌صدا")
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
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tabs) { tab in
                        Button(tab.Title) { selected = tab.id }
                            .buttonStyle(.bordered)
                            .tint(tab.id == current?.id ? .accentColor : .secondary)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            if let current {
                FeedView(url: current.FeedAddress).id(current.id)
            } else {
                Text("Nothing here").foregroundStyle(.secondary).frame(maxHeight: .infinity)
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
                Text("Nothing to show here").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(Array(containers.enumerated()), id: \.offset) { _, container in
                            ContainerView(container: container)
                        }
                    }
                    .padding(.vertical)
                }
            }
        }
    }
}

private struct ContainerView: View {
    let container: FeedContainer

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !container.Title.isEmpty || !container.MoreLink.isEmpty {
                HStack {
                    Text(container.Title).font(.headline)
                    Spacer()
                    if !container.MoreLink.isEmpty {
                        NavigationLink(container.MoreTitle.isEmpty ? "بیشتر" : container.MoreTitle) {
                            FeedScreen(url: container.MoreLink, title: container.Title)
                        }
                        .font(.subheadline)
                    }
                }
                .padding(.horizontal)
            }
            if container.isHorizontal == "1" {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(Array(container.boxes.enumerated()), id: \.offset) { _, box in
                            BoxLink(box: box) { BoxCard(box: box, circle: container.isCircle == "1") }
                        }
                    }
                    .padding(.horizontal)
                }
            } else {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(container.boxes.enumerated()), id: \.offset) { _, box in
                        BoxLink(box: box) { BoxRow(box: box) }
                    }
                }
                .padding(.horizontal)
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
        VStack(alignment: .leading, spacing: 6) {
            RemoteImage(link: box.image)
                .frame(width: 130, height: 130)
                .clipShape(circle ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 10)))
            if !box.title.isEmpty {
                Text(box.title).font(.subheadline).lineLimit(2)
            }
            if !box.subtitle.isEmpty {
                Text(box.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(width: 130, alignment: .leading)
    }
}

private struct BoxRow: View {
    let box: FeedBox

    var body: some View {
        HStack(spacing: 12) {
            RemoteImage(link: box.image)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) {
                Text(box.title).lineLimit(2)
                let meta = [box.subtitle, Format.duration(ms: box.duration)].filter { !$0.isEmpty }.joined(separator: " · ")
                if !meta.isEmpty {
                    Text(meta).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}
