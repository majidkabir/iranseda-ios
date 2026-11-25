import SwiftUI
import WatchKit

/// The player, as pages you swipe up and down: controls, the system volume/output view,
/// and options (files, speed, sleep timer).
struct PlayerScreen: View {
    @EnvironmentObject private var player: Player

    var body: some View {
        TabView {
            PlayerControls()
            if !Demo.isOn {
                // The system's own Now Playing view: Digital Crown volume and the output picker.
                NowPlayingView()
            }
            PlayerOptions()
        }
        .tabViewStyle(.verticalPage)
    }
}

private struct PlayerControls: View {
    @EnvironmentObject private var player: Player

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Artwork(link: player.album?.cover ?? "", title: player.subtitle,
                        symbol: player.isLive ? "dot.radiowaves.left.and.right" : "headphones")
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 1) {
                    Text(player.title).font(.footnote.weight(.semibold)).lineLimit(2)
                    Text(player.subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            if player.isLive {
                Label("پخش زنده", systemImage: "circle.fill")
                    .font(.caption2.bold())
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 2) {
                    ProgressView(value: player.progress)
                        .tint(.accentColor)
                    HStack {
                        Text(Format.clock(player.position))
                        Spacer()
                        Text("-" + Format.clock(max(player.duration - player.position, 0)))
                    }
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
                }
                // Time runs left to right, as on every player.
                .environment(\.layoutDirection, .leftToRight)
            }

            Spacer(minLength: 0)

            HStack {
                if player.isLive {
                    Spacer()
                    playButton
                    Spacer()
                } else {
                    control("gobackward.15", label: "۱۵ ثانیه عقب") { player.skip(-15) }
                    Spacer(minLength: 0)
                    playButton
                    Spacer(minLength: 0)
                    control("goforward.15", label: "۱۵ ثانیه جلو") { player.skip(15) }
                }
            }
            .environment(\.layoutDirection, .leftToRight)

            if !player.isLive, (player.album?.items.count ?? 0) > 1 {
                HStack {
                    control("backward.end.fill", label: "قبلی", small: true) { player.previous() }
                        .disabled(!player.hasPrevious)
                    Spacer()
                    Text(Format.fa(player.index + 1) + " از " + Format.fa(player.album?.items.count ?? 0))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                    control("forward.end.fill", label: "بعدی", small: true) { player.next() }
                        .disabled(!player.hasNext)
                }
                .environment(\.layoutDirection, .leftToRight)
            }
        }
        .padding(.horizontal, 4)
    }

    private var playButton: some View {
        Button {
            Haptics.tap()
            player.toggle()
        } label: {
            ZStack {
                Circle().fill(Color.accentColor)
                if player.isBuffering {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 58, height: 58)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(player.isPlaying ? "توقف" : "پخش")
    }

    private func control(_ symbol: String, label: String, small: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: symbol)
                .font(small ? .footnote : .title3)
                .frame(width: small ? 32 : 44, height: small ? 28 : 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct PlayerOptions: View {
    @EnvironmentObject private var player: Player
    @EnvironmentObject private var nav: WatchNav

    var body: some View {
        List {
            if let album = player.album, album.items.count > 1 {
                Section("فایل‌ها") {
                    ForEach(Array(album.items.enumerated()), id: \.offset) { index, track in
                        Button {
                            Haptics.tap()
                            player.jump(to: index)
                        } label: {
                            HStack {
                                Text(track.name.isEmpty ? album.displayTitle : track.name)
                                    .font(.footnote.weight(index == player.index ? .semibold : .regular))
                                    .foregroundStyle(index == player.index ? Color.accentColor : Color.primary)
                                    .lineLimit(2)
                                Spacer(minLength: 0)
                                if index == player.index {
                                    Image(systemName: "speaker.wave.2.fill").font(.caption2).foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                }
            }
            if !player.isLive {
                Section("سرعت") {
                    Picker("سرعت پخش", selection: Binding(get: { player.rate }, set: { player.setRate($0) })) {
                        ForEach(Player.speeds, id: \.self) { speed in
                            Text(Format.fa(String(format: "%g", speed)) + "×").tag(speed)
                        }
                    }
                }
            }
            Section("خواب") {
                if let until = player.sleepAt {
                    Button("لغو (" + Format.fa(until.formatted(date: .omitted, time: .shortened)) + ")") { player.sleep(afterMinutes: nil) }
                } else {
                    ForEach([15, 30, 60], id: \.self) { minutes in
                        Button(Format.fa(minutes) + " دقیقه") {
                            Haptics.tap()
                            player.sleep(afterMinutes: minutes)
                        }
                    }
                }
            }
            Section {
                Button("توقف پخش", role: .destructive) {
                    player.stop()
                    nav.showPlayer = false
                }
            }
        }
    }
}
