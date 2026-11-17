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
/// Скачанный трек (`DownloadStore`) играет из файла, без сети. История и сигналы волны — `PlayHistory`:
/// прослушивание засчитывается на пороге min(30 с, половины трека), при смене трека — дослушан / пропущен.
/// «Моя волна» и «Волна по треку» — `MyWave`, догружается вместо «Авто похожих».
///
/// Настройки раздела «Плеер» применяются на лету (`observeSettings`): эквалайзер и выравниватель —
/// `AudioTap` (только файлы, не HLS), нормализация по R128 Яндекса — громкость плеера (`Loudness`, и на HLS),
/// бесшовность (`audio.gapless` — следующий подгружается в ту же очередь AVQueuePlayer), кроссфейд
/// (`audio.crossfade` — две деки, как на ПК: следующий подгружается во вторую и за N секунд до конца
/// начинает играть поверх, громкости — равной мощностью), звонки (`audio.on_interruption`), «Добавлять
/// следующие» (`queue.add_following`), «Продолжить с прошлого раза» (`general.restore` — `PlaybackSnapshot`).
/// Таймер сна (`SleepTimer`) — плавное затухание и пауза. Волна без сети (`storage.wave_offline`) — `WaveCache`.
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
    /// Сейчас играет «Моя волна» или «Волна по треку» — для кнопки ▶/⏸ на Главной.
    private(set) var isWave = false
    /// Волна подбирает первую порцию.
    private(set) var waveLoading = false
    /// «Волна по треку»: от какого трека (nil — «Моя волна»).
    private(set) var waveSeed: Track?
    /// Режим волны (настройка `wave.mode`).
    private(set) var waveMode: WaveMode = .own
    /// Текущий трек идёт потоком HLS — эквалайзер и нормализация на нём не звучат (AVFoundation).
    private(set) var isHLS = false
    /// Таймер сна (nil — выключен).
    private(set) var sleep: SleepTimer?
    /// «Почему этот трек» у треков волны: ref → строка.
    private(set) var waveReasons: [String: String] = [:]

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

    /// Две деки, как на ПК: играет `player`, во второй ждёт следующий трек для кроссфейда (или затихает
    /// ушедший). Без кроссфейда вторая не используется — следующий стоит в очереди той же деки (бесшовно).
    @ObservationIgnored private let decks = [AVQueuePlayer(), AVQueuePlayer()]
    @ObservationIgnored private var active = 0
    private var player: AVQueuePlayer { decks[active] }
    private var standby: AVQueuePlayer { decks[1 - active] }
    @ObservationIgnored private var currentItem: AVPlayerItem?
    /// Подгруженный следующий: где он (в очереди текущей деки или во второй деке) и что играет.
    private struct Preloaded {
        var pos: Int
        var item: AVPlayerItem
        var onStandby: Bool
        var quality: String
        var hls: Bool
    }
    @ObservationIgnored private var preloaded: Preloaded?
    @ObservationIgnored private var preloading = false
    /// Кроссфейд идёт: уходящая дека затихает, текущая нарастает.
    @ObservationIgnored private var outgoing: (deck: AVQueuePlayer, start: Date, span: Double, gain: Double)?
    @ObservationIgnored private var fadeIn: (start: Date, span: Double)?
    @ObservationIgnored private var loadToken = 0
    @ObservationIgnored private var retried = false
    /// Третья попытка: поток не открылся и со свежей ссылкой — берём попроще (mp3 вместо FLAC, SC без двойника).
    @ObservationIgnored private var safeRetried = false
    @ObservationIgnored private var safeNext = false
    @ObservationIgnored private var itemStatus: AnyCancellable?
    @ObservationIgnored private var timeControls: [AnyCancellable] = []
    @ObservationIgnored private var timeObservers: [Any] = []
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var sessionActive = false
    @ObservationIgnored private lazy var nowPlaying = NowPlaying(engine: self)
    /// Номер очереди: «Авто похожие» не дописывают в очередь, которую уже заменили.
    @ObservationIgnored private var queueId = 0
    @ObservationIgnored private var autoplayLoading = false
    /// Очередь, для которой похожих не нашлось, — не долбить сервис, пока она не изменится.
    @ObservationIgnored private var deadQueue = ""
    @ObservationIgnored private lazy var wave = MyWave(source: MusicCore.shared, library: .shared, history: .shared)
    @ObservationIgnored private var waveMoreLoading = false
    /// Сколько реально прослушано у текущего трека (мс) — для истории и сигналов волны.
    @ObservationIgnored private var listenedMs: Double = 0
    @ObservationIgnored private var lastTick: Double?
    /// Текущий трек уже записан в историю.
    @ObservationIgnored private var counted = false
    /// Подгруженный следующий: ждём готовности, чтобы подключить эквалайзер заранее.
    @ObservationIgnored private var preloadStatus: AnyCancellable?
    /// Кроссфейд, секунды (0 — выкл), бесшовность и нормализация — из настроек.
    @ObservationIgnored private var crossfade: Double = 0
    @ObservationIgnored private var gapless = true
    @ObservationIgnored private var normalize = true
    @ObservationIgnored private var waveOffline: Bool?
    /// Возвращение после звонка: с какого момента нарастает громкость.
    @ObservationIgnored private var rampStart: Date?
    @ObservationIgnored private var fadeTask: Task<Void, Never>?
    /// До звонка играло — после звонка можно вернуть.
    @ObservationIgnored private var playingBeforeInterruption = false
    /// Восстановленный трек (ref) начнётся с этой секунды; другой трек — с начала.
    @ObservationIgnored private var pendingStart: (ref: String, seconds: Double)?
    @ObservationIgnored private let snapshotFile = PlaybackSnapshotFile()
    @ObservationIgnored private var lastSnapshot = Date.distantPast
    /// Последние применённые качество и «SoundCloud через Яндекс» — чтобы не дёргать MusicCore зря.
    @ObservationIgnored private var appliedQuality: (kbps: Int, viaYandex: Bool)?

    init() {
        waveMode = WaveMode(rawValue: SettingsStore.shared.string("wave.mode")) ?? .own
        restore()
        observeSettings()
        for (index, deck) in decks.enumerated() {
            deck.automaticallyWaitsToMinimizeStalling = true
            timeObservers.append(deck.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] time in
                MainActor.assumeIsolated { self?.tick(time, deck: index) }
            })
            // состояние «играет» — только у текущей деки (уходящая на паузе ничего не значит)
            timeControls.append(deck.publisher(for: \.timeControlStatus)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] status in
                    MainActor.assumeIsolated {
                        guard let self, index == self.active else { return }
                        self.isPlaying = status != .paused
                        self.nowPlaying.update()
                        self.updateFades()
                        if status == .paused { self.saveSnapshot(force: true) }
                    }
                })
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
        // ушли в фон — запомнить, где остановились (iOS может выгрузить приложение)
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveSnapshot(force: true) }
        })
    }

    // MARK: - Очередь

    /// Играть список с трека index. context — откуда («Поиск», «Любимые»…). tapped — нажали на трек в
    /// списке: с выключенным «Добавлять следующие» (`queue.add_following`) играет только он (дальше —
    /// «Авто похожие», если включены). Кнопки «Слушать» / «Перемешать» зовут без tapped — весь список.
    func play(_ list: [Track], at index: Int, context: String, tapped: Bool = false) {
        guard list.indices.contains(index) else { return }
        if tapped, list.count > 1, !SettingsStore.shared.bool("queue.add_following") {
            play([list[index]], at: 0, context: context)
            return
        }
        // новая очередь — прошлая волна (если была) закончилась, её сессии исход уже не нужен
        finishPlay(skipped: true, toWave: false)
        isWave = false
        waveSeed = nil
        waveReasons = [:]
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
        if let sleep, sleep.isDue(now: Date()) { self.sleep = nil }
        activateSession()
        player.playImmediately(atRate: rate)
    }

    /// Пауза; идёт кроссфейд — уходящий трек замолкает сразу.
    func pause() {
        stopOutgoing()
        player.pause()
    }

    func next() {
        guard let target = QueueMath.nextPos(pos, length: order.count, repeat: repeatMode, manual: true) else { return }
        finishPlay(skipped: true)
        pos = target
        load(autoplay: true)
    }

    /// Назад: после 3 секунд — в начало трека, раньше — предыдущий.
    func previous() {
        if position > 3 {
            seek(to: 0)
            return
        }
        finishPlay(skipped: true)
        pos = QueueMath.prevPos(pos, length: order.count, repeat: repeatMode)
        load(autoplay: true)
    }

    func jump(toUpcoming offset: Int) {
        let target = pos + 1 + offset
        guard order.indices.contains(target) else { return }
        finishPlay(skipped: true)
        pos = target
        load(autoplay: true)
    }

    func seek(to seconds: Double) {
        position = max(0, min(seconds, duration))
        // восстановленный трек ещё не загружен — начнётся с этой секунды
        if currentItem == nil, let track = current { pendingStart = (track.ref, position) }
        stopOutgoing()
        fadeIn = nil
        player.seek(to: CMTime(seconds: position, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        nowPlaying.update()
        updateFades()
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
        saveSnapshot(force: true)
    }

    /// Убрать трек «Далее» (offset 0 — ближайший) — жест «Удалить» в очереди.
    func removeUpcoming(_ offset: Int) {
        let next = QueueMath.removeUpcoming(order: order, pos: pos, offset: offset)
        guard next != order else { return }
        dropPreload()
        order = next
        saveSnapshot(force: true)
    }

    /// Трек «Далее» — сразу следующим или в конец очереди (жесты в очереди).
    func moveUpcoming(_ offset: Int, toEnd: Bool) {
        let next = QueueMath.moveUpcoming(order: order, pos: pos, offset: offset, toEnd: toEnd)
        guard next != order else { return }
        dropPreload()
        order = next
        saveSnapshot(force: true)
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

    /// Скачанный (или из офлайн-кэша волны) — из файла, без сети; fresh (файл не открылся или ссылка
    /// протухла) — из сети.
    private static func source(for track: Track, fresh: Bool, safe: Bool = false) async throws -> StreamSource {
        if !fresh, !safe, let local = DownloadStore.shared.localURL(track.ref) {
            return .file(url: local, quality: DownloadStore.shared.quality(track.ref) ?? "Скачан")
        }
        if !fresh, !safe, let cached = WaveCache.shared.localURL(track.ref) {
            return .file(url: cached, quality: WaveCache.shared.quality(track.ref) ?? "Офлайн")
        }
        return try await MusicCore.shared.stream(track.ref, fresh: fresh, safe: safe)
    }

    /// Трек есть на телефоне — сыграет без сети.
    private static func isLocal(_ ref: String) -> Bool {
        DownloadStore.shared.localURL(ref) != nil || WaveCache.shared.localURL(ref) != nil
    }

    private static func streamsHLS(_ source: StreamSource) -> Bool {
        if case .hls = source { return true }
        return false
    }

    private static func label(_ source: StreamSource) -> String {
        switch source {
        case let .file(_, quality), let .hls(_, quality): quality
        }
    }

    /// Загрузить трек на позиции pos. fresh — ссылка протухла, взять новую.
    private func load(autoplay: Bool, fresh: Bool = false) {
        guard let wanted = current else { return }
        // волна без сети: этого трека на телефоне нет — сразу к ближайшему подкачанному
        if isWave, !fresh, !WaveCache.shared.isOnline, !Self.isLocal(wanted.ref),
           let target = WaveCachePlan.nextPlayable(from: pos, refs: order.map { tracks[$0].ref }, isLocal: { Self.isLocal($0) }) {
            pos = target
        }
        guard let track = current else { return }
        loadToken += 1
        let token = loadToken
        if !fresh {
            retried = false
            safeRetried = false
            resetListening()
        }
        let safe = safeNext
        safeNext = false
        // откуда начать: свежая ссылка — с того же места, восстановленный трек — с запомненной секунды
        let start = fresh ? position : (pendingStart?.ref == track.ref ? pendingStart?.seconds ?? 0 : 0)
        pendingStart = nil
        dropPreload()
        stopOutgoing()
        fadeIn = nil
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
                let source = try await Self.source(for: track, fresh: fresh, safe: safe)
                guard token == self.loadToken else { return }
                let item = self.makeItem(source)
                self.quality = Self.label(source)
                self.isHLS = Self.streamsHLS(source)
                self.attach(item)
                self.player.insert(item, after: nil)
                if start > 1 {
                    self.position = start
                    self.player.seek(to: CMTime(seconds: start, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { _ in }
                }
                self.updateFades()
                self.saveSnapshot(force: true)
                if autoplay {
                    self.activateSession()
                    self.player.playImmediately(atRate: self.rate)
                }
                self.isLoading = false
                self.nowPlaying.update(artworkFor: track)
                self.topUpAutoplay()
                self.refreshWaveCache()
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
                        // эквалайзер и выравниватель — у файла (HLS их не пропускает)
                        if !self.isHLS { AudioTap.attach(to: item, leveler: self.current?.loudness == nil) }
                        self.nowPlaying.update()
                    case .failed:
                        guard let track = self.current else { return }
                        if !self.retried {
                            self.retried = true
                            self.load(autoplay: true, fresh: true)
                        } else if !self.safeRetried {
                            self.safeRetried = true
                            self.safeNext = true
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
            if preloaded.onStandby { standby.removeAllItems() } else { player.remove(preloaded.item) }
        }
        preloaded = nil
        preloading = false
        preloadStatus = nil
    }

    // MARK: - Время и переходы

    private func tick(_ time: CMTime, deck: Int) {
        let seconds = time.seconds
        guard deck == active, seconds.isFinite, currentItem != nil, player.currentItem === currentItem else { return }
        listened(at: seconds)
        position = seconds
        saveSnapshot()
        guard duration > 0 else { return }
        if duration - seconds < max(Self.preloadLead, crossfade + 10) {
            preloadNext()
        }
        // кроссфейд: следующий готов во второй деке — за N секунд (реальных, со скоростью) до конца он
        // начинает играть поверх
        if crossfade > 0, outgoing == nil, sleep?.isEndOfTrack != true, let preloaded, preloaded.onStandby,
           preloaded.item.status == .readyToPlay, order.indices.contains(preloaded.pos) {
            let next = tracks[order[preloaded.pos]]
            let span = Fades.overlapSpan(seconds: crossfade, outgoing: duration, incoming: Double(next.durationMs) / 1000)
            if span > 0, (duration - seconds) / Double(max(rate, 0.5)) <= span {
                startCrossfade(span: span)
            }
        }
    }

    /// Подгрузить следующий трек. Без кроссфейда — в очередь той же деки (AVQueuePlayer перейдёт без
    /// паузы); с кроссфейдом — во вторую деку, на паузе и без звука (буферизуется заранее). «Бесшовное»
    /// выключено (и нет кроссфейда) — следующий грузится, когда текущий кончился, с короткой паузой.
    /// Таймер сна «конец трека» — следующий не подгружается.
    private func preloadNext() {
        guard gapless || crossfade > 0, preloaded == nil, !preloading, outgoing == nil, repeatMode != .one,
              sleep?.isEndOfTrack != true, let currentItem,
              let target = QueueMath.nextPos(pos, length: order.count, repeat: repeatMode, manual: false), target != pos else { return }
        let track = tracks[order[target]]
        let token = loadToken
        let overlap = crossfade > 0
        preloading = true
        Task {
            defer { if token == self.loadToken { self.preloading = false } }
            guard let source = try? await Self.source(for: track, fresh: false),
                  token == self.loadToken, self.currentItem === currentItem, self.preloaded == nil, self.outgoing == nil else { return }
            let item = self.makeItem(source)
            if overlap {
                let deck = self.standby
                deck.pause()
                deck.removeAllItems()
                deck.volume = 0
                deck.insert(item, after: nil)
            } else {
                self.player.insert(item, after: currentItem)
            }
            let hls = Self.streamsHLS(source)
            self.preloaded = Preloaded(pos: target, item: item, onStandby: overlap, quality: Self.label(source), hls: hls)
            if !hls {
                let leveler = track.loudness == nil
                self.preloadStatus = item.publisher(for: \.status)
                    .receive(on: DispatchQueue.main)
                    .sink { [weak item] status in
                        MainActor.assumeIsolated {
                            if status == .readyToPlay, let item { AudioTap.attach(to: item, leveler: leveler) }
                        }
                    }
            }
        }
    }

    /// Кроссфейд: ушедшая дека затихает за span секунд, подгруженный во второй деке начинает играть и
    /// нарастает. Для истории и волны ушедший трек — дослушан.
    private func startCrossfade(span: Double) {
        guard let next = preloaded, next.onStandby else { return }
        let old = player
        let oldGain = trackGain()
        finishPlay(skipped: false)
        preloaded = nil
        preloadStatus = nil
        active = 1 - active
        outgoing = (old, Date(), span, oldGain)
        fadeIn = (Date(), span)
        advance(to: next)
        player.volume = 0
        activateSession()
        player.playImmediately(atRate: rate)
        isPlaying = true
        updateFades()
    }

    /// Текущий трек сменился сам на подгруженный: позиция, история, подписи. Сам звук уже идёт (AVQueuePlayer
    /// перешёл или вторая дека включилась).
    private func advance(to next: Preloaded) {
        pos = next.pos
        loadToken += 1
        retried = false
        safeRetried = false
        resetListening()
        position = 0
        quality = next.quality
        isHLS = next.hls
        if let track = current {
            duration = Double(track.durationMs) / 1000
            setRate(LibraryStore.shared.speed(for: track.ref) ?? 1)
            nowPlaying.update(artworkFor: track)
        }
        attach(next.item)
        saveSnapshot(force: true)
        topUpAutoplay()
        refreshWaveCache()
    }

    /// Уходящая дека замолкает и освобождается.
    private func stopOutgoing() {
        guard let outgoing else { return }
        outgoing.deck.pause()
        outgoing.deck.removeAllItems()
        outgoing.deck.volume = 0
        self.outgoing = nil
    }

    private func itemEnded(_ id: ObjectIdentifier?) {
        guard let id, let currentItem, ObjectIdentifier(currentItem) == id else { return }
        finishPlay(skipped: false)
        if repeatMode == .one {
            seek(to: 0)
            player.playImmediately(atRate: rate)
            return
        }
        // таймер сна «конец трека»: следующий — на паузе
        if sleep?.isEndOfTrack == true {
            sleep = nil
            dropPreload()
            if let target = QueueMath.nextPos(pos, length: order.count, repeat: repeatMode, manual: false) {
                pos = target
                load(autoplay: false)
            } else {
                player.pause()
                seek(to: 0)
            }
            return
        }
        if let next = preloaded {
            preloaded = nil
            preloadStatus = nil
            if next.onStandby {
                // кроссфейд не успел (следующий не был готов) — вторая дека включается сразу, без наложения
                active = 1 - active
                fadeIn = nil
                advance(to: next)
                activateSession()
                player.playImmediately(atRate: rate)
                isPlaying = true
            } else {
                // AVQueuePlayer уже перешёл на подгруженный трек сам
                advance(to: next)
            }
            updateFades()
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
        if isWave {
            topUpWave()
            return
        }
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
            let fresh = Autoplay.freshSimilar(lists, inQueue: Set(self.tracks.map(\.ref)), disliked: { LibraryStore.shared.isDisliked($0) }, limit: Autoplay.batch)
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

    // MARK: - История и сигналы

    private func resetListening() {
        listenedMs = 0
        lastTick = nil
        counted = false
        // Last.fm: новое прослушивание («сейчас играет», скроббл по половине / 4 мин)
        if let track = current { LastfmScrobbler.shared.trackStarted(track) }
    }

    /// Копим реально прослушанное (перемотка не считается) и засчитываем прослушивание на пороге
    /// min(30 с, половины трека) — как Windows `plays`.
    private func listened(at seconds: Double) {
        defer { lastTick = seconds }
        guard isPlaying, let last = lastTick else { return }
        let delta = seconds - last
        guard delta > 0, delta < 2 else { return }
        listenedMs += delta * 1000
        LastfmScrobbler.shared.progress(listenedMs: Int(listenedMs))
        if !counted, let track = current,
           QueueMath.countsAsPlay(listenedMs: Int(listenedMs), durationMs: track.durationMs > 0 ? track.durationMs : Int(duration * 1000)) {
            counted = true
            PlayHistory.shared.record(track)
        }
    }

    /// Трек сменился: дослушан / пропущен — в историю, исход — волне. Вызывать до смены позиции.
    private func finishPlay(skipped: Bool, toWave: Bool = true) {
        guard let track = current, listenedMs > 0 else { return }
        let library = LibraryStore.shared
        let reward = PlayHistory.shared.ended(track, listenedMs: Int(listenedMs), manualSkip: skipped,
                                              liked: library.isLiked(track), disliked: library.isDisliked(track.ref))
        resetListening()
        guard isWave, toWave else { return }
        if wave.ended(track, reward: reward, manualSkip: skipped) {
            // два ранних пропуска подряд — «Далее» подобрано не то; позицию плеер сменит сразу после
            // этого вызова, поэтому пересборка — следующим шагом главной очереди
            Task { self.rebuildWave() }
        }
    }

    // MARK: - Волна

    /// «Моя волна»: сиды из Любимых и недавнего, похожие SoundCloud и Яндекса, учится на лайках и
    /// пропусках, без 👎, бесконечно догружается. Уже играет — пауза / продолжить.
    func playMyWave() {
        if isWave, waveSeed == nil, current != nil {
            toggle()
            return
        }
        startWave(seed: nil)
    }

    /// «Волна по треку»: он первым, дальше — похожие на него (стиль держится всю сессию).
    func playWave(from track: Track) {
        startWave(seed: track)
    }

    /// Сменить режим волны и запомнить; если волна играет — перезапустить её в новом режиме (волна по
    /// треку остаётся по тому же треку).
    func setWaveMode(_ mode: WaveMode) {
        guard mode != waveMode else { return }
        waveMode = mode
        SettingsStore.shared.set("wave.mode", .string(mode.rawValue))
        if isWave { startWave(seed: waveSeed) }
    }

    private func startWave(seed: Track?) {
        guard !waveLoading else { return }
        waveLoading = true
        Task {
            defer { self.waveLoading = false }
            do {
                let list = try await self.wave.start(seed: seed, mode: self.waveMode)
                if self.shuffle { self.shuffle = false }
                self.play(list, at: 0, context: seed.map { "Волна по «\($0.title)»" } ?? "Моя волна")
                self.isWave = true
                self.waveSeed = seed
                self.waveReasons = self.wave.reasons
                self.refreshWaveCache()
            } catch {
                self.message = error.localizedDescription
            }
        }
    }

    /// Волна: до конца очереди меньше трёх — следующая порция.
    private func topUpWave() {
        guard !waveMoreLoading, order.count - pos - 1 < Autoplay.left else { return }
        let id = queueId
        waveMoreLoading = true
        Task {
            defer { self.waveMoreLoading = false }
            guard let fresh = try? await self.wave.more() else { return }
            guard id == self.queueId, self.isWave else {
                // очередь пересобрана, пока шёл запрос, — порция подобрана под старое: вернуть в пул
                // и (если волна ещё играет) попросить заново
                self.wave.unserve(fresh)
                if self.isWave { Task { self.topUpWave() } }
                return
            }
            for track in fresh {
                self.tracks.append(track)
                self.order.append(self.tracks.count - 1)
            }
            self.waveReasons = self.wave.reasons
            self.refreshWaveCache()
        }
    }

    /// Серия ранних пропусков: убрать ещё не игравшие треки волны, кроме ближайшего, и подобрать заново.
    private func rebuildWave() {
        guard isWave, order.indices.contains(pos) else { return }
        let keep = min(order.count, pos + 2)
        let gone = order[keep...].map { tracks[$0] }
        guard !gone.isEmpty else { return }
        if let preloaded, preloaded.pos >= keep { dropPreload() }
        order.removeSubrange(keep...)
        wave.unserve(gone)
        queueId += 1
        topUpWave()
    }

    /// 👎 «Не интересно»: больше не попадёт в подборки, волну и «Авто похожие»; если играет — сразу
    /// следующий. Повторно — вернуть.
    func dislike(_ track: Track) {
        LibraryStore.shared.toggleDislike(track)
        guard LibraryStore.shared.isDisliked(track.ref), current?.ref == track.ref else { return }
        next()
    }

    /// Звонок, Siri, будильник: система уже поставила паузу. После — по `audio.on_interruption`: вернуть
    /// плавно (с 20 % громкости), сразу или оставить на паузе. Возвращаем, только если до звонка играло и
    /// система разрешила (`shouldResume`; не разрешает, если пользователь включил другую музыку).
    private func interrupted(_ type: AVAudioSession.InterruptionType?, resume: Bool) {
        switch type {
        case .began?:
            playingBeforeInterruption = isPlaying || playingBeforeInterruption
            isPlaying = false
        case .ended?:
            defer { playingBeforeInterruption = false }
            guard resume, playingBeforeInterruption else { return }
            switch InterruptionMode.current(SettingsStore.shared) {
            case .pause:
                return
            case .duck:
                rampStart = Date()
            case .none:
                rampStart = nil
            }
            player.playImmediately(atRate: rate)
            updateFades()
        default:
            break
        }
    }

    // MARK: - Настройки, громкость переходов, снимок

    /// Следить за настройками: любая правка (экран, синк) — применить сразу.
    private func observeSettings() {
        withObservationTracking {
            applySettings()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeSettings() }
        }
    }

    private func applySettings() {
        let settings = SettingsStore.shared
        AudioTap.params.update(gains: Equalizer.parse(settings.string(Equalizer.gainsKey)),
                               eqEnabled: settings.bool(Equalizer.enabledKey),
                               normalize: settings.bool("audio.normalize"))
        let wasCrossfade = crossfade
        let wasNormalize = normalize
        crossfade = Double(PlayerPrefs.crossfade(settings))
        gapless = settings.bool("audio.gapless")
        normalize = settings.bool("audio.normalize")
        // подгруженный лежит не там, где нужен новому режиму (очередь деки ⇄ вторая дека) — подгрузить заново
        if let preloaded, preloaded.onStandby != (crossfade > 0) || (!gapless && crossfade == 0) { dropPreload() }
        // громкость — вне слежения за настройками (иначе оно подписалось бы на позицию и очередь)
        if wasCrossfade != crossfade || wasNormalize != normalize { Task { self.updateFades() } }
        let offline = settings.bool("storage.wave_offline")
        if offline != waveOffline {
            waveOffline = offline
            Task { self.refreshWaveCache() }
        }
        let kbps = MusicCore.qualityKbps(AudioQuality.current(settings).rawValue)
        let viaYandex = settings.bool("audio.sc_via_yandex")
        if appliedQuality?.kbps != kbps || appliedQuality?.viaYandex != viaYandex {
            appliedQuality = (kbps, viaYandex)
            Task { await MusicCore.shared.configure(maxKbps: kbps, soundCloudViaYandex: viaYandex) }
        }
    }

    /// Громкость дек: нормализация (R128), кроссфейд (уходящая затихает, текущая нарастает), возвращение
    /// после звонка, таймер сна. Пока что-то меняется — обновляется 20 раз в секунду, иначе стоит на месте.
    private func updateFades() {
        applyVolumes()
        guard isPlaying, rampStart != nil || fadeIn != nil || outgoing != nil || sleep != nil else {
            fadeTask?.cancel()
            fadeTask = nil
            return
        }
        guard fadeTask == nil else { return }
        fadeTask = Task { [weak self] in
            while !Task.isCancelled {
                // далеко до затухания (таймер сна на час) — раз в полсекунды, а не 20 раз
                let busy = self?.fadeBusy ?? false
                try? await Task.sleep(for: .milliseconds(busy ? 50 : 500))
                guard let self, !Task.isCancelled else { return }
                self.applyVolumes()
                self.checkSleep()
                if !self.isPlaying || (self.rampStart == nil && self.fadeIn == nil && self.outgoing == nil && self.sleep == nil) {
                    self.fadeTask = nil
                    return
                }
            }
        }
    }

    /// Громкость меняется прямо сейчас (или вот-вот начнёт).
    private var fadeBusy: Bool {
        if rampStart != nil || fadeIn != nil || outgoing != nil { return true }
        guard let sleep else { return false }
        switch sleep.mode {
        case let .deadline(date): return date.timeIntervalSinceNow < SleepTimer.fadeSeconds + 1
        case .endOfTrack: return duration - position < SleepTimer.trackFadeSeconds + 1
        }
    }

    private func applyVolumes() {
        let now = Date()
        let sleepFactor = sleep?.factor(now: now, position: currentSeconds(), duration: duration) ?? 1
        player.volume = Float(fadeFactor(now: now) * sleepFactor)
        if let outgoing {
            let t = outgoing.span > 0 ? now.timeIntervalSince(outgoing.start) / outgoing.span : 1
            if t >= 1 {
                stopOutgoing()
            } else {
                // таймер «конец трека» к уходящему не относится — он уже кончился
                let sleepOut = sleep?.isEndOfTrack == true ? 1 : sleepFactor
                outgoing.deck.volume = Float(outgoing.gain * Fades.crossOut(t) * sleepOut)
            }
        }
    }

    private func currentSeconds() -> Double {
        let time = player.currentTime().seconds
        return time.isFinite ? time : position
    }

    /// Нормализация текущего трека: громкость по R128 Яндекса (1 — нет данных или выключено).
    private func trackGain() -> Double {
        Loudness.gain(lufs: current?.loudness, enabled: normalize)
    }

    /// Громкость текущей деки без таймера сна.
    private func fadeFactor(now: Date) -> Double {
        var factor = trackGain()
        if let rampStart {
            let elapsed = now.timeIntervalSince(rampStart)
            factor *= Fades.rampFactor(elapsed: elapsed)
            if elapsed >= 2 { self.rampStart = nil }
        }
        if let fadeIn {
            let t = fadeIn.span > 0 ? now.timeIntervalSince(fadeIn.start) / fadeIn.span : 1
            factor *= Fades.crossIn(t)
            if t >= 1 { self.fadeIn = nil }
        }
        return factor
    }

    // MARK: - Таймер сна

    /// Включить таймер (nil — выключить). «Конец трека» — следующий не подгружается и начнётся на паузе.
    func setSleep(_ option: SleepOption?) {
        sleep = option.map { SleepTimer($0) }
        if sleep?.isEndOfTrack == true {
            dropPreload()
            stopOutgoing()
        }
        updateFades()
    }

    /// Минуты вышли — пауза (громкость к этому моменту уже ушла в ноль).
    private func checkSleep() {
        guard let sleep, sleep.isDue(now: Date()) else { return }
        self.sleep = nil
        pause()
        applyVolumes()
    }

    // MARK: - Волна: «почему» и офлайн

    /// «Почему этот трек» — только у трека волны и если включено (`player.wave_why`).
    func waveReason(for track: Track) -> String? {
        guard isWave, SettingsStore.shared.bool("player.wave_why") else { return nil }
        return waveReasons[track.ref]
    }

    /// Волна без сети: следующие треки волны — в кэш (на Wi‑Fi), сыгранное — из кэша вон.
    private func refreshWaveCache() {
        WaveCache.shared.update(upcoming: upNext, current: current, isWave: isWave,
                                enabled: SettingsStore.shared.bool("storage.wave_offline"))
    }

    /// Вернуть очередь с прошлого запуска (`general.restore`) — на паузе, с той же секунды.
    private func restore() {
        guard let snapshot = snapshotFile.load()?.restored(RestoreMode.current(SettingsStore.shared)) else { return }
        tracks = snapshot.tracks
        order = snapshot.order
        pos = snapshot.pos
        contextTitle = snapshot.context
        shuffle = snapshot.shuffle
        repeatMode = snapshot.repeatMode
        autoRefs = Set(snapshot.autoRefs)
        queueId += 1
        if let track = current {
            duration = Double(track.durationMs) / 1000
            position = max(0, min(snapshot.position, duration - 1))
            pendingStart = (track.ref, position)
            rate = LibraryStore.shared.speed(for: track.ref) ?? 1
        }
    }

    /// Запомнить, что играет: при смене трека и паузе сразу, во время игры — раз в 10 с.
    private func saveSnapshot(force: Bool = false) {
        guard force || Date().timeIntervalSince(lastSnapshot) > 10 else { return }
        lastSnapshot = Date()
        guard current != nil else {
            snapshotFile.save(nil)
            return
        }
        snapshotFile.save(PlaybackSnapshot(tracks: tracks, order: order, pos: pos, position: position, context: contextTitle,
                                           shuffle: shuffle, repeatMode: repeatMode, autoRefs: Array(autoRefs)))
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
