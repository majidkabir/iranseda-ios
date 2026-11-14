import SwiftUI

/// Loads a value once and shows a spinner, an error with retry, or the content.
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
                VStack(spacing: 12) {
                    Text(failure).multilineTextAlignment(.center).foregroundStyle(.secondary)
                    Button("Retry") { Task { await run() } }
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { if value == nil { await run() } }
    }

    private func run() async {
        failure = nil
        do { value = try await load() } catch { failure = error.localizedDescription }
    }
}

struct RemoteImage: View {
    let link: String
    var body: some View {
        AsyncImage(url: API.resolve(link)) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                Rectangle().fill(.quaternary)
            }
        }
    }
}

/// Fetches a player detail from a link and starts playing it.
struct PlayButton<Label: View>: View {
    let link: String
    private let label: Label
    @State private var busy = false
    @State private var failure: String?

    init(link: String, @ViewBuilder label: () -> Label) {
        self.link = link
        self.label = label()
    }

    var body: some View {
        Button {
            Task { await play() }
        } label: {
            HStack {
                label
                if busy { ProgressView() }
            }
        }
        .disabled(busy || link.isEmpty)
        .alert("Could not play", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(failure ?? "")
        }
    }

    @MainActor private func play() async {
        busy = true
        defer { busy = false }
        do {
            let detail = try await API.get(PlayerDetail.self, link)
            guard !detail.items.isEmpty else { throw API.Failure.empty }
            Player.shared.play(detail)
        } catch {
            failure = error.localizedDescription
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
