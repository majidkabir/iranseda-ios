import AVFoundation
import SwiftUI

struct MiniPlayer: View {
    @EnvironmentObject private var player: Player

    var body: some View {
        HStack(spacing: 12) {
            RemoteImage(link: player.album?.cover ?? "")
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(player.title).font(.subheadline).lineLimit(1)
                Text(player.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Button { player.toggle() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.title3)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
        .contentShape(Rectangle())
    }
}

struct NowPlayingView: View {
    @EnvironmentObject private var player: Player
    @Environment(\.dismiss) private var dismiss
    @State private var dragValue: Double?

    private let sleepOptions = [15, 30, 45, 60]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    RemoteImage(link: player.album?.cover ?? "")
                        .frame(width: 240, height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    VStack(spacing: 4) {
                        Text(player.title).font(.title3).bold().multilineTextAlignment(.center)
                        Text(player.subtitle).font(.subheadline).foregroundStyle(.secondary)
                    }

                    if player.isLive {
                        Text("پخش زنده").font(.caption).bold().foregroundStyle(.red)
                    } else {
                        VStack(spacing: 4) {
                            Slider(
                                value: Binding(get: { dragValue ?? player.position }, set: { dragValue = $0 }),
                                in: 0...max(player.duration, 1),
                                onEditingChanged: { editing in
                                    if !editing, let value = dragValue {
                                        player.seek(to: value)
                                        dragValue = nil
                                    }
                                }
                            )
                            HStack {
                                Text(Format.clock(dragValue ?? player.position))
                                Spacer()
                                Text(Format.clock(player.duration))
                            }
                            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        }
                        .environment(\.layoutDirection, .leftToRight)
                    }

                    HStack(spacing: 28) {
                        Button { player.previous() } label: { Image(systemName: "backward.end.fill") }
                            .disabled(!player.hasPrevious)
                        Button { player.skip(-15) } label: { Image(systemName: "gobackward.15") }
                            .disabled(player.isLive)
                        Button { player.toggle() } label: {
                            Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 64))
                        }
                        Button { player.skip(15) } label: { Image(systemName: "goforward.15") }
                            .disabled(player.isLive)
                        Button { player.next() } label: { Image(systemName: "forward.end.fill") }
                            .disabled(!player.hasNext)
                    }
                    .font(.title2)
                    .buttonStyle(.plain)
                    .environment(\.layoutDirection, .leftToRight)

                    Menu {
                        ForEach(sleepOptions, id: \.self) { minutes in
                            Button("\(minutes) min") { player.sleep(afterMinutes: minutes) }
                        }
                        if player.sleepAt != nil {
                            Button("Turn off", role: .destructive) { player.sleep(afterMinutes: nil) }
                        }
                    } label: {
                        if let sleepAt = player.sleepAt {
                            Label("Sleep at \(sleepAt.formatted(date: .omitted, time: .shortened))", systemImage: "moon.fill")
                        } else {
                            Label("Sleep timer", systemImage: "moon")
                        }
                    }

                    if let album = player.album, album.items.count > 1 {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(album.items.enumerated()), id: \.offset) { index, track in
                                Button {
                                    player.play(album, at: index)
                                } label: {
                                    HStack {
                                        Text(track.name.isEmpty ? "\(index + 1)" : track.name)
                                            .fontWeight(index == player.index ? .bold : .regular)
                                        Spacer()
                                        Text(Format.duration(ms: track.duration))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 10)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                Divider()
                            }
                        }
                    }
                }
                .padding()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button("Stop") { player.stop(); dismiss() }
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }
}

/// Files saved for offline listening.
struct DownloadsView: View {
    @EnvironmentObject private var downloads: DownloadStore
    @EnvironmentObject private var player: Player

    var body: some View {
        List {
            if downloads.items.isEmpty {
                Text("No downloads yet. Use the arrow next to a file to save it.")
                    .foregroundStyle(.secondary)
            }
            ForEach(downloads.items) { item in
                Button {
                    play(item)
                } label: {
                    HStack(spacing: 12) {
                        RemoteImage(link: item.image)
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).lineLimit(2)
                            Text(item.album).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .onDelete { offsets in
                for item in offsets.map({ downloads.items[$0] }) { downloads.delete(item) }
            }
        }
        .navigationTitle("Downloads")
    }

    /// Plays a saved file by wrapping it in a one-track player detail.
    @MainActor private func play(_ item: DownloadedItem) {
        let file = downloads.fileURL(for: item)
        let json: [String: Any] = [
            "itemid": item.id,
            "title": item.album,
            "type": "aod",
            "image": item.image,
            "items": [["name": item.title, "duration": item.durationMs, "FileID": item.id, "playUrl": file.absoluteString]],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: json),
              let detail = try? JSONDecoder().decode(PlayerDetail.self, from: data) else { return }
        player.play(detail)
    }
}
