import SwiftUI

/// Seda+ on Apple Watch. It runs on its own: it talks to the service over the watch's Wi-Fi
/// or cellular connection and plays through Bluetooth headphones or the watch speaker.
@main
struct SedaWatchApp: App {
    @StateObject private var player = Player.shared
    @StateObject private var downloads = DownloadStore.shared
    @StateObject private var library = Library.shared
    @StateObject private var nav = WatchNav()

    init() {
        URLCache.shared = URLCache(memoryCapacity: 8 << 20, diskCapacity: 32 << 20)
        Task.detached(priority: .background) { await ImageStore.shared.prune() }
    }

    var body: some Scene {
        WindowGroup {
            WatchRoot()
                .environmentObject(player)
                .environmentObject(downloads)
                .environmentObject(library)
                .environmentObject(nav)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "fa"))
        }
    }
}

/// App-wide navigation state: the player opens by itself whenever something starts.
@MainActor
final class WatchNav: ObservableObject {
    @Published var showPlayer = false

    /// Runs a "play" action, then shows the player.
    func play(_ work: () async throws -> Void) async throws {
        try await work()
        showPlayer = true
    }
}

struct WatchRoot: View {
    @EnvironmentObject private var player: Player
    @EnvironmentObject private var nav: WatchNav

    var body: some View {
        NavigationStack {
            demoRoot ?? AnyView(WatchHome())
        }
        .sheet(isPresented: $nav.showPlayer) {
            // A sheet starts a new environment on the watch: set the direction again.
            PlayerScreen()
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "fa"))
        }
        .alert("پخش نشد", isPresented: Binding(
            get: { player.failure != nil },
            set: { if !$0 { player.failure = nil } })) {
            Button("باشه", role: .cancel) {}
        } message: {
            Text(player.failure ?? "")
        }
        .task { await prepareDemo() }
    }

    /// Screenshots open a screen directly with `-screen <name>`.
    private var demoRoot: AnyView? {
        switch Demo.screen {
        case "radio": return AnyView(StationsScreen())
        case "channel": return AnyView(ChannelLoader(id: "12"))
        case "hubs": return AnyView(HubsScreen())
        case "hub": return AnyView(HubLoader())
        case "detail": return AnyView(DetailScreen(url: Demo.isOn ? "/book/Details/?g=1" : "/book/Details/?VALID=TRUE&g=730197"))
        case "serial": return AnyView(SeriesScreen(url: "/book/serialhome/?p=1", title: "قصه‌های جزیره"))
        case "search": return AnyView(SearchScreen(initialQuery: UserDefaults.standard.string(forKey: "query") ?? "رادیو"))
        case "library": return AnyView(SavedScreen(part: .favorites))
        case "recents": return AnyView(SavedScreen(part: .recents))
        case "downloads": return AnyView(DownloadsScreen())
        case "settings": return AnyView(WatchSettings())
        default: return nil
        }
    }

    @MainActor private func prepareDemo() async {
        guard Demo.isOn, Demo.screen != "empty" else { return }
        let live = Demo.screen == "playerlive"
        try? await Playback.play(link: live ? "/radio/liveplayer/?CH=12" : "/book/Details/?g=1")
        if !live { player.jump(to: 1) }
        if Demo.screen.hasPrefix("player") { nav.showPlayer = true }
    }
}

/// First screen: what is playing, then the main sections.
struct WatchHome: View {
    @EnvironmentObject private var player: Player
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var nav: WatchNav

    var body: some View {
        List {
            if player.album != nil {
                Button { nav.showPlayer = true } label: { NowPlayingRow() }
                    .listItemTint(Color.accentColor)
            }
            if let last = library.recents.first, player.album == nil, last.kind != .home {
                Section("ادامه شنیدن") {
                    PlaySavedButton(item: last)
                }
            }
            Section {
                NavigationLink { StationsScreen() } label: {
                    MenuLabel(title: "رادیو", symbol: "dot.radiowaves.left.and.right", color: .red)
                }
                NavigationLink { HubsScreen() } label: {
                    MenuLabel(title: "کتاب و پادکست", symbol: "books.vertical.fill", color: .purple)
                }
                NavigationLink { SearchScreen() } label: {
                    MenuLabel(title: "جست‌وجو", symbol: "magnifyingglass", color: .blue)
                }
            }
            Section {
                NavigationLink { SavedScreen(part: .favorites) } label: {
                    MenuLabel(title: "علاقه‌مندی‌ها", symbol: "heart.fill", color: .pink)
                }
                NavigationLink { SavedScreen(part: .recents) } label: {
                    MenuLabel(title: "اخیر", symbol: "clock.fill", color: .orange)
                }
                NavigationLink { DownloadsScreen() } label: {
                    MenuLabel(title: "دانلودها", symbol: "arrow.down.circle.fill", color: .green)
                }
                NavigationLink { WatchSettings() } label: {
                    MenuLabel(title: "تنظیمات", symbol: "gearshape.fill", color: .gray)
                }
            }
        }
        .navigationTitle("Seda+")
    }
}

private struct MenuLabel: View {
    let title: String
    let symbol: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(color.gradient, in: Circle())
            Text(title).lineLimit(2)
        }
        .padding(.vertical, 2)
    }
}

/// The "now playing" row at the top of Home.
struct NowPlayingRow: View {
    @EnvironmentObject private var player: Player

    var body: some View {
        HStack(spacing: 10) {
            Artwork(link: player.album?.cover ?? "", title: player.subtitle, symbol: player.isLive ? "dot.radiowaves.left.and.right" : "headphones")
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 1) {
                Text(player.title).font(.footnote.weight(.semibold)).lineLimit(1)
                Text(player.subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: player.isPlaying ? "waveform" : "pause.fill")
                .symbolEffect(.variableColor.iterative, isActive: player.isPlaying)
                .foregroundStyle(Color.accentColor)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("در حال پخش: \(player.title)")
    }
}
