import SwiftUI

/// All radio stations, grouped as the server groups them (national / provincial).
struct RadioView: View {
    let url: String

    var body: some View {
        Loader(load: { try await API.get(RadioList.self, url) }) { list in
            let groups = grouped(list.channels)
            List {
                ForEach(groups, id: \.name) { group in
                    Section(group.name) {
                        ForEach(group.channels) { channel in
                            NavigationLink {
                                ChannelView(channel: channel)
                            } label: {
                                HStack(spacing: 12) {
                                    RemoteImage(link: channel.logo)
                                        .frame(width: 44, height: 44)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(channel.title)
                                        if !channel.name.isEmpty {
                                            Text(channel.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("رادیو")
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

/// One station. Tab types from the server: 1 live, 2 schedule, 3 programmes, 4 time archive.
struct ChannelView: View {
    let channel: Channel
    @State private var selected: String?

    var body: some View {
        let tabs = channel.tabs.filter { !$0.feedAddress.isEmpty }
        let current = tabs.first { $0.id == selected } ?? tabs.first
        VStack(spacing: 0) {
            if tabs.count > 1 {
                Picker("", selection: Binding(get: { current?.id ?? "" }, set: { selected = $0 })) {
                    ForEach(tabs) { tab in Text(tab.title).tag(tab.id) }
                }
                .pickerStyle(.segmented)
                .padding()
            }
            if let current {
                Group {
                    switch current.type {
                    case "1": LiveTab(url: current.feedAddress)
                    case "2": ScheduleTab(url: current.feedAddress)
                    case "3": ProgramsTab(url: current.feedAddress)
                    case "4": TimeArchiveTab(url: current.feedAddress)
                    default: FeedView(url: current.feedAddress)
                    }
                }
                .id(current.id)
            } else {
                Spacer()
            }
        }
        .navigationTitle(channel.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// What is on air now, with a button that starts the live stream.
struct LiveTab: View {
    let url: String

    var body: some View {
        Loader(load: { try await API.get(LiveInfo.self, url) }) { info in
            ScrollView {
                VStack(spacing: 16) {
                    RemoteImage(link: info.image)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    Text(info.name).font(.title3).bold()
                    if !info.desc2.isEmpty { Text(info.desc2).font(.subheadline).foregroundStyle(.secondary) }
                    if !info.desc1.isEmpty { Text(info.desc1).font(.footnote).foregroundStyle(.secondary) }
                    PlayButton(link: info.PlayURL) {
                        Label("پخش زنده", systemImage: "play.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    if !info.programHome.isEmpty {
                        NavigationLink("صفحه برنامه") { HomeInfoView(url: info.programHome, title: info.name) }
                    }
                }
                .padding()
                .multilineTextAlignment(.center)
            }
        }
    }
}

private struct ScheduleTab: View {
    let url: String

    var body: some View {
        Loader(load: { try await API.get(Schedule.self, url) }) { schedule in
            List {
                ForEach(Array(schedule.EPGRecords.enumerated()), id: \.offset) { _, record in
                    PlayButton(link: record.epgDesc) {
                        HStack(spacing: 12) {
                            Text(Format.time(epochMs: record.start)).monospacedDigit().foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.programname)
                                if !record.programdesc1.isEmpty {
                                    Text(record.programdesc1).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            Spacer(minLength: 0)
                            if record.status == "live" {
                                Text("زنده").font(.caption).bold().foregroundStyle(.red)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct ProgramsTab: View {
    let url: String

    var body: some View {
        Loader(load: { try await API.get(LossyList<ProgramItem>.self, url).wrappedValue }) { programs in
            List {
                ForEach(Array(programs.enumerated()), id: \.offset) { _, program in
                    NavigationLink {
                        HomeInfoView(url: program.programHome, title: program.title)
                    } label: {
                        HStack(spacing: 12) {
                            RemoteImage(link: program.imageUrl)
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            Text(program.title)
                        }
                    }
                    .disabled(program.programHome.isEmpty)
                }
            }
        }
    }
}

private struct TimeArchiveTab: View {
    let url: String

    var body: some View {
        Loader(load: { try await API.get(TimeArchive.self, url) }) { archive in
            List {
                Section(archive.dateStr) {
                    ForEach(Array(archive.items.enumerated()), id: \.offset) { _, slot in
                        NavigationLink(slot.timeStr) {
                            ArchivePartView(url: slot.TimeArchivePart, title: slot.timeStr)
                        }
                    }
                }
            }
        }
    }
}

/// One hour of a station's archive: the programmes aired then.
private struct ArchivePartView: View {
    let url: String
    let title: String

    var body: some View {
        Loader(load: { try await API.get(TimeArchivePart.self, url) }) { part in
            List {
                if !part.PlayUrlByTime.isEmpty {
                    PlayButton(link: part.PlayUrlByTime) {
                        Label("پخش از ساعت \(part.timeStr)", systemImage: "play.circle")
                    }
                }
                ForEach(Array(part.programs.enumerated()), id: \.offset) { _, program in
                    PlayButton(link: program.PlayUrl) {
                        HStack(spacing: 12) {
                            RemoteImage(link: program.progCoverUrl)
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(program.progName)
                                Text("\(program.progStart) · \(program.progDuration)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
