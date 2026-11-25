import AVKit
import SwiftUI

struct SectionHeader<Destination: View>: View {
    let title: String
    var more: String = ""
    @ViewBuilder var destination: () -> Destination

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3.bold())
            Spacer()
            if !more.isEmpty {
                NavigationLink(destination: destination) {
                    HStack(spacing: 2) {
                        Text(more)
                        Image(systemName: "chevron.forward").font(.caption.bold())
                    }
                    .font(.subheadline)
                }
            }
        }
        .padding(.horizontal, Theme.gutter)
        .accessibilityAddTraits(.isHeader)
    }
}

extension SectionHeader where Destination == EmptyView {
    init(title: String) {
        self.init(title: title, more: "", destination: { EmptyView() })
    }
}

/// The system AirPlay / output picker.
struct RoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = false
        view.tintColor = .label
        view.activeTintColor = UIColor(named: "AccentColor")
        return view
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

/// Opens whatever a saved item points at.
struct SavedItemDestination: View {
    let item: SavedItem

    var body: some View {
        switch item.kind {
        case .detail, .play: DetailView(url: item.url)
        case .home: HomeInfoView(url: item.url, title: item.title)
        case .channel: ChannelLoader(id: item.ref)
        }
    }
}

/// Where a link leads, by the server's URL type.
/// 9 = playable item, 7 = serial or programme home, anything else = another list.
struct LinkDestination: View {
    let urlType: String
    let url: String
    let title: String

    var body: some View {
        switch urlType {
        case "9": DetailView(url: url)
        case "7": HomeInfoView(url: url, title: title)
        default: FeedScreen(url: url, title: title)
        }
    }
}

struct FavoriteButton: View {
    let item: SavedItem
    @EnvironmentObject private var library: Library

    var body: some View {
        let on = library.isFavorite(item)
        Button {
            Haptics.tap()
            withAnimation(.snappy) { library.toggleFavorite(item) }
        } label: {
            Image(systemName: on ? "heart.fill" : "heart")
                .foregroundStyle(on ? Color.red : Color.accentColor)
                .symbolEffect(.bounce, value: on)
        }
        .accessibilityLabel(on ? "حذف از علاقه‌مندی‌ها" : "افزودن به علاقه‌مندی‌ها")
    }
}

/// A small "راوی: …" line for a list item. The name comes from the item's own page, looked up
/// in the background the first time the item is on screen.
struct VoiceLine: View {
    let urlType: String
    let link: String
    /// Keep the line's height while the name is unknown, so a shelf does not jump when it arrives.
    var reserveSpace = false
    @State private var text: String?

    var body: some View {
        if CreditStore.applies(urlType: urlType, link: link) {
            let shown = text ?? CreditStore.cachedVoiceLine(link) ?? ""
            Group {
                if !shown.isEmpty {
                    Text(shown)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .transition(.opacity)
                } else if reserveSpace {
                    Text(" ").font(.caption2).accessibilityHidden(true)
                }
            }
            .task(id: link) {
                if let hit = CreditStore.cachedVoiceLine(link) { text = hit; return }
                // Rows that are only scrolled past do not need a lookup.
                try? await Task.sleep(nanoseconds: 400_000_000)
                if Task.isCancelled { return }
                let found = await CreditStore.shared.voiceLine(for: link)
                if !Task.isCancelled { withAnimation(.easeOut(duration: 0.2)) { text = found } }
            }
        }
    }
}

/// Swipe a row to add it to favourites, or to take it out again.
private struct FavoriteSwipe: ViewModifier {
    let box: FeedBox
    @EnvironmentObject private var library: Library

    func body(content: Content) -> some View {
        if let item = box.saved {
            let on = library.isFavorite(item)
            content.swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button {
                    Haptics.tap()
                    library.toggleFavorite(item)
                } label: {
                    Label(on ? "حذف از علاقه‌مندی‌ها" : "علاقه‌مندی", systemImage: on ? "heart.slash" : "heart")
                }
                .tint(on ? .gray : .red)
            }
        } else {
            content
        }
    }
}

extension View {
    func favoriteSwipe(_ box: FeedBox) -> some View { modifier(FavoriteSwipe(box: box)) }

    /// Rows in a plain scroll view only answer swipes from iOS 27 on; lists always do.
    @ViewBuilder func swipeHost() -> some View {
        if #available(iOS 27, *) {
            swipeActionsContainer()
        } else {
            self
        }
    }
}
