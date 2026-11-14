import Foundation

// MARK: - Lenient decoding helpers
// The API sends almost everything as strings, sometimes as numbers, and often
// omits keys. These wrappers make every field optional-with-default.

@propertyWrapper
struct Lossy: Decodable, Hashable {
    var wrappedValue: String
    init(wrappedValue: String = "") { self.wrappedValue = wrappedValue }
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { wrappedValue = s }
        else if let i = try? c.decode(Int.self) { wrappedValue = String(i) }
        else if let d = try? c.decode(Double.self) { wrappedValue = String(d) }
        else if let b = try? c.decode(Bool.self) { wrappedValue = b ? "1" : "0" }
        else { wrappedValue = "" }
    }
}

private struct Skip: Decodable { init(from decoder: Decoder) throws {} }

@propertyWrapper
struct LossyList<T: Decodable>: Decodable {
    var wrappedValue: [T]
    init(wrappedValue: [T] = []) { self.wrappedValue = wrappedValue }
    init(from decoder: Decoder) throws {
        var out: [T] = []
        if var c = try? decoder.unkeyedContainer() {
            while !c.isAtEnd {
                if let v = try? c.decode(T.self) { out.append(v) } else { _ = try? c.decode(Skip.self) }
            }
        }
        wrappedValue = out
    }
}

extension KeyedDecodingContainer {
    func decode(_ type: Lossy.Type, forKey key: Key) throws -> Lossy {
        (try? decodeIfPresent(type, forKey: key)) ?? Lossy()
    }
    func decode<T: Decodable>(_ type: LossyList<T>.Type, forKey key: Key) throws -> LossyList<T> {
        (try? decodeIfPresent(type, forKey: key)) ?? LossyList()
    }
}

// MARK: - initv8: the list of hubs (book, podcast, music, ...)

struct InitConfig: Decodable {
    @LossyList var Base: [Hub]
}

struct Hub: Decodable, Identifiable {
    @Lossy var Id: String
    @Lossy var headerTitle: String
    @Lossy var LogoTitle: String
    @Lossy var LogoImage: String
    @Lossy var UrlType: String      // "base" = content hub, "radio" = radio list, "web"/"external" = links
    @Lossy var UrlAddress: String
    @LossyList var tabs: [HubTab]
    var id: String { Id }
    var title: String { LogoTitle.isEmpty ? headerTitle : LogoTitle }
}

struct HubTab: Decodable, Identifiable {
    @Lossy var ID: String
    @Lossy var Title: String
    @Lossy var FeedAddress: String
    @Lossy var TabEnabled: String
    var id: String { ID + FeedAddress }
}

// MARK: - Feed page: containers of boxes (used by every hub tab and list)

struct FeedPage: Decodable {
    @Lossy var PageTitle: String
    @LossyList var Containers: [FeedContainer]
}

struct FeedContainer: Decodable {
    @Lossy var Title: String
    @Lossy var MoreTitle: String
    @Lossy var MoreLink: String
    @Lossy var isHorizontal: String
    @Lossy var isCircle: String
    @LossyList var boxes: [FeedBox]
}

struct FeedBox: Decodable {
    @Lossy var ItemID: String
    @Lossy var image: String
    @Lossy var URL: String
    @Lossy var URLType: String      // 9 = playable item, 7 = serial/programme home, 8 = another list
    @Lossy var title: String
    @Lossy var duration: String     // milliseconds
    @LossyList var tags: [Tag]
    var subtitle: String { tags.map(\.tagvalue).filter { !$0.isEmpty }.joined(separator: " · ") }
}

struct Tag: Decodable {
    @Lossy var tagname: String
    @Lossy var tagvalue: String
}

// MARK: - Player detail: one playable item with its tracks
// Returned by .../Details, .../SerialDetails, /radio/liveplayer, /radio/playbyepgid, /radio/playbytime

struct PlayerDetail: Decodable {
    @Lossy var itemid: String
    @Lossy var title: String
    @Lossy var PlaylistTitle: String
    @Lossy var chTitle: String
    @Lossy var type: String         // "aod" or "live"
    @Lossy var image: String
    @Lossy var imageCover: String
    @Lossy var abstract: String
    @Lossy var desc: String
    @LossyList var mainTags: [Tag]
    @LossyList var items: [Track]
    @LossyList var related: [RelatedItem]

    enum CodingKeys: String, CodingKey {
        case itemid, title, PlaylistTitle, chTitle, type, image, abstract, desc, mainTags, items, related
        case imageCover = "image-cover"
    }

    var displayTitle: String { title.isEmpty ? PlaylistTitle : title }
    var isLive: Bool { type == "live" }
    var cover: String { imageCover.isEmpty ? image : imageCover }
}

struct Track: Decodable {
    @Lossy var name: String
    @Lossy var duration: String     // milliseconds
    @Lossy var candownload: String
    @Lossy var FileID: String
    @Lossy var FileKey: String
    @Lossy var playUrl: String      // HLS playlist
    @LossyList var download: [DownloadOption]
}

struct DownloadOption: Decodable {
    @Lossy var downloadUrl: String
    @Lossy var fileSize: String
    @Lossy var bitRate: String
    @Lossy var `extension`: String
}

struct RelatedItem: Decodable {
    @Lossy var ItemID: String
    @Lossy var image: String
    @Lossy var URL: String
    @Lossy var title: String
    @Lossy var urlType: String
}

// MARK: - Serial home / radio programme home

struct HomeInfo: Decodable {
    @Lossy var serialName: String
    @Lossy var programName: String
    @Lossy var radioName: String
    @Lossy var imageurl: String
    @Lossy var abstract: String
    @Lossy var description: String
    @LossyList var tabs: [LinkTab]
    var title: String { serialName.isEmpty ? programName : serialName }
}

struct LinkTab: Decodable, Identifiable {
    @Lossy var title: String
    @Lossy var feedAddress: String
    @Lossy var type: String
    var id: String { type + feedAddress }
}

// MARK: - Radio

struct RadioList: Decodable {
    @LossyList var channels: [Channel]
}

struct Channel: Decodable, Identifiable {
    @Lossy var id: String
    @Lossy var title: String
    @Lossy var typeTitle: String    // سراسری (national) / استانی (provincial)
    @Lossy var logo: String
    @Lossy var name: String         // programme on air now
    @LossyList var tabs: [LinkTab]  // 1 live, 2 schedule, 3 programmes, 4 time archive
}

struct LiveInfo: Decodable {
    @Lossy var name: String
    @Lossy var image: String
    @Lossy var PlayURL: String
    @Lossy var desc1: String
    @Lossy var desc2: String
    @Lossy var programHome: String
}

struct Schedule: Decodable {
    @LossyList var EPGRecords: [ScheduleRecord]
}

struct ScheduleRecord: Decodable {
    @Lossy var epgid: String
    @Lossy var programname: String
    @Lossy var programdesc1: String
    @Lossy var start: String        // epoch milliseconds
    @Lossy var status: String       // "live" for the current programme
    @Lossy var image: String
    @Lossy var epgDesc: String      // link to a player detail
}

struct ProgramItem: Decodable {
    @Lossy var groupID: String
    @Lossy var title: String
    @Lossy var imageUrl: String
    @Lossy var programHome: String
}

struct TimeArchive: Decodable {
    @Lossy var dateStr: String
    @LossyList var items: [TimeSlot]
}

struct TimeSlot: Decodable {
    @Lossy var TimeArchivePart: String
    @Lossy var timeStr: String
}

struct TimeArchivePart: Decodable {
    @Lossy var dateStr: String
    @Lossy var timeStr: String
    @Lossy var PlayUrlByTime: String
    @LossyList var programs: [ArchivedProgram]
}

struct ArchivedProgram: Decodable {
    @Lossy var progName: String
    @Lossy var progDesc1: String
    @Lossy var progCoverUrl: String
    @Lossy var progStart: String
    @Lossy var progDuration: String
    @Lossy var PlayUrl: String
}

// MARK: - Formatting

enum Format {
    /// "12590000" (ms) -> "3:29:50"
    static func duration(ms: String) -> String {
        guard let v = Double(ms), v > 0 else { return "" }
        return clock(v / 1000)
    }

    static func clock(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let t = Int(seconds)
        let h = t / 3600, m = (t % 3600) / 60, s = t % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    static func time(epochMs: String) -> String {
        guard let v = Double(epochMs), v > 0 else { return "" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.timeZone = TimeZone(identifier: "Asia/Tehran")
        return f.string(from: Date(timeIntervalSince1970: v / 1000))
    }
}
