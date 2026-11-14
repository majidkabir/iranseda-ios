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
    @Published private(set) var index = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var position: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var sleepAt: Date?
    @Published private(set) var rate: Float = 1

    private let av = AVPlayer()
    private var timeObserver: Any?
    private var observers: [NSObjectProtocol] = []
    private var sleepTask: Task<Void, Never>?
    private var artwork: MPMediaItemArtwork?
    private var lastSaved: Double = 0

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
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
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
                if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { self?.pause() }
            }
        })
        setUpRemoteCommands()
    }

    // MARK: Playback

    func play(_ detail: PlayerDetail, at first: Int = 0, source: SavedItem? = nil) {
        guard detail.items.indices.contains(first) else { return }
        saveResume()
        position = 0
        album = detail
        artwork = nil
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
        try? AVAudioSession.sharedInstance().setActive(true)
        av.replaceCurrentItem(with: AVPlayerItem(url: url))
        if !album.isLive, let resume = resumePosition(for: track), resume > 5 {
            av.seek(to: CMTime(seconds: resume, preferredTimescale: 600))
            position = resume
        }
        resume()
    }

    private func resume() {
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
        if isPlaying { pause() } else { resume() }
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
        album = nil
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
        if hasNext { start(index: index + 1) } else { isPlaying = false; updateNowPlaying() }
    }

    private func interrupted(typeValue: UInt?, optionValue: UInt) {
        guard let typeValue, let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        switch type {
        case .began:
            if isPlaying { isPlaying = false; saveResume(); updateNowPlaying() }
        case .ended:
            if AVAudioSession.InterruptionOptions(rawValue: optionValue).contains(.shouldResume), album != nil {
                resume()
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
        let v = UserDefaults.standard.double(forKey: resumeKey(track))
        return v > 0 ? v : nil
    }

    private func saveResume() {
        guard let track, !isLive, position > 0, !Demo.isOn else { return }
        UserDefaults.standard.set(position, forKey: resumeKey(track))
        lastSaved = position
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
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyAlbumTitle: subtitle,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(isLive ? 1 : rate) : 0.0,
            MPNowPlayingInfoPropertyIsLiveStream: isLive,
        ]
        if !isLive, duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func loadArtwork(_ link: String) {
        guard !Demo.isOn, let url = API.resolve(link) else { return }
        Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: data) else { return }
            self?.artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            self?.updateNowPlaying()
        }
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
