import SwiftUI

/// All radio stations, grouped as the server groups them, with a search filter.
struct RadioView: View {
    @EnvironmentObject private var library: Library
    @State private var query = ""

    var body: some View {
        Loader(load: { try await API.get(RadioList.self, API.radioPath) }) { list in
            let needle = query.trimmingCharacters(in: .whitespaces)
            let shown = needle.isEmpty ? list.channels : list.channels.filter { $0.title.contains(needle) || $0.name.contains(needle) }
            let favorites = shown.filter { library.isFavorite(Self.saved($0)) }
            List {
                if !favorites.isEmpty {
                    Section("شبکه‌های من") {
                        ForEach(favorites) { StationRow(channel: $0) }
                    }
                }
                ForEach(grouped(shown), id: \.name) { group in
                    Section(group.name) {
                        ForEach(group.channels) { StationRow(channel: $0) }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .overlay {
                if shown.isEmpty { ContentUnavailableView.search(text: needle) }
            }
        }
        .searchable(text: $query, prompt: "جست‌وجوی شبکه")
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

private struct StationRow: View {
    let channel: Channel
    @EnvironmentObject private var player: Player

    var body: some View {
        NavigationLink { ChannelView(channel: channel) } label: {
            HStack(spacing: 12) {
                Artwork(link: channel.logo, title: channel.title, symbol: "dot.radiowaves.left.and.right")
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(channel.title).font(.body.weight(.medium))
                    if !channel.name.isEmpty {
                        Text(channel.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if player.isOn(channel: channel.id) {
                    // This station is on: show it, and let the same button pause and resume.
                    Button {
                        Haptics.tap()
                        player.toggle()
                    } label: {
                        Image(systemName: player.isPlaying ? "waveform" : "play.fill")
                            .font(.body.weight(.semibold))
                            .symbolEffect(.variableColor.iterative, isActive: player.isPlaying)
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.accentColor, in: Circle())
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(player.isPlaying ? "توقف \(channel.title)" : "ادامه \(channel.title)")
                } else {
                    AsyncButton {
                        try await Playback.playLive(channel)
                    } label: {
                        Image(systemName: "play.circle.fill")
                            .font(.title)
                            .symbolRenderingMode(.hierarchical)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("پخش زنده \(channel.title)")
                }
            }
        }
    }
}

/// Finds a station by id in the station list (for favourites and history).
struct ChannelLoader: View {
    let id: String

    var body: some View {
        Loader(load: { try await API.get(RadioList.self, API.radioPath) }) { list in
            if let channel = list.channels.first(where: { $0.id == id }) {
                ChannelView(channel: channel)
            } else {
                ContentUnavailableView("این شبکه پیدا نشد", systemImage: "dot.radiowaves.left.and.right")
            }
        }
    }
}

/// One station. Tab types from the server: 1 live, 2 schedule, 3 programmes, 4 time archive.
struct ChannelView: View {
    let channel: Channel
    @State private var selected: String?

    var body: some View {
        let tabs = channel.tabs.filter { !$0.feedAddress.isEmpty }
        let current = tabs.first { $0.id == selected } ?? tabs.first
        VStack(spacing: 0) {
            if tabs.count > 1 {
                Picker("بخش", selection: Binding(get: { current?.id ?? "" }, set: { selected = $0 })) {
                    ForEach(tabs) { tab in Text(tab.title).tag(tab.id) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Theme.gutter)
                .padding(.vertical, 8)
            }
            if let current {
                Group {
                    switch current.type {
                    case "1": LiveTab(url: current.feedAddress, channel: channel)
                    case "2": ScheduleTab(url: current.feedAddress)
                    case "3": ProgramsTab(url: current.feedAddress)
                    case "4": TimeArchiveTab(url: current.feedAddress)
                    default: FeedView(url: current.feedAddress)
                    }
                }
                .id(current.id)
            } else {
                ContentUnavailableView("چیزی برای نمایش نیست", systemImage: "tray")
            }
        }
        .navigationTitle(channel.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { FavoriteButton(item: RadioView.saved(channel)) }
        }
    }
}

/// What is on air now, with a button that starts the live stream.
struct LiveTab: View {
    let url: String
    var channel: Channel?

    var body: some View {
        Loader(load: { try await API.get(LiveInfo.self, url) }) { info in
            ScrollView {
                VStack(spacing: 16) {
                    Artwork(link: info.image, title: channel?.title ?? info.name, symbol: "dot.radiowaves.left.and.right")
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
                    VStack(spacing: 6) {
                        Label("روی آنتن", systemImage: "circle.fill")
                            .font(.caption.bold())
                            .foregroundStyle(.red)
                            .labelStyle(.titleAndIcon)
                        Text(info.name).font(.title2.bold())
                        if !info.desc2.isEmpty {
                            Text(info.desc2).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .multilineTextAlignment(.center)

                    AsyncButton {
                        let source = channel.map { SavedItem(kind: .channel, url: API.radioPath, ref: $0.id, title: $0.title, subtitle: info.name, image: $0.logo) }
                        try await Playback.play(link: info.PlayURL, source: source)
                    } label: {
                        Label("پخش زنده", systemImage: "play.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 30)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(info.PlayURL.isEmpty)

                    if !info.programHome.isEmpty {
                        NavigationLink { HomeInfoView(url: info.programHome, title: info.name) } label: {
                            Label("صفحه برنامه", systemImage: "info.circle")
                                .frame(maxWidth: .infinity, minHeight: 30)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                }
                .padding(Theme.gutter)
            }
        }
    }
}

private struct ScheduleTab: View {
    let url: String

    var body: some View {
        Loader(load: { try await API.get(Schedule.self, url) }) { schedule in
            if schedule.EPGRecords.isEmpty {
                ContentUnavailableView("جدول پخش خالی است", systemImage: "calendar")
            } else {
                List {
                    ForEach(Array(schedule.EPGRecords.enumerated()), id: \.offset) { _, record in
                        let live = record.status == "live"
                        AsyncButton {
                            try await Playback.play(link: record.epgDesc)
                        } label: {
                            HStack(spacing: 12) {
                                Text(Format.time(epochMs: record.start))
                                    .font(.callout.monospacedDigit())
                                    .foregroundStyle(live ? Color.red : Color.secondary)
                                    .frame(width: 52, alignment: .leading)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(record.programname).font(.body.weight(live ? .semibold : .regular))
                                    if !record.programdesc1.isEmpty {
                                        Text(record.programdesc1).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                                Spacer(minLength: 0)
                                if live {
                                    Text("زنده")
                                        .font(.caption.bold())
                                        .padding(.horizontal, 8).padding(.vertical, 3)
                                        .background(.red, in: Capsule())
                                        .foregroundStyle(.white)
                                } else {
                                    Image(systemName: "play.circle").foregroundStyle(.tint)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(record.epgDesc.isEmpty)
                    }
                }
                .listStyle(.plain)
            }
        }
    }
}

private struct ProgramsTab: View {
    let url: String

    var body: some View {
        Loader(load: { try await API.get(LossyList<ProgramItem>.self, url).wrappedValue }) { programs in
            if programs.isEmpty {
                ContentUnavailableView("برنامه‌ای پیدا نشد", systemImage: "list.bullet")
            } else {
                List {
                    ForEach(Array(programs.enumerated()), id: \.offset) { _, program in
                        NavigationLink {
                            HomeInfoView(url: program.programHome, title: program.title)
                        } label: {
                            HStack(spacing: 12) {
                                Artwork(link: program.imageUrl, title: program.title, symbol: "mic.fill")
                                    .frame(width: 48, height: 48)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                Text(program.title)
                            }
                        }
                        .disabled(program.programHome.isEmpty)
                    }
                }
                .listStyle(.plain)
            }
        }
    }
}

private struct TimeArchiveTab: View {
    let url: String

    var body: some View {
        Loader(load: { try await API.get(TimeArchive.self, url) }) { archive in
            if archive.items.isEmpty {
                ContentUnavailableView("آرشیوی موجود نیست", systemImage: "clock")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(archive.dateStr).font(.headline).padding(.horizontal, Theme.gutter)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 10)], spacing: 10) {
                            ForEach(Array(archive.items.enumerated()), id: \.offset) { _, slot in
                                NavigationLink {
                                    ArchivePartView(url: slot.TimeArchivePart, title: slot.timeStr)
                                } label: {
                                    Text(slot.timeStr)
                                        .font(.body.monospacedDigit().weight(.medium))
                                        .frame(maxWidth: .infinity, minHeight: 48)
                                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("ساعت \(slot.timeStr)")
                            }
                        }
                        .padding(.horizontal, Theme.gutter)
                    }
                    .padding(.vertical, 12)
                }
            }
        }
    }
}

/// One slot of a station's archive: the programmes aired then.
private struct ArchivePartView: View {
    let url: String
    let title: String

    var body: some View {
        Loader(load: { try await API.get(TimeArchivePart.self, url) }) { part in
            List {
                if !part.PlayUrlByTime.isEmpty {
                    Section {
                        AsyncButton {
                            try await Playback.play(link: part.PlayUrlByTime)
                        } label: {
                            Label("پخش از ساعت \(part.timeStr)", systemImage: "play.circle.fill")
                        }
                    }
                }
                Section("برنامه‌های این ساعت") {
                    ForEach(Array(part.programs.enumerated()), id: \.offset) { _, program in
                        AsyncButton {
                            try await Playback.play(link: program.PlayUrl)
                        } label: {
                            HStack(spacing: 12) {
                                Artwork(link: program.progCoverUrl, title: program.progName, symbol: "mic.fill")
                                    .frame(width: 48, height: 48)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(program.progName)
                                    Text("\(program.progStart) · \(program.progDuration)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "play.circle").foregroundStyle(.tint)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(program.PlayUrl.isEmpty)
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
