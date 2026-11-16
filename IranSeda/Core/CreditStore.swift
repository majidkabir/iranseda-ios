import Foundation

/// Who made an item: the author and the voice (narrator, singer, speaker).
struct Credits: Codable {
    var author = ""
    var voice = ""
    var voiceLabel = ""

    /// "راوی: رضا جهانی، نازنین مهیمنی", or empty when there is no voice credit.
    var voiceLine: String { voice.isEmpty ? "" : voiceLabel + ": " + voice }
}

extension PlayerDetail {
    /// Roles that count as the item's voice, most specific first.
    private static let voiceRoles = ["راوی", "گوینده", "خواننده", "سخنران", "قاری", "مداح", "قصه گو", "قصه‌گو"]

    private static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: "ي", with: "ی").replacingOccurrences(of: "ك", with: "ک")
    }

    /// Names as the service lists them ("a,b") shown with a Persian comma.
    private static func names(_ value: String) -> String {
        value.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "، ")
    }

    var credits: Credits {
        var out = Credits()
        let tags = mainTags.map { (name: Self.clean($0.tagname), value: Self.names($0.tagvalue)) }.filter { !$0.value.isEmpty }
        out.author = tags.first { $0.name.contains("نویسنده") }?.value ?? ""
        for role in Self.voiceRoles {
            if let hit = tags.first(where: { $0.name.hasPrefix(role) }) {
                out.voice = hit.value
                out.voiceLabel = role
                break
            }
        }
        return out
    }

    /// Short labelled lines for the item page: author, voice, translator.
    var creditLines: [String] {
        let credit = credits
        var lines: [String] = []
        if !credit.author.isEmpty { lines.append("نویسنده: " + credit.author) }
        if !credit.voice.isEmpty { lines.append(credit.voiceLine) }
        if let translator = mainTags.first(where: { Self.clean($0.tagname).hasPrefix("ترجمه") && !$0.tagvalue.isEmpty }) {
            lines.append("ترجمه: " + Self.names(translator.tagvalue))
        }
        return lines
    }
}

/// Narrator names for lists. Lists only carry the author; the narrator is on each item's own page.
/// So the page is fetched once, in the background, for items that are on screen, and what it says
/// is remembered on disk for good. One request at a time, newest row first.
actor CreditStore {
    static let shared = CreditStore()

    /// Thread-safe mirror, so a row can show a known narrator at once.
    nonisolated static let memory = NSCache<NSString, NSString>()

    private var known: [String: Credits] = [:]
    private var busy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var unsaved = 0
    private let file: URL

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        file = caches.appendingPathComponent("credits.json")
        if !Demo.isOn, let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode([String: Credits].self, from: data) {
            known = saved
            for (link, credit) in saved { Self.memory.setObject(credit.voiceLine as NSString, forKey: link as NSString) }
        }
    }

    /// Only item pages have credits worth fetching.
    nonisolated static func applies(urlType: String, link: String) -> Bool {
        urlType == "9" && link.lowercased().contains("details")
    }

    nonisolated static func cachedVoiceLine(_ link: String) -> String? {
        memory.object(forKey: link as NSString) as String?
    }

    /// Stores credits the app has anyway, because the user opened the item.
    func learn(_ detail: PlayerDetail, link: String) {
        remember(detail.credits, link: link)
    }

    func voiceLine(for link: String) async -> String {
        if let hit = known[link] { return hit.voiceLine }
        await acquire()
        defer { release() }
        if let hit = known[link] { return hit.voiceLine }
        // The row may have scrolled away while this waited its turn.
        if Task.isCancelled { return "" }
        guard let detail = try? await API.get(PlayerDetail.self, link) else { return "" }
        let credit = detail.credits
        remember(credit, link: link)
        return credit.voiceLine
    }

    private func remember(_ credit: Credits, link: String) {
        known[link] = credit
        Self.memory.setObject(credit.voiceLine as NSString, forKey: link as NSString)
        unsaved += 1
        if unsaved >= 5 { save() }
    }

    private func save() {
        unsaved = 0
        guard !Demo.isOn else { return }
        if let data = try? JSONEncoder().encode(known) { try? data.write(to: file, options: .atomic) }
    }

    private func acquire() async {
        if !busy { busy = true; return }
        await withCheckedContinuation { waiting.append($0) }
    }

    private func release() {
        // Newest request first: it belongs to what is on screen now.
        if let next = waiting.popLast() { next.resume() } else { busy = false; if unsaved > 0 { save() } }
    }
}
