import Foundation

/// Sample data for screenshots: launch with `-demo YES -screen <name>`.
/// In demo mode nothing touches the network, the disk or the audio session.
enum Demo {
    static let isOn = UserDefaults.standard.bool(forKey: "demo")
    static let screen = UserDefaults.standard.string(forKey: "screen") ?? "home"

    static func data(for link: String) -> Data {
        let l = link.lowercased()
        let json: String
        if l.contains("initv8") { json = initJSON }
        else if l.contains("liveplayer") || l.contains("playby") { json = liveDetailJSON }
        else if l.contains("channelcurrentprogdata") || l.contains("programlastepisode") { json = liveInfoJSON }
        else if l.contains("epgarchivelist") { json = scheduleJSON }
        else if l.contains("programarchivelist") { json = episodesJSON }
        else if l.contains("programlist") { json = programsJSON }
        else if l.contains("timearchivepart") { json = archivePartJSON }
        else if l.contains("timearchive") { json = timeArchiveJSON }
        else if l.contains("details") { json = detailJSON }
        else if l.contains("serialhome") || l.contains("programhome") { json = homeJSON }
        else if l.hasSuffix("/radio/") { json = radioJSON }
        else { json = feedJSON }
        return Data(json.utf8)
    }

    static let favorites: [SavedItem] = [
        SavedItem(kind: .channel, url: "/radio/", ref: "12", title: "رادیو پیام", subtitle: "بخش شبانگاهی", image: ""),
        SavedItem(kind: .detail, url: "/book/Details/?g=1", title: "نام من سرخ", subtitle: "کتاب گویا", image: ""),
        SavedItem(kind: .channel, url: "/radio/", ref: "20", title: "رادیو نمایش", subtitle: "نمایش شب", image: ""),
        SavedItem(kind: .home, url: "/book/serialhome/?p=1", title: "قصه‌های جزیره", subtitle: "سریال", image: ""),
    ]

    static let recents: [SavedItem] = [
        SavedItem(kind: .detail, url: "/book/Details/?g=2", title: "جنگ دنیاها", subtitle: "کتاب گویا", image: ""),
        SavedItem(kind: .channel, url: "/radio/", ref: "12", title: "رادیو پیام", subtitle: "پخش زنده", image: ""),
        SavedItem(kind: .detail, url: "/podcast/Details/?g=3", title: "رادیو راه", subtitle: "پادکست", image: ""),
        SavedItem(kind: .detail, url: "/music/Details/?g=4", title: "شب‌های تهران", subtitle: "موسیقی", image: ""),
    ]

    static let downloads: [DownloadedItem] = [
        DownloadedItem(id: "d1", title: "فصل اول", album: "نام من سرخ", image: "", fileName: "d1.mp4", durationMs: "1836000", bytes: 28_400_000),
        DownloadedItem(id: "d2", title: "فصل دوم", album: "نام من سرخ", image: "", fileName: "d2.mp4", durationMs: "2104000", bytes: 32_100_000),
        DownloadedItem(id: "d3", title: "قسمت ۱۲", album: "رادیو راه", image: "", fileName: "d3.mp4", durationMs: "2710000", bytes: 41_800_000),
    ]

    // MARK: - JSON

    private static func tabs(_ base: String) -> String {
        """
        [{"ID":"1","Title":"خانه","FeedAddress":"/\(base)/vitrin","TabEnabled":"1"},
         {"ID":"2","Title":"تازه‌ها","FeedAddress":"/\(base)/last","TabEnabled":"1"},
         {"ID":"3","Title":"شنیدنی","FeedAddress":"/\(base)/best","TabEnabled":"1"},
         {"ID":"4","Title":"دسته‌بندی","FeedAddress":"/\(base)/cats","TabEnabled":"1"}]
        """
    }

    private static var initJSON: String {
        """
        {"Base":[
         {"Id":"3","LogoTitle":"پخش زنده و آرشیو رادیو","UrlType":"radio","UrlAddress":"/radio/"},
         {"Id":"1021","LogoTitle":"کتاب گویا","UrlType":"base","UrlAddress":"/book/","tabs":\(tabs("book"))},
         {"Id":"1027","LogoTitle":"پادکست","UrlType":"base","UrlAddress":"/podcast/","tabs":\(tabs("podcast"))},
         {"Id":"1023","LogoTitle":"موسیقی","UrlType":"base","UrlAddress":"/music/","tabs":\(tabs("music"))},
         {"Id":"1026","LogoTitle":"کودک","UrlType":"base","UrlAddress":"/kids/","tabs":\(tabs("kids"))},
         {"Id":"1022","LogoTitle":"قرآن","UrlType":"base","UrlAddress":"/quran/","tabs":\(tabs("quran"))},
         {"Id":"1024","LogoTitle":"سخنرانی","UrlType":"base","UrlAddress":"/sokhanrani/","tabs":\(tabs("sokhanrani"))},
         {"Id":"1025","LogoTitle":"دعا و نغمه","UrlType":"base","UrlAddress":"/nava/","tabs":\(tabs("nava"))},
         {"Id":"1029","LogoTitle":"تاریخ شفاهی","UrlType":"base","UrlAddress":"/history/","tabs":\(tabs("history"))}
        ]}
        """
    }

    private static func channel(_ id: String, _ title: String, _ type: String, _ now: String) -> String {
        """
        {"id":"\(id)","title":"\(title)","typeTitle":"\(type)","logo":"","name":"\(now)","tabs":[
         {"title":"پخش زنده","feedAddress":"/radio/ChannelCurrentProgData/?ch=\(id)","type":"1"},
         {"title":"جدول پخش","feedAddress":"/radio/epgarchivelist/?ch=\(id)","type":"2"},
         {"title":"برنامه‌ها","feedAddress":"/radio/programlist/?ch=\(id)","type":"3"},
         {"title":"آرشیو","feedAddress":"/radio/TimeArchive/?ch=\(id)","type":"4"}]}
        """
    }

    private static var radioJSON: String {
        let national = [("12", "رادیو پیام", "بخش شبانگاهی"), ("11", "رادیو ایران", "راه شب"), ("13", "رادیو جوان", "اینجا شب نیست"),
                        ("14", "رادیو فرهنگ", "درس مثنوی"), ("20", "رادیو نمایش", "نمایش شب"), ("15", "رادیو ورزش", "ورزش و مردم"),
                        ("16", "رادیو سلامت", "با من بگو"), ("17", "رادیو آوا", "ادامه بخش شبانگاهی"), ("18", "رادیو گفت‌وگو", "کاشف"),
                        ("19", "رادیو اقتصاد", "راه شب")]
        let provincial = [("101", "رادیو تهران", "کلاغ پر"), ("102", "رادیو اصفهان", "شب‌های زنده‌رود"), ("103", "رادیو فارس", "شب شیراز"),
                          ("104", "رادیو خراسان", "هشتمین بهشت")]
        let all = national.map { channel($0.0, $0.1, "سراسری", $0.2) } + provincial.map { channel($0.0, $0.1, "استانی", $0.2) }
        return "{\"channels\":[\(all.joined(separator: ","))]}"
    }

    private static func box(_ id: Int, _ title: String, _ by: String, type: String = "9", duration: String = "5317000") -> String {
        let url = type == "7" ? "/book/serialhome/?p=\(id)" : "/book/Details/?g=\(id)"
        return "{\"ItemID\":\"\(id)\",\"image\":\"\",\"URL\":\"\(url)\",\"URLType\":\"\(type)\",\"title\":\"\(title)\",\"duration\":\"\(duration)\",\"tags\":[{\"tagname\":\"\",\"tagvalue\":\"\(by)\"}]}"
    }

    private static var feedJSON: String {
        let shelf1 = [box(1, "نام من سرخ", "اورهان پاموک"), box(2, "جنگ دنیاها", "اچ. جی. ولز"), box(3, "مرد آسمانی", "نمایشی"),
                      box(4, "قطره‌ی جوهر", "روایی"), box(5, "راه بی‌انتها", "روایی"), box(6, "آب‌های سنگی", "نمایشی")]
        let shelf2 = [box(11, "قصه‌های جزیره", "۲۶ قسمت", type: "7"), box(12, "آنه در خانه‌ی رویاها", "۱۸ قسمت", type: "7"),
                      box(13, "دره رنگین‌کمان", "۲۰ قسمت", type: "7"), box(14, "ریلا در اینگل‌ساید", "۳۰ قسمت", type: "7")]
        let people = [box(21, "حافظ", ""), box(22, "سعدی", ""), box(23, "مولانا", ""), box(24, "فردوسی", ""), box(25, "نیما", "")]
        let list = [box(31, "سلول سیزده", "ژاک فوترل", duration: "3120000"), box(32, "مادر عراقی من", "روایی", duration: "8200000"),
                    box(33, "پرواز دوگاهه", "نمایشی", duration: "2760000"), box(34, "کد ۰۸", "نمایشی", duration: "4100000"),
                    box(35, "کتاب‌فروشی کوچک بروکن‌ویل", "روایی", duration: "11200000")]
        return """
        {"PageTitle":"کتاب‌ها","Containers":[
         {"Title":"شنیدنی‌ها","MoreTitle":"همه","MoreLink":"/book/best","isHorizontal":"1","boxes":[\(shelf1.joined(separator: ","))]},
         {"Title":"سریال‌ها","MoreTitle":"همه","MoreLink":"/book/serials","isHorizontal":"1","boxes":[\(shelf2.joined(separator: ","))]},
         {"Title":"ادیبان و شاعران","MoreTitle":"بیشتر","MoreLink":"/book/farsi-poem","isHorizontal":"1","isCircle":"1","boxes":[\(people.joined(separator: ","))]},
         {"Title":"تازه‌ها","isHorizontal":"0","boxes":[\(list.joined(separator: ","))]}
        ]}
        """
    }

    private static var detailJSON: String {
        let names = ["صدای نمونه کتاب", "فصل اول: من مرده‌ام", "فصل دوم: نام من قره است", "فصل سوم: من، سگ", "فصل چهارم: به من قاتل خواهند گفت", "فصل پنجم: من شوهرخاله‌ی شما هستم"]
        let durations = ["157000", "1836000", "2104000", "1522000", "1990000", "2380000"]
        let items = zip(names, durations).enumerated().map { index, pair in
            "{\"name\":\"\(pair.0)\",\"duration\":\"\(pair.1)\",\"candownload\":\"1\",\"FileID\":\"demo\(index)\",\"playUrl\":\"/demo/\(index).m3u8\",\"download\":[{\"downloadUrl\":\"/demo/\(index).mp4\",\"fileSize\":\"28000000\",\"bitRate\":\"128\",\"extension\":\"mp4\"}]}"
        }
        return """
        {"itemid":"1","title":"نام من سرخ","PlaylistTitle":"نام من سرخ","chTitle":"کتاب گویا","type":"aod","image":"",
         "abstract":"پاموک در این کتاب، مرز میان تاریخ، فلسفه‌ی هنر و داستان‌گویی مدرن را از میان برمی‌دارد.",
         "desc":"او با استفاده از ساختاری چندصدایی، به هر شخصیت صدایی مستقل می‌دهد؛ تا جایی که حتی «سرخ» خود روایتگر یکی از فصل‌هاست. داستان از قتل یکی از نگارگران دربار آغاز می‌شود و کم‌کم در دل معمایی هنری و عاشقانه فرو می‌رود.",
         "mainTags":[{"tagname":"قالب كتاب گویا","tagvalue":"روایی"},{"tagname":"راوی","tagvalue":"رضا جهانی,نازنین مهیمنی"},{"tagname":"ترجمه / اقتباس شنیداری","tagvalue":"ماهرخ حیدری"},{"tagname":"نویسنده اثر مرجع","tagvalue":"اورهان پاموک"}],
         "items":[\(items.joined(separator: ","))],
         "related":[{"ItemID":"2","image":"","URL":"/book/Details/?g=2","title":"جنگ دنیاها","urlType":"9"},
                    {"ItemID":"31","image":"","URL":"/book/Details/?g=31","title":"سلول سیزده","urlType":"9"},
                    {"ItemID":"32","image":"","URL":"/book/Details/?g=32","title":"مادر عراقی من","urlType":"9"}]}
        """
    }

    private static let liveInfoJSON = """
    {"name":"بخش شبانگاهی (زنده)","image":"","PlayURL":"/radio/liveplayer/?CH=12",
     "desc1":"www.radiopayam.ir","desc2":"خبر، موسیقی بی‌کلام، موسیقی با کلام، پیام‌های بازرگانی","programHome":"/radio/ProgramHome/?ch=12&m=1"}
    """

    private static let liveDetailJSON = """
    {"itemid":"024105","title":"رادیو پیام","PlaylistTitle":"پخش زنده رادیو پیام","chTitle":"پخش زنده","type":"live","image":"",
     "items":[{"name":"بخش شبانگاهی (زنده)","duration":"7200000","candownload":"0","playUrl":"/demo/live.m3u8"}]}
    """

    private static var scheduleJSON: String {
        let rows = [("1794700800000", "بخش شبانگاهی", "live"), ("1794708000000", "بخش سحرگاهی", ""), ("1794715200000", "بخش صبحگاهی", ""),
                    ("1794729600000", "بخش نیمروزی", ""), ("1794744000000", "بخش عصرگاهی", ""), ("1794758400000", "بخش شامگاهی", "")]
        let records = rows.map { "{\"epgid\":\"\($0.0)\",\"programname\":\"\($0.1)\",\"programdesc1\":\"خبر، موسیقی و ترافیک\",\"start\":\($0.0),\"status\":\"\($0.2)\",\"image\":\"\",\"epgDesc\":\"/radio/playbyepgid/?e=\($0.0)\"}" }
        return "{\"EPGRecords\":[\(records.joined(separator: ","))]}"
    }

    private static var programsJSON: String {
        let names = ["بخش سحرگاهی", "بخش صبحگاهی", "بخش نیمروزی", "بخش عصرگاهی", "بخش شامگاهی", "بخش شبانگاهی"]
        let rows = names.enumerated().map { "{\"groupID\":\"\($0.offset)\",\"title\":\"\($0.element)\",\"imageUrl\":\"\",\"programHome\":\"/radio/ProgramHome/?ch=12&m=\($0.offset)\"}" }
        return "[\(rows.joined(separator: ","))]"
    }

    private static var episodesJSON: String {
        let rows = (0..<8).map { "{\"itemid\":\"e\($0)\",\"day\":\"\(23 - $0)\",\"month\":\"آبان\",\"year\":\"1405-ساعت 22:00\",\"description1\":\"خبر، موسیقی و ترافیک\",\"duration\":\"7200\",\"PlayURL\":\"/radio/playbyepgid/?e=\($0)\"}" }
        return "{\"episodes\":[\(rows.joined(separator: ","))]}"
    }

    private static var timeArchiveJSON: String {
        let slots = (0..<12).map { "{\"TimeArchivePart\":\"/radio/timeArchivePart/?ti=\($0)\",\"timeStr\":\"\(String(format: "%02d", $0 * 2)):00\"}" }
        return "{\"dateStr\":\"یکشنبه ۲۴ آبان ۱۴۰۵\",\"items\":[\(slots.joined(separator: ","))]}"
    }

    private static let archivePartJSON = """
    {"dateStr":"یکشنبه ۲۴ آبان ۱۴۰۵","timeStr":"08:00","PlayUrlByTime":"/radio/playbytime/?ti=4",
     "programs":[{"progName":"بخش صبحگاهی","progDesc1":"خبر و موسیقی","progCoverUrl":"","progStart":"06:00","progDuration":"240 دقیقه","PlayUrl":"/radio/playbyepgid/?e=1"},
                 {"progName":"اخبار ساعت ۸","progDesc1":"","progCoverUrl":"","progStart":"08:00","progDuration":"10 دقیقه","PlayUrl":"/radio/playbyepgid/?e=2"},
                 {"progName":"ترافیک صبحگاهی","progDesc1":"","progCoverUrl":"","progStart":"08:10","progDuration":"5 دقیقه","PlayUrl":"/radio/playbyepgid/?e=3"}]}
    """

    private static let homeJSON = """
    {"serialName":"قصه‌های جزیره","imageurl":"","abstract":"مجموعه‌ای شنیدنی از ماجراهای ساکنان یک جزیره‌ی کوچک؛ هر قسمت داستانی تازه.",
     "tabs":[{"title":"قسمت‌ها","feedAddress":"/book/serialepisodes/?p=1","type":"6"},{"title":"مشخصات","feedAddress":"/book/serialabout/?p=1","type":"6"},{"title":"دیوار","feedAddress":"/x","type":"3"}]}
    """
}
