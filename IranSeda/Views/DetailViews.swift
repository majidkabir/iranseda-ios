import SwiftUI

/// A playable item (audiobook, podcast episode, album, ...) with its tracks.
struct DetailView: View {
    let url: String
    @EnvironmentObject private var player: Player
    @EnvironmentObject private var downloads: DownloadStore
    @State private var expanded = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Loader(load: { try await API.get(PlayerDetail.self, url) }) { detail in
            let saved = SavedItem(kind: .detail, url: url, title: detail.displayTitle, subtitle: detail.chTitle, image: detail.cover)
            let downloadable = detail.items.filter { downloads.canDownload($0) && !downloads.isDownloaded($0) }
            List {
                Section {
                    VStack(spacing: 14) {
                        Artwork(link: detail.cover, title: detail.displayTitle, symbol: "headphones")
                            .frame(width: 180, height: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                            .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
                        VStack(spacing: 4) {
                            Text(detail.displayTitle).font(.title2.bold()).multilineTextAlignment(.center)
                            let byline = detail.mainTags.prefix(2).map(\.tagvalue).filter { !$0.isEmpty }.joined(separator: " · ")
                            if !byline.isEmpty {
                                Text(byline).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        let row = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
                        row {
                            Button {
                                Haptics.tap()
                                player.play(detail, source: saved)
                            } label: {
                                Label("پخش", systemImage: "play.fill")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity, minHeight: 30)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(detail.items.isEmpty)

                            if !downloadable.isEmpty {
                                Button {
                                    Haptics.tap()
                                    downloads.downloadAll(of: detail)
                                } label: {
                                    Label("دانلود همه", systemImage: "arrow.down.circle")
                                        .frame(maxWidth: .infinity, minHeight: 30)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .controlSize(.large)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowSeparator(.hidden)

                    let about = [detail.abstract, detail.desc].filter { !$0.isEmpty }.joined(separator: "\n\n")
                    if !about.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(about)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(expanded ? nil : 3)
                            Button(expanded ? "کمتر" : "بیشتر") { withAnimation(.snappy) { expanded.toggle() } }
                                .font(.subheadline.weight(.medium))
                                .buttonStyle(.borderless)
                        }
                    }
                }

                Section(Format.fa(detail.items.count) + " فایل") {
                    ForEach(Array(detail.items.enumerated()), id: \.offset) { index, track in
                        TrackRow(detail: detail, index: index, track: track, source: saved)
                    }
                }

                if !detail.related.isEmpty {
                    Section("مرتبط") {
                        ForEach(Array(detail.related.enumerated()), id: \.offset) { _, item in
                            NavigationLink {
                                LinkDestination(urlType: item.urlType.isEmpty ? "9" : item.urlType, url: item.URL, title: item.title)
                            } label: {
                                HStack(spacing: 12) {
                                    Artwork(link: item.image, title: item.title, symbol: "headphones")
                                        .frame(width: 48, height: 48)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                    Text(item.title).lineLimit(2)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(detail.displayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { FavoriteButton(item: saved) }
            }
        }
        .alert("دانلود ناموفق بود", isPresented: Binding(get: { downloads.lastError != nil }, set: { if !$0 { downloads.lastError = nil } })) {
            Button("باشه", role: .cancel) {}
        } message: {
            Text(downloads.lastError ?? "")
        }
    }
}

private struct TrackRow: View {
    let detail: PlayerDetail
    let index: Int
    let track: Track
    let source: SavedItem
    @EnvironmentObject private var player: Player
    @EnvironmentObject private var downloads: DownloadStore

    private var isCurrent: Bool {
        player.album?.itemid == detail.itemid && player.index == index && !detail.itemid.isEmpty
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                Haptics.tap()
                if isCurrent { player.toggle() } else { player.play(detail, at: index, source: source) }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: isCurrent && player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.footnote)
                        .foregroundStyle(isCurrent ? Color.white : Color.accentColor)
                        .frame(width: 32, height: 32)
                        .background(isCurrent ? Color.accentColor : Color.accentColor.opacity(0.14), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.name.isEmpty ? detail.displayTitle : track.name)
                            .font(.body.weight(isCurrent ? .semibold : .regular))
                            .foregroundStyle(isCurrent ? Color.accentColor : Color.primary)
                            .lineLimit(2)
                        Text(Format.duration(ms: track.duration))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            downloadControl
        }
        .frame(minHeight: 44)
    }

    @MainActor @ViewBuilder private var downloadControl: some View {
        if downloads.isDownloaded(track) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .frame(width: 44, height: 44)
                .accessibilityLabel("دانلود شده")
        } else if let fraction = downloads.fraction(for: track) {
            Button { downloads.cancel(track) } label: {
                ZStack {
                    Circle().stroke(.quaternary, lineWidth: 3)
                    Circle().trim(from: 0, to: max(0.03, fraction))
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "stop.fill").font(.system(size: 9)).foregroundStyle(.tint)
                }
                .frame(width: 24, height: 24)
                .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("لغو دانلود")
            .accessibilityValue(Format.fa(Int(fraction * 100)) + " درصد")
        } else if downloads.canDownload(track) {
            Button {
                Haptics.tap()
                downloads.download(track, from: detail)
            } label: {
                Image(systemName: "arrow.down.circle").font(.title3).frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("دانلود")
        }
    }
}

/// Home of a serial (audiobook series) or a radio programme: a header plus its sections.
struct HomeInfoView: View {
    let url: String
    let title: String

    var body: some View {
        Loader(load: { try await API.get(HomeInfo.self, url) }) { info in
            let name = info.title.isEmpty ? title : info.title
            let tabs = info.tabs.filter { !$0.feedAddress.isEmpty }
            List {
                Section {
                    VStack(spacing: 12) {
                        Artwork(link: info.imageurl, title: name, symbol: "square.stack.fill")
                            .frame(width: 150, height: 150)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                            .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
                        Text(name).font(.title2.bold()).multilineTextAlignment(.center)
                        if !info.radioName.isEmpty {
                            Text(info.radioName).font(.subheadline).foregroundStyle(.secondary)
                        }
                        if !info.abstract.isEmpty {
                            Text(info.abstract).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                if !tabs.isEmpty {
                    Section {
                        ForEach(tabs) { tab in
                            NavigationLink {
                                if tab.type == "7" {
                                    LiveTab(url: tab.feedAddress).navigationTitle(tab.title)
                                } else {
                                    FeedScreen(url: tab.feedAddress, title: tab.title)
                                }
                            } label: {
                                Label(tab.title, systemImage: tab.type == "7" ? "dot.radiowaves.left.and.right" : "list.bullet")
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    FavoriteButton(item: SavedItem(kind: .home, url: url, title: name, subtitle: info.radioName, image: info.imageurl))
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
