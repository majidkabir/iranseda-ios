import SwiftUI

/// A playable item (audiobook, podcast episode, album, ...) with its tracks.
struct DetailView: View {
    let url: String
    @EnvironmentObject private var player: Player
    @EnvironmentObject private var downloads: DownloadStore

    var body: some View {
        Loader(load: { try await API.get(PlayerDetail.self, url) }) { detail in
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 12) {
                            RemoteImage(link: detail.cover)
                                .frame(width: 110, height: 110)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            VStack(alignment: .leading, spacing: 6) {
                                Text(detail.displayTitle).font(.headline)
                                ForEach(Array(detail.mainTags.prefix(4).enumerated()), id: \.offset) { _, tag in
                                    if !tag.tagvalue.isEmpty {
                                        Text("\(tag.tagname) \(tag.tagvalue)").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        Button {
                            player.play(detail)
                        } label: {
                            Label("پخش", systemImage: "play.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(detail.items.isEmpty)
                        if !detail.abstract.isEmpty { Text(detail.abstract).font(.subheadline) }
                        if !detail.desc.isEmpty {
                            Text(detail.desc).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("فایل‌ها") {
                    ForEach(Array(detail.items.enumerated()), id: \.offset) { index, track in
                        HStack {
                            Button {
                                player.play(detail, at: index)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(track.name.isEmpty ? detail.displayTitle : track.name)
                                    Text(Format.duration(ms: track.duration)).font(.caption).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            downloadControl(track, detail)
                        }
                    }
                }

                if !detail.related.isEmpty {
                    Section("مرتبط") {
                        ForEach(Array(detail.related.enumerated()), id: \.offset) { _, item in
                            NavigationLink {
                                LinkDestination(urlType: item.urlType.isEmpty ? "9" : item.urlType, url: item.URL, title: item.title)
                            } label: {
                                HStack(spacing: 12) {
                                    RemoteImage(link: item.image)
                                        .frame(width: 44, height: 44)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                    Text(item.title).lineLimit(2)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(detail.displayTitle)
            .navigationBarTitleDisplayMode(.inline)
        }
        .alert("Download failed", isPresented: Binding(get: { downloads.lastError != nil }, set: { if !$0 { downloads.lastError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(downloads.lastError ?? "")
        }
    }

    @MainActor @ViewBuilder private func downloadControl(_ track: Track, _ detail: PlayerDetail) -> some View {
        if downloads.isDownloaded(track) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        } else if downloads.inProgress.contains(DownloadStore.key(for: track)) {
            ProgressView()
        } else if downloads.canDownload(track) {
            Button {
                downloads.download(track, from: detail)
            } label: {
                Image(systemName: "arrow.down.circle")
            }
            .buttonStyle(.borderless)
        }
    }
}

/// Home of a serial (audiobook series) or a radio programme: a header plus its sections.
struct HomeInfoView: View {
    let url: String
    let title: String

    var body: some View {
        Loader(load: { try await API.get(HomeInfo.self, url) }) { info in
            List {
                Section {
                    HStack(alignment: .top, spacing: 12) {
                        RemoteImage(link: info.imageurl)
                            .frame(width: 90, height: 90)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 6) {
                            Text(info.title.isEmpty ? title : info.title).font(.headline)
                            if !info.radioName.isEmpty {
                                Text(info.radioName).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if !info.abstract.isEmpty { Text(info.abstract).font(.footnote) }
                }
                Section {
                    ForEach(info.tabs.filter { !$0.feedAddress.isEmpty }) { tab in
                        NavigationLink(tab.title) {
                            if tab.type == "7" {
                                LiveTab(url: tab.feedAddress).navigationTitle(tab.title)
                            } else {
                                FeedScreen(url: tab.feedAddress, title: tab.title)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
