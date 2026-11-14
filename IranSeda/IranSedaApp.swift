import SwiftUI

@main
struct IranSedaApp: App {
    @StateObject private var player = Player.shared
    @StateObject private var downloads = DownloadStore.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(player)
                .environmentObject(downloads)
                .environment(\.layoutDirection, .rightToLeft)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var player: Player
    @State private var showPlayer = false

    var body: some View {
        TabView {
            NavigationStack { HomeView() }
                .safeAreaInset(edge: .bottom) { miniPlayer }
                .tabItem { Label("Browse", systemImage: "square.grid.2x2") }
            NavigationStack { DownloadsView() }
                .safeAreaInset(edge: .bottom) { miniPlayer }
                .tabItem { Label("Downloads", systemImage: "arrow.down.circle") }
        }
        .sheet(isPresented: $showPlayer) { NowPlayingView() }
    }

    @MainActor @ViewBuilder private var miniPlayer: some View {
        if player.album != nil {
            MiniPlayer().onTapGesture { showPlayer = true }
        }
    }
}
