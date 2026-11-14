import AVFoundation
import MediaPlayer
import SwiftUI

/// One audio player for the whole app: queue, background audio, lock-screen
/// controls, resume positions, sleep timer.
@MainActor
final class Player: ObservableObject {
    static let shared = Player()

    @Published private(set) var album: PlayerDetail?
    @Published private(set) var index = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var position: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var sleepAt: Date?

    private let av = AVPlayer()
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var sleepTask: Task<Void, Never>?
    private var artwork: MPMediaItemArtwork?
    private var lastSaved: Double = 0

    var track: Track? {
        guard let album, album.items.indices.contains(index) else { return nil }
        return album.items[index]
    }
    var isLive: Bool { album?.isLive ?? false }
    var title: String { track.map { $0.name.isEmpty ? (album?.displayTitle ?? "") : $0.name } ?? "" }
    var subtitle: String { album?.displayTitle ?? "" }
    var hasNext: Bool { (album?.items.count ?? 0) > index + 1 }
    var hasPrevious: Bool { index > 0 }

    private init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        timeObserver = av.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 2), queue: .main) { [weak self] time in
            Task { @MainActor in self?.tick(time.seconds) }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.trackEnded() }
        }
        setUpRemoteCommands()
    }

    // MARK: Playback

    func play(_ detail: PlayerDetail, at start: Int = 0) {
        guard detail.items.indices.contains(start) else { return }
        saveResume()
        position = 0
        album = detail
        artwork = nil
        loadArtwork(detail.cover)
        start(index: start)
    }

    private func start(index newIndex: Int) {
        guard let album, album.items.indices.contains(newIndex) else { return }
        saveResume()
        index = newIndex
        let track = album.items[newIndex]
        let url = DownloadStore.shared.localFile(for: track) ?? API.resolve(track.playUrl)
        guard let url else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        av.replaceCurrentItem(with: AVPlayerItem(url: url))
        position = 0
        duration = (Double(track.duration) ?? 0) / 1000
        if !album.isLive, let resume = resumePosition(for: track), resume > 5 {
            av.seek(to: CMTime(seconds: resume, preferredTimescale: 600))
            position = resume
        }
        av.play()
        isPlaying = true
        updateNowPlaying()
    }

    func toggle() {
        guard av.currentItem != nil else { return }
        if isPlaying { av.pause() } else { av.play() }
        isPlaying.toggle()
        saveResume()
        updateNowPlaying()
    }

    func next() { if hasNext { start(index: index + 1) } }
    func previous() { if hasPrevious { start(index: index - 1) } }

    func seek(to seconds: Double) {
        guard !isLive else { return }
        let target = max(0, duration > 0 ? min(seconds, duration) : seconds)
        av.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        position = target
        updateNowPlaying()
    }

    func skip(_ delta: Double) { seek(to: position + delta) }

    func stop() {
        saveResume()
        av.pause()
        av.replaceCurrentItem(with: nil)
        isPlaying = false
        album = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func tick(_ seconds: Double) {
        guard seconds.isFinite else { return }
        position = seconds
        if let item = av.currentItem, item.duration.seconds.isFinite, item.duration.seconds > 0 {
            duration = item.duration.seconds
        }
        if abs(seconds - lastSaved) > 10 { saveResume() }
    }

    private func trackEnded() {
        if let track { UserDefaults.standard.removeObject(forKey: resumeKey(track)) }
        lastSaved = 0
        if hasNext { start(index: index + 1) } else { isPlaying = false; updateNowPlaying() }
    }

    // MARK: Sleep timer

    func sleep(afterMinutes minutes: Int?) {
        sleepTask?.cancel()
        guard let minutes else { sleepAt = nil; return }
        sleepAt = Date().addingTimeInterval(Double(minutes) * 60)
        sleepTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(minutes) * 60 * 1_000_000_000)
            guard !Task.isCancelled, let self else { return }
            if self.isPlaying { self.toggle() }
            self.sleepAt = nil
        }
    }

    // MARK: Resume positions (the app's "bookmark" for long files)

    private func resumeKey(_ track: Track) -> String {
        "resume." + (track.FileID.isEmpty ? track.playUrl : track.FileID)
    }

    private func resumePosition(for track: Track) -> Double? {
        let v = UserDefaults.standard.double(forKey: resumeKey(track))
        return v > 0 ? v : nil
    }

    private func saveResume() {
        guard let track, !isLive, position > 0 else { return }
        UserDefaults.standard.set(position, forKey: resumeKey(track))
        lastSaved = position
    }

    // MARK: Lock screen / Control Centre

    private func setUpRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in if self?.isPlaying == false { self?.toggle() } }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in if self?.isPlaying == true { self?.toggle() } }
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
            Task { @MainActor in self?.seek(to: event.positionTime) }
            return .success
        }
    }

    private func updateNowPlaying() {
        guard album != nil else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyAlbumTitle: subtitle,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyIsLiveStream: isLive,
        ]
        if !isLive, duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func loadArtwork(_ link: String) {
        guard let url = API.resolve(link) else { return }
        Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: data) else { return }
            self?.artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            self?.updateNowPlaying()
        }
    }
}
