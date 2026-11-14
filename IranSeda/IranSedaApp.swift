import SwiftUI

@main
struct IranSedaApp: App {
    @StateObject private var player = Player.shared
    @StateObject private var downloads = DownloadStore.shared
    @StateObject private var library = Library.shared

    init() {
        // Covers and logos are small and reused everywhere; keep them on disk.
        URLCache.shared = URLCache(memoryCapacity: 32 << 20, diskCapacity: 256 << 20)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(player)
                .environmentObject(downloads)
                .environmentObject(library)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "fa"))
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var player: Player
    @State private var showPlayer = false
    @State private var tab: Int

    init() {
        let start: Int
        switch Demo.isOn ? Demo.screen : "home" {
        case "radio": start = 1
        case "library", "downloads", "recents": start = 2
        case "settings": start = 3
        default: start = 0
        }
        _tab = State(initialValue: start)
    }

    var body: some View {
        TabView(selection: $tab) {
            page { demoRoot ?? AnyView(HomeView()) }
                .tabItem { Label("خانه", systemImage: "house.fill") }
                .tag(0)
            page { RadioView() }
                .tabItem { Label("رادیو", systemImage: "dot.radiowaves.left.and.right") }
                .tag(1)
            page { LibraryView() }
                .tabItem { Label("کتابخانه", systemImage: "books.vertical.fill") }
                .tag(2)
            page { SettingsView() }
                .tabItem { Label("تنظیمات", systemImage: "gearshape.fill") }
                .tag(3)
        }
        .sheet(isPresented: $showPlayer) {
            NowPlayingView()
                .presentationDragIndicator(.visible)
        }
        .task { await prepareDemo() }
    }

    private func page<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        NavigationStack { content() }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if player.album != nil {
                    MiniPlayer { showPlayer = true }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: player.album != nil)
    }

    /// Deep screens for screenshots (`-demo YES -screen channel`, ...).
    private var demoRoot: AnyView? {
        guard Demo.isOn else { return nil }
        switch Demo.screen {
        case "channel": return AnyView(ChannelLoader(id: "12"))
        case "hub": return AnyView(HubLoader())
        case "detail": return AnyView(DetailView(url: "/book/Details/?g=1"))
        case "serial": return AnyView(HomeInfoView(url: "/book/serialhome/?p=1", title: "قصه‌های جزیره"))
        default: return nil
        }
    }

    @MainActor private func prepareDemo() async {
        guard Demo.isOn, Demo.screen != "empty" else { return }
        let live = Demo.screen == "playerlive"
        try? await Playback.play(link: live ? "/radio/liveplayer/?CH=12" : "/book/Details/?g=1")
        if !live { player.jump(to: 1) }
        if Demo.screen.hasPrefix("player") { showPlayer = true }
    }
}
