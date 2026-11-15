import SwiftUI

/// Favourites, downloads and listening history.
struct LibraryView: View {
    private enum Part: String, CaseIterable {
        case favorites = "علاقه‌مندی‌ها"
        case downloads = "دانلودها"
        case recents = "اخیر"
    }

    @EnvironmentObject private var library: Library
    @EnvironmentObject private var downloads: DownloadStore
    @EnvironmentObject private var player: Player
    @State private var part: Part

    init() {
        let start: Part
        switch Demo.screen {
        case "downloads": start = .downloads
        case "recents": start = .recents
        default: start = .favorites
        }
        _part = State(initialValue: start)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("بخش", selection: $part) {
                ForEach(Part.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Theme.gutter)
            .padding(.vertical, 8)

            switch part {
            case .favorites: favorites
            case .downloads: downloadList
            case .recents: recents
            }
        }
        .navigationTitle("کتابخانه")
    }

    @ViewBuilder private var favorites: some View {
        if library.favorites.isEmpty {
            ContentUnavailableView("هنوز چیزی اضافه نکرده‌اید", systemImage: "heart",
                                   description: Text("با زدن قلب در صفحه هر شبکه یا کتاب، آن را اینجا نگه دارید."))
        } else {
            List {
                ForEach(library.favorites) { SavedRow(item: $0) }
                    .onDelete { library.removeFavorites(at: $0) }
            }
            .listStyle(.plain)
        }
    }

    @ViewBuilder private var recents: some View {
        if library.recents.isEmpty {
            ContentUnavailableView("هنوز چیزی گوش نکرده‌اید", systemImage: "clock",
                                   description: Text("هر چه پخش کنید اینجا می‌ماند تا راحت ادامه دهید."))
        } else {
            List {
                ForEach(library.recents) { SavedRow(item: $0) }
            }
            .listStyle(.plain)
        }
    }

    @ViewBuilder private var downloadList: some View {
        if downloads.items.isEmpty {
            ContentUnavailableView("دانلودی ندارید", systemImage: "arrow.down.circle",
                                   description: Text("در صفحه هر کتاب یا برنامه، فلش کنار فایل را بزنید تا بدون اینترنت گوش کنید."))
        } else {
            List {
                Section {
                    ForEach(downloads.items) { item in
                        Button { play(item) } label: {
                            HStack(spacing: 12) {
                                Artwork(link: item.image, title: item.album, symbol: "headphones")
                                    .frame(width: 48, height: 48)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title).font(.body.weight(.medium)).lineLimit(1)
                                    Text([item.album, Format.duration(ms: item.durationMs), item.bytes.map(Format.bytes) ?? ""]
                                        .filter { !$0.isEmpty }.joined(separator: " · "))
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "play.circle").font(.title3).foregroundStyle(.tint)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        for item in offsets.map({ downloads.items[$0] }) { downloads.delete(item) }
                    }
                } footer: {
                    Text(Format.fa(downloads.items.count) + " فایل · " + Format.bytes(downloads.totalBytes))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)
                }
            }
            .listStyle(.plain)
        }
    }

    /// Plays a saved file, with the other downloaded files of the same album queued around it.
    @MainActor private func play(_ item: DownloadedItem) {
        Haptics.tap()
        let album = downloads.items.filter { $0.album == item.album }
        let tracks: [[String: String]] = album.map {
            ["name": $0.title, "duration": $0.durationMs, "FileID": $0.id, "playUrl": downloads.fileURL(for: $0).absoluteString]
        }
        let json: [String: Any] = [
            "itemid": "download-" + item.album,
            "title": item.album,
            "chTitle": "دانلودها",
            "type": "aod",
            "image": item.image,
            "items": tracks,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: json),
              let detail = try? JSONDecoder().decode(PlayerDetail.self, from: data) else { return }
        player.play(detail, at: album.firstIndex { $0.id == item.id } ?? 0)
    }
}

private struct SavedRow: View {
    let item: SavedItem

    private var kindLabel: String {
        switch item.kind {
        case .channel: return "شبکه رادیویی"
        case .home: return "مجموعه"
        case .detail, .play: return item.subtitle
        }
    }

    var body: some View {
        NavigationLink { SavedItemDestination(item: item) } label: {
            HStack(spacing: 12) {
                Artwork(link: item.image, title: item.title, symbol: item.kind == .channel ? "dot.radiowaves.left.and.right" : "headphones")
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.body.weight(.medium)).lineLimit(1)
                    if !kindLabel.isEmpty {
                        Text(kindLabel).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var player: Player
    @EnvironmentObject private var downloads: DownloadStore
    @EnvironmentObject private var library: Library
    @State private var confirmDownloads = false
    @State private var confirmHistory = false
    @State private var imageBytes: Int64 = 0

    var body: some View {
        Form {
            Section("پخش") {
                Picker("سرعت پخش", selection: Binding(get: { player.rate }, set: { player.setRate($0) })) {
                    ForEach(Player.speeds, id: \.self) { Text(NowPlayingView.speedLabel($0)).tag($0) }
                }
                Button("فراموش کردن محل توقف فایل‌ها") {
                    Player.clearResumePositions()
                    Haptics.success()
                }
            }

            Section {
                LabeledContent("فضای دانلودها", value: Format.bytes(downloads.totalBytes))
                LabeledContent("حافظه تصاویر", value: Format.bytes(imageBytes))
                Button("پاک کردن حافظه تصاویر") {
                    Task {
                        await ImageStore.shared.clear()
                        imageBytes = await ImageStore.shared.diskBytes()
                        Haptics.success()
                    }
                }
                .disabled(imageBytes == 0)
                Button("حذف همه دانلودها", role: .destructive) { confirmDownloads = true }
                    .disabled(downloads.items.isEmpty)
                Button("پاک کردن تاریخچه شنیدن", role: .destructive) { confirmHistory = true }
                    .disabled(library.recents.isEmpty)
            } header: {
                Text("داده‌ها")
            } footer: {
                Text("همه چیز فقط روی همین دستگاه نگه داشته می‌شود.")
            }

            Section("درباره") {
                LabeledContent("نسخه", value: Format.fa(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"))
                Link(destination: URL(string: "https://github.com/majidkabir/iranseda-ios")!) {
                    Label("کد برنامه در گیت‌هاب", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Text("این برنامه غیررسمی است و برای استفاده شخصی ساخته شده. محتوا از سرویس ایران‌صدا می‌آید.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("تنظیمات")
        .task { imageBytes = await ImageStore.shared.diskBytes() }
        .confirmationDialog("همه فایل‌های دانلودشده حذف شوند؟", isPresented: $confirmDownloads, titleVisibility: .visible) {
            Button("حذف همه", role: .destructive) { downloads.deleteAll() }
            Button("انصراف", role: .cancel) {}
        }
        .confirmationDialog("تاریخچه شنیدن پاک شود؟", isPresented: $confirmHistory, titleVisibility: .visible) {
            Button("پاک کردن", role: .destructive) { library.clearRecents() }
            Button("انصراف", role: .cancel) {}
        }
    }
}
