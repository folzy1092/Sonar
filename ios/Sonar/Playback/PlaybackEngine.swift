import AVFoundation
import Combine
import Foundation
import MediaPlayer
import Observation
import UIKit

/// Плеер (SPEC §4.3): `AVQueuePlayer`, следующий трек подгружается за 15 с до конца — переход без
/// паузы; ссылка на поток берётся у `MusicCore` перед загрузкой; ошибка потока — ещё раз со свежей
/// ссылкой (протухла), потом пропуск с сообщением. Очередь — как Windows `player.svelte.ts`:
/// список треков + порядок (перемешанный или нет) + позиция в порядке.
///
/// Колбэки AVFoundation приходят на главной очереди (Combine `receive(on:)`, наблюдатель времени,
/// уведомления с `queue: .main`) — состояние живёт на главном акторе.
@MainActor
@Observable
final class PlaybackEngine {
    static let shared = PlaybackEngine()

    /// За сколько секунд до конца подгрузить следующий трек.
    static let preloadLead: Double = 15

    private(set) var tracks: [Track] = []
    /// Индексы в `tracks` в порядке воспроизведения.
    private(set) var order: [Int] = []
    private(set) var pos = 0
    /// Откуда играем: «Любимые», «Поиск», название плейлиста.
    private(set) var contextTitle = ""
    private(set) var isPlaying = false
    private(set) var isLoading = false
    /// Секунды.
    private(set) var position: Double = 0
    private(set) var duration: Double = 0
    /// Что реально играет: «AAC 160», «FLAC · Яндекс».
    private(set) var quality: String?
    /// Последняя ошибка — для тоста.
    var message: String?
    var repeatMode: RepeatMode = .off
    private(set) var shuffle = false
    /// Скорость 0.5–2× (тон не меняется — `.timeDomain`).
    private(set) var rate: Float = 1
    /// Треки, дописанные «Авто похожими» (в очереди — отдельным блоком).
    private(set) var autoRefs: Set<String> = []

    var current: Track? {
        order.indices.contains(pos) ? tracks[order[pos]] : nil
    }

    /// Предыдущие · сейчас · далее — для листа очереди.
    var upNext: [Track] {
        order.indices.contains(pos) ? order[(pos + 1)...].map { tracks[$0] } : []
    }

    var history: [Track] {
        order.indices.contains(pos) ? order[..<pos].map { tracks[$0] } : []
    }

    @ObservationIgnored private let player = AVQueuePlayer()
    @ObservationIgnored private var currentItem: AVPlayerItem?
    @ObservationIgnored private var preloaded: (pos: Int, item: AVPlayerItem)?
    @ObservationIgnored private var preloading = false
    @ObservationIgnored private var loadToken = 0
    @ObservationIgnored private var retried = false
    @ObservationIgnored private var itemStatus: AnyCancellable?
    @ObservationIgnored private var timeControl: AnyCancellable?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var sessionActive = false
    @ObservationIgnored private lazy var nowPlaying = NowPlaying(engine: self)
    /// Номер очереди: «Авто похожие» не дописывают в очередь, которую уже заменили.
    @ObservationIgnored private var queueId = 0
    @ObservationIgnored private var autoplayLoading = false
    /// Очередь, для которой похожих не нашлось, — не долбить сервис, пока она не изменится.
    @ObservationIgnored private var deadQueue = ""

    init() {
        player.automaticallyWaitsToMinimizeStalling = true
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time) }
        }
        timeControl = player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.isPlaying = status != .paused
                    self.nowPlaying.update()
                }
            }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main) { [weak self] note in
            // сам элемент через границу актора не передаём — только его идентичность
            let id = (note.object as? AVPlayerItem).map(ObjectIdentifier.init)
            MainActor.assumeIsolated { self?.itemEnded(id) }
        })
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
            let options = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt).map(AVAudioSession.InterruptionOptions.init)
            MainActor.assumeIsolated { self?.interrupted(type, resume: options?.contains(.shouldResume) == true) }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).flatMap(AVAudioSession.RouteChangeReason.init)
            // наушники вынули — пауза, как у всех плееров
            if reason == .oldDeviceUnavailable {
                MainActor.assumeIsolated { self?.pause() }
            }
        })
    }

    // MARK: - Очередь

    /// Играть список с трека index. context — откуда («Поиск», «Любимые»…).
    func play(_ list: [Track], at index: Int, context: String) {
        guard list.indices.contains(index) else { return }
        tracks = list
        contextTitle = context
        queueId += 1
        autoRefs = []
        deadQueue = ""
        order = QueueMath.makeOrder(length: list.count, current: index, shuffle: shuffle)
        pos = shuffle ? 0 : index
        load(autoplay: true)
    }

    func toggle() {
        isPlaying ? pause() : resume()
    }

    func resume() {
        guard current != nil else { return }
        if currentItem == nil {
            load(autoplay: true)
            return
        }
        activateSession()
        player.playImmediately(atRate: rate)
    }

    func pause() {
        player.pause()
    }

    func next() {
        guard let target = QueueMath.nextPos(pos, length: order.count, repeat: repeatMode, manual: true) else { return }
        pos = target
        load(autoplay: true)
    }

    /// Назад: после 3 секунд — в начало трека, раньше — предыдущий.
    func previous() {
        if position > 3 {
            seek(to: 0)
            return
        }
        pos = QueueMath.prevPos(pos, length: order.count, repeat: repeatMode)
        load(autoplay: true)
    }

    func jump(toUpcoming offset: Int) {
        let target = pos + 1 + offset
        guard order.indices.contains(target) else { return }
        pos = target
        load(autoplay: true)
    }

    func seek(to seconds: Double) {
        position = max(0, min(seconds, duration))
        player.seek(to: CMTime(seconds: position, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        nowPlaying.update()
    }

    func toggleShuffle() {
        shuffle.toggle()
        guard order.indices.contains(pos) else { return }
        let index = order[pos]
        order = QueueMath.makeOrder(length: tracks.count, current: index, shuffle: shuffle)
        pos = shuffle ? 0 : index
        dropPreload()
    }

    func cycleRepeat() {
        repeatMode = repeatMode.next
        dropPreload()
    }

    func setRate(_ value: Float) {
        rate = min(2, max(0.5, value))
        player.defaultRate = rate
        if isPlaying { player.rate = rate }
        nowPlaying.update()
    }

    /// «Следующим» / «В очередь».
    func enqueue(_ track: Track, next: Bool) {
        tracks.append(track)
        order = QueueMath.enqueue(order: order, pos: pos, newIndex: tracks.count - 1, next: next)
        if next { dropPreload() }
        if order.count == 1 {
            pos = 0
            load(autoplay: true)
        }
    }

    // MARK: - Загрузка

    private func activateSession() {
        guard !sessionActive else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
        sessionActive = true
    }

    private func makeItem(_ source: StreamSource) -> AVPlayerItem {
        let url: URL
        switch source {
        case let .file(link, _), let .hls(link, _): url = link
        }
        let item = AVPlayerItem(asset: AVURLAsset(url: url))
        item.audioTimePitchAlgorithm = .timeDomain
        // буфер вперёд — чтобы мобильная сеть не рвала звук
        item.preferredForwardBufferDuration = 30
        return item
    }

    private static func label(_ source: StreamSource) -> String {
        switch source {
        case let .file(_, quality), let .hls(_, quality): quality
        }
    }

    /// Загрузить трек на позиции pos. fresh — ссылка протухла, взять новую.
    private func load(autoplay: Bool, fresh: Bool = false) {
        guard let track = current else { return }
        loadToken += 1
        let token = loadToken
        if !fresh { retried = false }
        dropPreload()
        player.pause()
        player.removeAllItems()
        currentItem = nil
        itemStatus = nil
        position = 0
        duration = Double(track.durationMs) / 1000
        quality = nil
        isLoading = true
        // запомненная скорость трека, иначе обычная (SPEC §4.3)
        if !fresh { setRate(LibraryStore.shared.speed(for: track.ref) ?? 1) }
        nowPlaying.update()
        Task {
            do {
                let source = try await MusicCore.shared.stream(track.ref, fresh: fresh)
                guard token == self.loadToken else { return }
                let item = self.makeItem(source)
                self.quality = Self.label(source)
                self.attach(item)
                self.player.insert(item, after: nil)
                if autoplay {
                    self.activateSession()
                    self.player.playImmediately(atRate: self.rate)
                }
                self.isLoading = false
                self.nowPlaying.update(artworkFor: track)
                self.topUpAutoplay()
            } catch {
                guard token == self.loadToken else { return }
                self.isLoading = false
                self.failed(track, error)
            }
        }
    }

    /// Следить за готовностью элемента: не открылся — ещё раз со свежей ссылкой, потом пропуск.
    private func attach(_ item: AVPlayerItem) {
        currentItem = item
        itemStatus = item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak item] status in
                MainActor.assumeIsolated {
                    guard let self, let item, item === self.currentItem else { return }
                    switch status {
                    case .readyToPlay:
                        let seconds = item.duration.seconds
                        if seconds.isFinite, seconds > 0 { self.duration = seconds }
                        self.nowPlaying.update()
                    case .failed:
                        guard let track = self.current else { return }
                        if !self.retried {
                            self.retried = true
                            self.load(autoplay: true, fresh: true)
                        } else {
                            self.failed(track, item.error ?? ServiceError(message: "поток не открылся"))
                        }
                    default:
                        break
                    }
                }
            }
    }

    private func failed(_ track: Track, _ error: Error) {
        message = "Не играет «\(track.title)»: \(error.localizedDescription)"
        // пропустить трек; очередь кончилась — просто стоп
        if let target = QueueMath.nextPos(pos, length: order.count, repeat: repeatMode == .one ? .off : repeatMode, manual: true),
           target != pos {
            pos = target
            load(autoplay: true)
        }
    }

    private func dropPreload() {
        if let preloaded {
            player.remove(preloaded.item)
        }
        preloaded = nil
        preloading = false
    }

    // MARK: - Время и переходы

    private func tick(_ time: CMTime) {
        let seconds = time.seconds
        guard seconds.isFinite, currentItem != nil, player.currentItem === currentItem else { return }
        position = seconds
        if duration > 0, duration - seconds < Self.preloadLead {
            preloadNext()
        }
    }

    /// Подгрузить следующий трек в очередь AVQueuePlayer — переход без паузы.
    private func preloadNext() {
        guard preloaded == nil, !preloading, repeatMode != .one, let currentItem,
              let target = QueueMath.nextPos(pos, length: order.count, repeat: repeatMode, manual: false), target != pos else { return }
        let track = tracks[order[target]]
        let token = loadToken
        preloading = true
        Task {
            defer { if token == self.loadToken { self.preloading = false } }
            guard let source = try? await MusicCore.shared.stream(track.ref),
                  token == self.loadToken, self.currentItem === currentItem, self.preloaded == nil else { return }
            let item = self.makeItem(source)
            self.player.insert(item, after: currentItem)
            self.preloaded = (target, item)
        }
    }

    private func itemEnded(_ id: ObjectIdentifier?) {
        guard let id, let currentItem, ObjectIdentifier(currentItem) == id else { return }
        if repeatMode == .one {
            seek(to: 0)
            player.playImmediately(atRate: rate)
            return
        }
        if let preloaded {
            // AVQueuePlayer уже перешёл на подгруженный трек сам
            self.preloaded = nil
            pos = preloaded.pos
            loadToken += 1
            retried = false
            position = 0
            if let track = current {
                duration = Double(track.durationMs) / 1000
                setRate(LibraryStore.shared.speed(for: track.ref) ?? 1)
                nowPlaying.update(artworkFor: track)
            }
            Task {
                // подпись качества у подгруженного — из кэша ссылок MusicCore
                if let track = self.current, let source = try? await MusicCore.shared.stream(track.ref) {
                    self.quality = Self.label(source)
                }
            }
            attach(preloaded.item)
            topUpAutoplay()
            return
        }
        guard let target = QueueMath.nextPos(pos, length: order.count, repeat: repeatMode, manual: false) else {
            // очередь кончилась
            player.pause()
            seek(to: 0)
            return
        }
        pos = target
        load(autoplay: true)
    }

    /// «Авто похожие»: до конца очереди меньше трёх треков — дописать похожие (повтор трека — не надо).
    private func topUpAutoplay() {
        guard SettingsStore.shared.bool("general.similar_autoplay"), repeatMode != .one, !autoplayLoading,
              order.count - pos - 1 < Autoplay.left else { return }
        let queue = order.map { tracks[$0] }
        let key = "\(queueId):\(queue.count)"
        guard key != deadQueue else { return }
        let seeds = Autoplay.seeds(queue, auto: autoRefs)
        let id = queueId
        autoplayLoading = true
        Task {
            defer { self.autoplayLoading = false }
            var lists: [[Track]] = []
            for seed in seeds {
                if let list = try? await MusicCore.shared.similar(to: seed.ref) { lists.append(list) }
            }
            guard id == self.queueId else { return }
            let fresh = Autoplay.freshSimilar(lists, inQueue: Set(self.tracks.map(\.ref)), disliked: { _ in false }, limit: Autoplay.batch)
            guard !fresh.isEmpty else {
                self.deadQueue = key
                return
            }
            for track in fresh {
                self.tracks.append(track)
                self.order.append(self.tracks.count - 1)
                self.autoRefs.insert(track.ref)
            }
        }
    }

    private func interrupted(_ type: AVAudioSession.InterruptionType?, resume: Bool) {
        switch type {
        case .began?:
            isPlaying = false
        case .ended?:
            if resume { player.playImmediately(atRate: rate) }
        default:
            break
        }
    }
}

/// Экран блокировки и пульт (`MPNowPlayingInfoCenter`, `MPRemoteCommandCenter`).
@MainActor
final class NowPlaying {
    private unowned let engine: PlaybackEngine
    private var artwork: MPMediaItemArtwork?
    private var artworkRef: String?

    init(engine: PlaybackEngine) {
        self.engine = engine
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { [weak engine] _ in
            MainActor.assumeIsolated { engine?.resume() }
            return .success
        }
        commands.pauseCommand.addTarget { [weak engine] _ in
            MainActor.assumeIsolated { engine?.pause() }
            return .success
        }
        commands.togglePlayPauseCommand.addTarget { [weak engine] _ in
            MainActor.assumeIsolated { engine?.toggle() }
            return .success
        }
        commands.nextTrackCommand.addTarget { [weak engine] _ in
            MainActor.assumeIsolated { engine?.next() }
            return .success
        }
        commands.previousTrackCommand.addTarget { [weak engine] _ in
            MainActor.assumeIsolated { engine?.previous() }
            return .success
        }
        commands.changePlaybackPositionCommand.addTarget { [weak engine] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let time = event.positionTime
            MainActor.assumeIsolated { engine?.seek(to: time) }
            return .success
        }
    }

    func update() {
        guard let track = engine.current else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyPlaybackDuration: engine.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: engine.position,
            MPNowPlayingInfoPropertyPlaybackRate: engine.isPlaying ? Double(engine.rate) : 0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: Double(engine.rate),
        ]
        if let album = track.album?.title { info[MPMediaItemPropertyAlbumTitle] = album }
        if artworkRef == track.ref, let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// Обложка для экрана блокировки — качается один раз на трек.
    func update(artworkFor track: Track) {
        update()
        guard artworkRef != track.ref else { return }
        artworkRef = track.ref
        artwork = nil
        guard let url = track.coverURL.flatMap(URL.init(string:)) else { return }
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url), let image = UIImage(data: data),
                  self.artworkRef == track.ref else { return }
            self.artwork = Self.artwork(image)
            self.update()
        }
    }

    /// Вне главного актора: iOS просит картинку с любого потока, а замыкание с главного актора упало бы
    /// на проверке изоляции.
    nonisolated private static func artwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}
