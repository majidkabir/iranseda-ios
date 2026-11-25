import SwiftUI

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
