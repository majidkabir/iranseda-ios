import SwiftUI

/// The bar above the tab bar while something is loaded in the player.
struct MiniPlayer: View {
    let open: () -> Void
    @EnvironmentObject private var player: Player

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: open) {
                    HStack(spacing: 12) {
                        Artwork(link: player.album?.cover ?? "", title: player.album?.displayTitle ?? "", symbol: player.isLive ? "dot.radiowaves.left.and.right" : "headphones")
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(player.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text(player.isLive ? "پخش زنده" : player.subtitle)
                                .font(.caption)
                                .foregroundStyle(player.isLive ? Color.red : Color.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("باز کردن پخش‌کننده، \(player.title)")

                Button {
                    Haptics.tap()
                    player.toggle()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .frame(width: 44, height: 44)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(player.isPlaying ? "توقف" : "پخش")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if !player.isLive {
                GeometryReader { geo in
                    Rectangle().fill(Color.accentColor)
                        .frame(width: geo.size.width * player.progress)
                }
                .frame(height: 3)
                .environment(\.layoutDirection, .leftToRight)
                .accessibilityHidden(true)
            }
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.quaternary))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }
}

struct NowPlayingView: View {
    @EnvironmentObject private var player: Player
    @Environment(\.dismiss) private var dismiss
    @State private var dragValue: Double?
    @State private var showQueue = false

    private let sleepOptions = [15, 30, 45, 60, 90]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer(minLength: 8)
                Artwork(link: player.album?.cover ?? "", title: player.album?.displayTitle ?? "", symbol: player.isLive ? "dot.radiowaves.left.and.right" : "headphones")
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .shadow(color: .black.opacity(0.22), radius: 22, y: 12)
                    .scaleEffect(player.isPlaying ? 1 : 0.92)
                    .animation(.spring(duration: 0.4), value: player.isPlaying)
                    .padding(.horizontal, 32)
                Spacer(minLength: 20)

                VStack(spacing: 4) {
                    Text(player.title).font(.title3.bold()).multilineTextAlignment(.center).lineLimit(2)
                    Text(player.subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                .padding(.horizontal, 24)

                scrubber.padding(.horizontal, 24).padding(.top, 18)
                transport.padding(.top, 10)
                options.padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 12)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "chevron.down") }
                        .accessibilityLabel("بستن")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            player.stop()
                            dismiss()
                        } label: {
                            Label("پایان پخش", systemImage: "stop.circle")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("گزینه‌های بیشتر")
                }
            }
            .sheet(isPresented: $showQueue) { QueueView().presentationDetents([.medium, .large]) }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    @ViewBuilder private var scrubber: some View {
        if player.isLive {
            HStack(spacing: 6) {
                Circle().fill(.red).frame(width: 8, height: 8)
                Text("پخش زنده").font(.subheadline.bold()).foregroundStyle(.red)
            }
            .frame(height: 56)
        } else {
            VStack(spacing: 2) {
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
                .accessibilityLabel("موقعیت پخش")
                .accessibilityValue(Format.clock(dragValue ?? player.position))
                HStack {
                    Text(Format.clock(dragValue ?? player.position))
                    Spacer()
                    Text("−" + Format.clock(max(player.duration - (dragValue ?? player.position), 0)))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            .environment(\.layoutDirection, .leftToRight)
            .frame(height: 56)
        }
    }

    private var transport: some View {
        HStack(spacing: 0) {
            if !player.isLive {
                control("backward.end.fill", label: "قبلی", size: .title2, enabled: player.hasPrevious) { player.previous() }
                control("gobackward.15", label: "۱۵ ثانیه عقب", size: .title, enabled: true) { player.skip(-15) }
            }
            Button {
                Haptics.tap()
                player.toggle()
            } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 72))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(maxWidth: .infinity)
            }
            .accessibilityLabel(player.isPlaying ? "توقف" : "پخش")
            if !player.isLive {
                control("goforward.15", label: "۱۵ ثانیه جلو", size: .title, enabled: true) { player.skip(15) }
                control("forward.end.fill", label: "بعدی", size: .title2, enabled: player.hasNext) { player.next() }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .environment(\.layoutDirection, .leftToRight)
    }

    private func control(_ symbol: String, label: String, size: Font, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: symbol)
                .font(size)
                .frame(maxWidth: .infinity, minHeight: 56)
                .contentShape(Rectangle())
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
        .accessibilityLabel(label)
    }

    private var options: some View {
        HStack(spacing: 0) {
            if !player.isLive {
            Menu {
                Picker("سرعت پخش", selection: Binding(get: { player.rate }, set: { player.setRate($0) })) {
                    ForEach(Player.speeds, id: \.self) { speed in
                        Text(Self.speedLabel(speed)).tag(speed)
                    }
                }
            } label: {
                option(text: Self.speedLabel(player.rate), caption: "سرعت")
            }
            }

            Menu {
                ForEach(sleepOptions, id: \.self) { minutes in
                    Button(Format.fa(minutes) + " دقیقه") { player.sleep(afterMinutes: minutes) }
                }
                if player.sleepAt != nil {
                    Button("خاموش کردن زمان‌سنج", role: .destructive) { player.sleep(afterMinutes: nil) }
                }
            } label: {
                option(symbol: player.sleepAt == nil ? "moon" : "moon.fill",
                       caption: player.sleepAt.map { $0.formatted(date: .omitted, time: .shortened) } ?? "خواب")
            }

            VStack(spacing: 4) {
                RoutePicker().frame(width: 28, height: 28)
                Text("خروجی").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .accessibilityLabel("انتخاب خروجی صدا")

            if (player.album?.items.count ?? 0) > 1 {
                Button { showQueue = true } label: {
                    option(symbol: "list.bullet", caption: "فهرست")
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func option(symbol: String? = nil, text: String? = nil, caption: String) -> some View {
        VStack(spacing: 4) {
            Group {
                if let symbol {
                    Image(systemName: symbol).font(.title3)
                } else {
                    Text(text ?? "").font(.headline.monospacedDigit())
                }
            }
            .frame(height: 28)
            Text(caption).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 52)
        .contentShape(Rectangle())
    }

    static func speedLabel(_ speed: Float) -> String {
        let text = speed == speed.rounded() ? String(format: "%.0f", speed) : String(format: "%g", speed)
        return Format.fa(text) + "×"
    }
}

/// The files of the item that is playing.
private struct QueueView: View {
    @EnvironmentObject private var player: Player
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let album = player.album {
                    ForEach(Array(album.items.enumerated()), id: \.offset) { index, track in
                        let current = index == player.index
                        Button {
                            Haptics.tap()
                            player.jump(to: index)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: current ? "speaker.wave.2.fill" : "play.fill")
                                    .font(.footnote)
                                    .foregroundStyle(current ? Color.accentColor : Color.secondary)
                                    .frame(width: 24)
                                Text(track.name.isEmpty ? "\(index + 1)" : track.name)
                                    .fontWeight(current ? .semibold : .regular)
                                    .foregroundStyle(current ? Color.accentColor : Color.primary)
                                Spacer(minLength: 0)
                                Text(Format.duration(ms: track.duration))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("فهرست پخش")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("بستن") { dismiss() } }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }
}
