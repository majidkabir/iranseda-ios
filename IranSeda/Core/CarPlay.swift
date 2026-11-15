import CarPlay
import UIKit

/// CarPlay audio app: favourites, stations and recently played, plus the system Now Playing screen.
///
/// CarPlay only shows the app once Apple has granted the CarPlay audio entitlement and it is
/// added to the app; see docs/CARPLAY.md. Until then this code is never called.
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
        Task { @MainActor in await showRoot() }
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        self.interfaceController = nil
    }

    @MainActor
    private func showRoot() async {
        let stations = CPListTemplate(title: "رادیو", sections: [])
        stations.tabImage = UIImage(systemName: "dot.radiowaves.left.and.right")
        let favorites = CPListTemplate(title: "علاقه‌مندی‌ها", sections: [savedSection(Library.shared.favorites)])
        favorites.tabImage = UIImage(systemName: "heart.fill")
        favorites.emptyViewTitleVariants = ["هنوز چیزی اضافه نکرده‌اید"]
        let recents = CPListTemplate(title: "اخیر", sections: [savedSection(Library.shared.recents)])
        recents.tabImage = UIImage(systemName: "clock")
        recents.emptyViewTitleVariants = ["هنوز چیزی گوش نکرده‌اید"]

        let tabs = CPTabBarTemplate(templates: [favorites, stations, recents])
        _ = try? await interfaceController?.setRootTemplate(tabs, animated: false)

        if let list = try? await API.get(RadioList.self, API.radioPath) {
            let items = list.channels.prefix(CPListTemplate.maximumItemCount).map { channel in
                item(title: channel.title, detail: channel.name) { try await Playback.playLive(channel) }
            }
            stations.updateSections([CPListSection(items: Array(items))])
        } else {
            stations.emptyViewTitleVariants = ["بارگیری نشد"]
        }
    }

    @MainActor
    private func savedSection(_ saved: [SavedItem]) -> CPListSection {
        let items = saved.prefix(CPListTemplate.maximumItemCount).map { entry in
            item(title: entry.title, detail: entry.subtitle) {
                switch entry.kind {
                case .channel:
                    let list = try await API.get(RadioList.self, API.radioPath)
                    guard let channel = list.channels.first(where: { $0.id == entry.ref }) else { throw API.Failure.empty }
                    try await Playback.playLive(channel)
                case .detail, .play:
                    try await Playback.play(link: entry.url, source: entry)
                case .home:
                    throw API.Failure.empty   // a series has no single thing to play
                }
            }
        }
        return CPListSection(items: Array(items))
    }

    /// A row that starts playback and then shows the Now Playing screen.
    @MainActor
    private func item(title: String, detail: String, play: @escaping () async throws -> Void) -> CPListItem {
        let row = CPListItem(text: title, detailText: detail.isEmpty ? nil : detail)
        row.handler = { [weak self] _, completion in
            Task { @MainActor in
                do {
                    try await play()
                    _ = try? await self?.interfaceController?.pushTemplate(CPNowPlayingTemplate.shared, animated: true)
                } catch {
                    // Leave the list as it is; the row simply stops spinning.
                }
                completion()
            }
        }
        return row
    }
}
