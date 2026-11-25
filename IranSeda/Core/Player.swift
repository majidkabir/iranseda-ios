import AVFoundation
import MediaPlayer
import SwiftUI

/// One audio player for the whole app: queue, background audio, lock-screen
/// controls, resume positions, playback speed, sleep timer.
@MainActor
final class Player: ObservableObject {
    static let shared = Player()
    static let speeds: [Float] = [0.75, 1, 1.25, 1.5, 2]

    @Published private(set) var album: PlayerDetail?
    /// What was opened to start this playback (a book, a station…), for "now playing" marks in lists.
    @Published private(set) var source: SavedItem?
    @Published private(set) var index = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var position: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var sleepAt: Date?
    @Published private(set) var rate: Float = 1
    /// True while the player is waiting for data, so the UI can show a spinner instead of "playing".
    @Published private(set) var isBuffering = false
    /// Set when a file or stream cannot be played; the UI shows it once.
    @Published var failure: String?

    private let av = AVPlayer()
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var itemObservation: NSKeyValueObservation?
    private var observers: [NSObjectProtocol] = []
    private var sleepTask: Task<Void, Never>?
    #if os(iOS)
    private var artwork: MPMediaItemArtwork?
    #endif
    private var lastSaved: Double = 0
    #if os(watchOS)
    /// The watch needs its audio route picked (headphones or speaker) before anything can play.
    private var sessionReady = false
    /// Play through the watch's own speaker instead of Bluetooth headphones.
    static var useWatchSpeaker: Bool {
        get { UserDefaults.standard.bool(forKey: "watch.speaker") }
        set { UserDefaults.standard.set(newValue, forKey: "watch.speaker") }
    }
    #endif

    var track: Track? {
        guard let album, album.items.indices.contains(index) else { return nil }
        return album.items[index]
    }
    var isLive: Bool { album?.isLive ?? false }
    var title: String { track.map { $0.name.isEmpty ? (album?.displayTitle ?? "") : $0.name } ?? "" }
    var subtitle: String {
        guard let album else { return "" }
        return album.displayTitle == title ? album.chTitle : album.displayTitle
    }
    var hasNext: Bool { (album?.items.count ?? 0) > index + 1 }
    var hasPrevious: Bool { index > 0 }
    var progress: Double { duration > 0 ? min(max(position / duration, 0), 1) : 0 }

    private init() {
        let saved = UserDefaults.standard.float(forKey: "player.rate")
        rate = Player.speeds.contains(saved) ? saved : 1
        #if os(watchOS)
        configureWatchSession()
        #else
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        #endif
        timeObserver = av.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 2), queue: .main) { [weak self] time in
            Task { @MainActor in self?.tick(time.seconds) }
        }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.trackEnded() }
        })
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let typeValue = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let optionValue = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            Task { @MainActor in self?.interrupted(typeValue: typeValue, optionValue: optionValue) }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            Task { @MainActor in
                // Headphones unplugged: pause instead of blasting the speaker.
                if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
                    self?.pause()
                    #if os(watchOS)
                    self?.sessionReady = false
                    #endif
                }
            }
        })
        observers.append(center.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: nil, queue: .main) { [weak self] note in
            let message = (note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?.localizedDescription
            Task { @MainActor in self?.itemFailed(message) }
        })
        statusObservation = av.observe(\.timeControlStatus) { [weak self] player, _ in
            let waiting = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
            Task { @MainActor in
                guard let self else { return }
                self.isBuffering = waiting && self.isPlaying
            }
        }
        setUpRemoteCommands()
    }

    private func itemFailed(_ message: String?) {
        guard album != nil else { return }
        isPlaying = false
        isBuffering = false
        failure = isLive ? "پخش زنده این شبکه در دسترس نیست." : "پخش این فایل ممکن نشد."
        if let message, !message.isEmpty { failure = (failure ?? "") + "\n" + message }
        updateNowPlaying()
    }

    // MARK: Playback

    func play(_ detail: PlayerDetail, at first: Int = 0, source: SavedItem? = nil) {
        guard detail.items.indices.contains(first) else { return }
        saveResume()
        position = 0
        album = detail
        self.source = source
        #if os(iOS)
        artwork = nil
        #endif
        loadArtwork(detail.cover)
        if let source { Library.shared.addRecent(source) }
        start(index: first)
    }

    private func start(index newIndex: Int) {
        guard let album, album.items.indices.contains(newIndex) else { return }
        saveResume()
        index = newIndex
        let track = album.items[newIndex]
        duration = (Double(track.duration) ?? 0) / 1000
        position = 0
        guard !Demo.isOn else { isPlaying = true; position = duration * 0.37; return }
        guard let url = DownloadStore.shared.localFile(for: track) ?? API.resolve(track.playUrl) else { return }
        #if os(watchOS)
        guard sessionReady else {
            activateWatchSession { [weak self] in self?.start(index: newIndex) }
            return
        }
        #else
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        let item = AVPlayerItem(url: url)
        itemObservation = item.observe(\.status) { [weak self] item, _ in
            guard item.status == .failed else { return }
            let message = item.error?.localizedDescription
            Task { @MainActor in self?.itemFailed(message) }
        }
        failure = nil
        av.replaceCurrentItem(with: item)
        if !album.isLive, let resume = resumePosition(for: track), resume > 5 {
            av.seek(to: CMTime(seconds: resume, preferredTimescale: 600))
            position = resume
        }
        resume()
    }

    private func resume() {
        #if os(watchOS)
        guard sessionReady || Demo.isOn else {
            activateWatchSession { [weak self] in self?.resume() }
            return
        }
        #endif
        av.play()
        if !isLive { av.rate = rate }
        isPlaying = true
        updateNowPlaying()
    }

    func pause() {
        guard isPlaying else { return }
        av.pause()
        isPlaying = false
        saveResume()
        updateNowPlaying()
    }

    func toggle() {
        guard album != nil else { return }
        if Demo.isOn { isPlaying.toggle(); return }
        guard av.currentItem != nil else { return }
        if isPlaying {
            pause()
        } else if isLive || av.currentItem?.status == .failed {
            // A paused live stream has fallen behind; reconnect to hear what is on air now.
            start(index: index)
        } else {
            resume()
        }
    }

    func next() { if hasNext { start(index: index + 1) } }
    func previous() { if hasPrevious { start(index: index - 1) } }
    func jump(to newIndex: Int) { start(index: newIndex) }

    func seek(to seconds: Double) {
        guard !isLive else { return }
        let target = max(0, duration > 0 ? min(seconds, duration) : seconds)
        av.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        position = target
        updateNowPlaying()
    }

    func skip(_ delta: Double) { seek(to: position + delta) }

    func setRate(_ newRate: Float) {
        rate = newRate
        UserDefaults.standard.set(newRate, forKey: "player.rate")
        if isPlaying, !isLive { av.rate = newRate }
        updateNowPlaying()
    }

    func stop() {
        saveResume()
        av.pause()
        av.replaceCurrentItem(with: nil)
        isPlaying = false
        isBuffering = false
        itemObservation = nil
        album = nil
        source = nil
        sleep(afterMinutes: nil)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func tick(_ seconds: Double) {
        guard seconds.isFinite, album != nil else { return }
        position = seconds
        if let item = av.currentItem, item.duration.seconds.isFinite, item.duration.seconds > 0 {
            duration = item.duration.seconds
        }
        if abs(seconds - lastSaved) > 10 { saveResume() }
    }

    private func trackEnded() {
        if let track { UserDefaults.standard.removeObject(forKey: resumeKey(track)) }
        lastSaved = 0
        position = 0
        if hasNext {
            start(index: index + 1)
        } else {
            if let source, !isLive, !Demo.isOn { UserDefaults.standard.set(1.0, forKey: Self.progressKey(source)) }
            isPlaying = false
            updateNowPlaying()
        }
    }

    private func interrupted(typeValue: UInt?, optionValue: UInt) {
        guard let typeValue, let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        switch type {
        case .began:
            if isPlaying { isPlaying = false; saveResume(); updateNowPlaying() }
        case .ended:
            if AVAudioSession.InterruptionOptions(rawValue: optionValue).contains(.shouldResume), album != nil {
                if isLive { start(index: index) } else { resume() }
            }
        @unknown default:
            break
        }
    }

    // MARK: Sleep timer

    func sleep(afterMinutes minutes: Int?) {
        sleepTask?.cancel()
        guard let minutes else { sleepAt = nil; return }
        sleepAt = Date().addingTimeInterval(Double(minutes) * 60)
        sleepTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(minutes) * 60 * 1_000_000_000)
            guard !Task.isCancelled, let self else { return }
            self.pause()
            self.sleepAt = nil
        }
    }

    // MARK: Resume positions

    private func resumeKey(_ track: Track) -> String {
        "resume." + (track.FileID.isEmpty ? track.playUrl : track.FileID)
    }

    func resumePosition(for track: Track) -> Double? {
        if Demo.isOn { return track.FileID == "demo1" ? (Double(track.duration) ?? 0) / 1000 * 0.4 : nil }
        let v = UserDefaults.standard.double(forKey: resumeKey(track))
        return v > 0 ? v : nil
    }

    private func saveResume() {
        guard let track, !isLive, position > 0, !Demo.isOn else { return }
        UserDefaults.standard.set(position, forKey: resumeKey(track))
        lastSaved = position
        if let source, let album, duration > 0, !album.items.isEmpty {
            let done = (Double(index) + min(position / duration, 1)) / Double(album.items.count)
            UserDefaults.standard.set(done, forKey: Self.progressKey(source))
        }
    }

    private static func progressKey(_ item: SavedItem) -> String { "resume.progress." + item.id }

    /// How much of a book or episode has been heard, 0…1, or nil if never started.
    static func progress(for item: SavedItem) -> Double? {
        guard item.kind == .detail || item.kind == .play else { return nil }
        if Demo.isOn { return item.title.count % 3 == 0 ? nil : Double(item.title.count % 7 + 2) / 10 }
        let v = UserDefaults.standard.double(forKey: progressKey(item))
        return v > 0 ? v : nil
    }

    /// True when this station's live stream is the thing loaded in the player.
    func isOn(channel id: String) -> Bool {
        album != nil && source?.kind == .channel && source?.ref == id
    }

    static func clearResumePositions() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("resume.") {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: Lock screen / Control Centre

    private func setUpRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in if self?.isPlaying == false { self?.toggle() } }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.toggle() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
        center.skipForwardCommand.preferredIntervals = [15]
        center.skipForwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skip(15) }
            return .success
        }
        center.skipBackwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skip(-15) }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let target = event.positionTime
            Task { @MainActor in self?.seek(to: target) }
            return .success
        }
    }

    private func updateNowPlaying() {
        guard album != nil, !Demo.isOn else { return }
        // Lock-screen buttons follow what is possible: no seeking in a live stream.
        let center = MPRemoteCommandCenter.shared()
        center.skipForwardCommand.isEnabled = !isLive
        center.skipBackwardCommand.isEnabled = !isLive
        center.changePlaybackPositionCommand.isEnabled = !isLive
        center.nextTrackCommand.isEnabled = hasNext
        center.previousTrackCommand.isEnabled = hasPrevious
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyAlbumTitle: subtitle,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(isLive ? 1 : rate) : 0.0,
            MPNowPlayingInfoPropertyIsLiveStream: isLive,
        ]
        if !isLive, duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        #if os(iOS)
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        #endif
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    #if os(watchOS)
    /// Long-form audio goes to Bluetooth headphones; the system asks which ones if none are on.
    /// With the speaker setting on, it plays from the watch itself.
    func configureWatchSession() {
        let session = AVAudioSession.sharedInstance()
        if Self.useWatchSpeaker {
            try? session.setCategory(.playback, mode: .spokenAudio)
        } else {
            try? session.setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio)
        }
        sessionReady = false
    }

    private func activateWatchSession(then next: @escaping @MainActor () -> Void) {
        let session = AVAudioSession.sharedInstance()
        if Self.useWatchSpeaker {
            try? session.setActive(true)
            sessionReady = true
            next()
            return
        }
        isBuffering = true
        session.activate(options: []) { [weak self] ok, _ in
            Task { @MainActor in
                guard let self else { return }
                self.isBuffering = false
                if ok {
                    self.sessionReady = true
                    next()
                } else {
                    self.isPlaying = false
                    self.failure = "هدفون یا بلندگوی بلوتوثی انتخاب نشد."
                }
            }
        }
    }
    #endif

    private func loadArtwork(_ link: String) {
        #if os(iOS)
        guard !Demo.isOn, let url = API.resolve(link) else { return }
        Task { [weak self] in
            guard let image = await ImageStore.shared.image(for: url) else { return }
            self?.artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            self?.updateNowPlaying()
        }
        #endif
    }
}

/// Shared ways to start playback from a link.
enum Playback {
    /// Fetches a player detail from a link and plays it.
    @MainActor
    static func play(link: String, source: SavedItem? = nil) async throws {
        let detail = try await API.get(PlayerDetail.self, link)
        guard !detail.items.isEmpty else { throw API.Failure.empty }
        Player.shared.play(detail, source: source)
    }

    /// Plays a favourite or recent item directly, as widget and CarPlay taps do.
    @MainActor
    static func play(saved item: SavedItem) async throws {
        switch item.kind {
        case .channel:
            let list = try await API.get(RadioList.self, API.radioPath)
            guard let channel = list.channels.first(where: { $0.id == item.ref }) else { throw API.Failure.empty }
            try await playLive(channel)
        case .detail, .play:
            try await play(link: item.url, source: item)
        case .home:
            throw API.Failure.empty   // a series has no single thing to play
        }
    }

    /// Starts a station's live stream: on-air info first, then its player link.
    @MainActor
    static func playLive(_ channel: Channel) async throws {
        guard let tab = channel.liveTab else { throw API.Failure.empty }
        let info = try await API.get(LiveInfo.self, tab.feedAddress)
        let source = SavedItem(kind: .channel, url: API.radioPath, ref: channel.id,
                               title: channel.title, subtitle: info.name, image: channel.logo)
        try await play(link: info.PlayURL, source: source)
    }
}
