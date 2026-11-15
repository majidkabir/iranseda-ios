import SwiftUI
import WidgetKit

struct SedaEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct SedaProvider: TimelineProvider {
    func placeholder(in context: Context) -> SedaEntry {
        SedaEntry(date: .now, snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (SedaEntry) -> Void) {
        completion(SedaEntry(date: .now, snapshot: context.isPreview ? .sample : .load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SedaEntry>) -> Void) {
        // The app reloads the widget whenever favourites or history change.
        completion(Timeline(entries: [SedaEntry(date: .now, snapshot: .load())], policy: .never))
    }
}

struct SedaWidgetView: View {
    let snapshot: WidgetSnapshot
    @Environment(\.widgetFamily) private var family

    private let accent = Color(red: 0.05, green: 0.58, blue: 0.42)

    var body: some View {
        Group {
            if snapshot.recent == nil && snapshot.stations.isEmpty {
                empty
            } else if family == .systemSmall {
                small
            } else {
                medium
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .containerBackground(for: .widget) { Color(.systemBackground) }
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform").font(.title2).foregroundStyle(accent)
            Text("چیزی پخش کنید یا شبکه‌ای را به علاقه‌مندی‌ها اضافه کنید")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder private var small: some View {
        if let entry = snapshot.recent ?? snapshot.stations.first {
            resume(entry).widgetURL(entry.url)
        }
    }

    private var medium: some View {
        HStack(spacing: 12) {
            if let entry = snapshot.recent {
                Link(destination: entry.url) { resume(entry) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            if !snapshot.stations.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(snapshot.stations.prefix(3)) { station in
                        Link(destination: station.url) {
                            HStack(spacing: 8) {
                                Image(systemName: "dot.radiowaves.left.and.right")
                                    .font(.caption)
                                    .foregroundStyle(.white)
                                    .frame(width: 26, height: 26)
                                    .background(accent, in: Circle())
                                Text(station.title).font(.footnote.weight(.medium)).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 5)
                            .padding(.horizontal, 8)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                        }
                        .accessibilityLabel("پخش زنده \(station.title)")
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    private func resume(_ entry: WidgetSnapshot.Entry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: entry.isStation ? "dot.radiowaves.left.and.right" : "headphones")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(accent, in: RoundedRectangle(cornerRadius: 10))
            Spacer(minLength: 0)
            Text(entry.isStation ? "پخش زنده" : "ادامه شنیدن")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(accent)
            Text(entry.title).font(.subheadline.weight(.semibold)).lineLimit(2)
            if !entry.subtitle.isEmpty {
                Text(entry.subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }
}

@main
struct SedaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSnapshot.kind, provider: SedaProvider()) { entry in
            SedaWidgetView(snapshot: entry.snapshot)
        }
        .configurationDisplayName("ایران‌صدا")
        .description("ادامه شنیدن و شبکه‌های دلخواه شما.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
