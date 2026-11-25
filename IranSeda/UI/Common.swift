import SwiftUI
#if os(watchOS)
import WatchKit
#endif

// Views and helpers shared by the iPhone app and the Apple Watch app.

enum Theme {
    static let corner: CGFloat = 14
    static let gutter: CGFloat = 16

    private static let palette: [(Color, Color)] = [
        (Color(red: 0.05, green: 0.58, blue: 0.42), Color(red: 0.02, green: 0.31, blue: 0.32)),
        (Color(red: 0.20, green: 0.45, blue: 0.85), Color(red: 0.10, green: 0.22, blue: 0.52)),
        (Color(red: 0.85, green: 0.45, blue: 0.20), Color(red: 0.55, green: 0.20, blue: 0.15)),
        (Color(red: 0.60, green: 0.35, blue: 0.80), Color(red: 0.30, green: 0.15, blue: 0.50)),
        (Color(red: 0.85, green: 0.30, blue: 0.45), Color(red: 0.50, green: 0.12, blue: 0.30)),
        (Color(red: 0.25, green: 0.62, blue: 0.70), Color(red: 0.08, green: 0.30, blue: 0.42)),
    ]

    /// A stable gradient per title, used when an item has no picture.
    static func gradient(for text: String) -> LinearGradient {
        let hash = text.unicodeScalars.reduce(UInt32(2166136261)) { ($0 ^ $1.value) &* 16777619 }
        let pair = palette[Int((hash >> 8) % UInt32(palette.count))]
        return LinearGradient(colors: [pair.0, pair.1], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

enum Haptics {
    #if os(watchOS)
    static func tap() { WKInterfaceDevice.current().play(.click) }
    static func success() { WKInterfaceDevice.current().play(.success) }
    #else
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    #endif
}

/// A picture from the server, with a titled gradient tile while loading or when missing.
struct Artwork: View {
    let link: String
    var title: String = ""
    var symbol: String = "waveform"
    @State private var loaded: UIImage?

    private var url: URL? { Demo.isOn ? nil : API.resolve(link) }

    var body: some View {
        // An image already in memory shows at once, with no placeholder flash.
        let image = loaded ?? url.flatMap(ImageStore.cached)
        GeometryReader { geo in
            ZStack {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .transition(.opacity)
                } else {
                    Theme.gradient(for: title)
                    Image(systemName: symbol)
                        .font(.system(size: max(12, min(geo.size.width, geo.size.height) * 0.36), weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
        }
        .task(id: link) {
            guard let url else { loaded = nil; return }
            if let hit = ImageStore.cached(url) { loaded = hit; return }
            loaded = nil
            let fetched = await ImageStore.shared.image(for: url)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { loaded = fetched }
        }
        .accessibilityHidden(true)
    }
}

/// Loads a value once and shows a spinner, an error with retry, or the content.
/// Pull to refresh reloads it.
struct Loader<T, Content: View>: View {
    private let load: () async throws -> T
    private let content: (T) -> Content
    @State private var value: T?
    @State private var failure: String?

    init(load: @escaping () async throws -> T, @ViewBuilder content: @escaping (T) -> Content) {
        self.load = load
        self.content = content
    }

    var body: some View {
        Group {
            if let value {
                content(value)
            } else if let failure {
                ContentUnavailableView {
                    Label("بارگیری نشد", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(failure)
                } actions: {
                    Button("تلاش دوباره") { Task { await run() } }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                ProgressView()
                    #if os(iOS)
                    .controlSize(.large)
                    #endif
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("در حال بارگیری")
            }
        }
        .task { if value == nil { await run() } }
        #if os(iOS)
        .refreshable { await API.$wantsFresh.withValue(true) { await run() } }
        #endif
    }

    private func run() async {
        failure = nil
        do { value = try await load() } catch is CancellationError {
        } catch { if value == nil { failure = error.localizedDescription } }
    }
}

/// A button that runs async work, shows a spinner meanwhile and an alert on failure.
struct AsyncButton<Label: View>: View {
    private let action: () async throws -> Void
    private let label: Label
    @State private var busy = false
    @State private var failure: String?

    init(action: @escaping () async throws -> Void, @ViewBuilder label: () -> Label) {
        self.action = action
        self.label = label()
    }

    var body: some View {
        Button {
            guard !busy else { return }
            Haptics.tap()
            busy = true
            Task {
                do { try await action() } catch { failure = error.localizedDescription }
                busy = false
            }
        } label: {
            label.opacity(busy ? 0.4 : 1).overlay { if busy { ProgressView() } }
        }
        .alert("پخش نشد", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("باشه", role: .cancel) {}
        } message: {
            Text(failure ?? "")
        }
    }
}

