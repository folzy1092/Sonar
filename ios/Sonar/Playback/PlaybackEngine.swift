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
/// Sonar Mix и «Волна по треку» — `MyWave`, догружается вместо «Авто похожих».
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
    /// Очередь доиграла до конца (стоит на последнем треке, пауза): «Слушать» на экране подборки начинает
    /// её заново (`ListenAction`), а не повторяет последний трек. Снимается при загрузке трека и при игре.
    private(set) var queueEnded = false
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
    /// Скорость 0.5–2× (тон не меняется — `.timeDomain`; связан со скоростью — `.varispeed`).
    private(set) var rate: Float = 1
    /// Свой тон в полутонах −12…+12, когда не связан со скоростью (`AudioTap` — только файлы, не HLS).
    private(set) var pitch: Double = 0
    /// Тон едет вместе со скоростью — slowed / sped up (сам AVPlayer, работает и на HLS).
    private(set) var pitchLinked = false
    /// Реверб 0…1, 0 — выключен (`AudioTap` — только файлы).
    private(set) var reverb: Double = 0
    /// У играющего трека свой звук («Для этого трека», `TrackSound`): правки пишутся в трек.
    private(set) var hasTrackSound = false
    /// Кривая эквалайзера трека со своим звуком (nil — общая `audio.eq`).
    private(set) var trackEq: [Double]?
    /// Треки, дописанные «Авто похожими» (в очереди — отдельным блоком).
    private(set) var autoRefs: Set<String> = []
    /// Сейчас играет Sonar Mix или «Волна по треку» — для кнопки ▶/⏸ на Главной.
    private(set) var isWave = false
    /// Волна подбирает первую порцию.
    private(set) var waveLoading = false
    /// «Волна по треку»: от какого трека (nil — Sonar Mix).
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

    /// Ранее · сейчас · далее — для листа очереди.
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
        /// Играет из резервного сервиса — тост при переходе.
        var via: FallbackVia?
        /// Второй дек сведения: сбрасывать — через контроллер.
        var forBlend = false
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
    /// Четвёртая попытка: свой поток не открылся и попроще — тот же трек из резервного сервиса.
    @ObservationIgnored private var brokenTried = false
    @ObservationIgnored private var brokenNext = false
    /// Сколько треков подряд не открылось: прошли всю очередь — стоп, а не круг мгновенных сбоев
    /// (очередь из одних треков Spotify при «повторять всё»).
    @ObservationIgnored private var failStreak = 0
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
    @ObservationIgnored private var appliedQuality: (kbps: Int, viaYandex: Bool, youTubeHigh: Bool, fallback: FallbackSettings)?
    /// Сведение (docs/BLEND.md §13): контроллер, деки поверх элементов и «держим скорость и тон» на время перехода.
    @ObservationIgnored private(set) lazy var blend = BlendController(host: self)
    @ObservationIgnored private var blendHold = false
    @ObservationIgnored private var blendDecks: [ObjectIdentifier: BlendPlayerDeck] = [:]

    init() {
        waveMode = WaveMode.stored(SettingsStore.shared.string("wave.mode"))
        restore()
        observeSettings()
        BlendAnalysisHub.shared.trackOf = { [weak self] ref in
            self?.tracks.first { $0.ref == ref } ?? BlendPartyStore.shared.track(ref)
        }
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
                        if status != .paused { self.queueEnded = false }
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
        tapFeedback()
        // пульт: играет ПК — список уходит туда, этот iPhone молчит
        if RemoteControl.shared.forward(list, from: index) { return }
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
        player.playImmediately(atRate: blendHold ? player.defaultRate : rate)
        blend.resume()
    }

    /// Пауза; идёт кроссфейд — уходящий трек замолкает сразу.
    func pause() {
        stopOutgoing()
        // B уже текущий — довести переход сразу, иначе — часы перехода и B на паузу
        if blend.phase == .promoting { blend.abort() } else { blend.pause() }
        player.pause()
    }

    func next() {
        // идёт сведение — «Следующий» сразу переводит на B
        if blend.isActive && blend.finishNow() { return }
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
        tapFeedback()
        finishPlay(skipped: true)
        pos = target
        load(autoplay: true)
    }

    func seek(to seconds: Double) {
        position = max(0, min(seconds, duration))
        // восстановленный трек ещё не загружен — начнётся с этой секунды
        if currentItem == nil, let track = current { pendingStart = (track.ref, position) }
        stopOutgoing()
        blend.cancel()
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

    /// Выбрали трек (в списке, у артиста, в очереди) — лёгкий отклик, если включён (`general.haptics`).
    private func tapFeedback() {
        guard SettingsStore.shared.bool("general.haptics") else { return }
        Haptics.tap()
    }

    func setRate(_ value: Float) {
        applyRate(value)
        persistTempo()
    }

    private func applyRate(_ value: Float) {
        rate = (min(2, max(0.5, value)) * 100).rounded() / 100
        // скоростью дек сейчас правит сведение — вернётся в `hold(false)`
        guard !blendHold else {
            nowPlaying.update()
            return
        }
        player.defaultRate = rate
        if isPlaying { player.rate = rate }
        nowPlaying.update()
    }

    // MARK: - Тон, реверб и звук трека (лист скорости)

    /// Тон, который звучит: связан — от скорости, иначе свой.
    var semitones: Double { pitchLinked ? TrackSound.linkedSemitones(Double(rate)) : pitch }

    /// Тон. Связан со скоростью — двигается скорость (как у пластинки): −2 пт ≈ ×0.89.
    func setPitch(_ semitones: Double) {
        let value = min(12, max(-12, (semitones * 10).rounded() / 10))
        if pitchLinked {
            var next = Float(TrackSound.pitchRatio(value))
            // шаг тона 0.1 пт мельче шага скорости 0.01 — сдвигаем скорость хотя бы на 0.01 в ту же сторону
            let rounded = (min(2, max(0.5, next)) * 100).rounded() / 100
            if rounded == rate, value != self.semitones { next = rate + (value > self.semitones ? 0.01 : -0.01) }
            applyRate(next)
        } else {
            pitch = value
        }
        applyTempo()
        persistTempo()
    }

    /// Связать тон со скоростью. Отвязали — тон остаётся тем, что звучал, и дальше двигается сам.
    func setPitchLinked(_ on: Bool) {
        guard on != pitchLinked else { return }
        if !on { pitch = TrackSound.linkedSemitones(Double(rate)) }
        pitchLinked = on
        applyTempo()
        persistTempo()
    }

    func setReverb(_ amount: Double) {
        reverb = (min(1, max(0, amount)) * 100).rounded() / 100
        applyTempo()
        persistTempo()
    }

    /// Всё как было: 1×, без сдвига тона и реверба.
    func resetTempo() {
        applyRate(1)
        pitch = 0
        reverb = 0
        applyTempo()
        persistTempo()
    }

    /// «Для этого трека»: включили — нынешний звук (и кривая эквалайзера) запоминается для трека; выключили —
    /// трек забывает свой звук и играет по общим настройкам.
    func setTrackSound(_ on: Bool) {
        guard let ref = current?.ref, on != hasTrackSound else { return }
        if on {
            trackEq = Equalizer.parse(SettingsStore.shared.string(Equalizer.gainsKey))
            hasTrackSound = true
            persistTempo()
        } else {
            LibraryStore.shared.rememberSound(nil, for: ref)
            applyTrackSound(for: ref)
        }
    }

    /// Кривая эквалайзера, которая сейчас звучит: трека со своим звуком или общая.
    var eqGains: [Double] { trackEq ?? Equalizer.parse(SettingsStore.shared.string(Equalizer.gainsKey)) }

    /// Сохранить кривую: у трека со своим звуком — в трек, иначе общую.
    func saveEq(_ gains: [Double]) {
        if hasTrackSound {
            trackEq = gains.map(Equalizer.clamp)
            persistTempo()
        } else {
            SettingsStore.shared.set(Equalizer.gainsKey, .string(Equalizer.isFlat(gains) ? "" : Equalizer.encode(gains)))
        }
    }

    /// Новый трек: свой звук — звучит он; иначе общие тон и реверб и 1× (SPEC §4.3).
    private func applyTrackSound(for ref: String?) {
        if let ref, let sound = LibraryStore.shared.sound(for: ref) {
            hasTrackSound = true
            pitch = sound.pitch
            pitchLinked = sound.linked
            reverb = sound.reverb
            trackEq = sound.eq
            applyRate(Float(sound.rate))
        } else {
            let settings = SettingsStore.shared
            hasTrackSound = false
            trackEq = nil
            pitch = settings.double("player.pitch")
            pitchLinked = settings.bool("player.pitch_linked")
            reverb = settings.double("player.reverb")
            applyRate(1)
        }
        applyTempo()
    }

    /// Плашка «Свой звук · …» у названия: что отличается у играющего трека; без своего звука — nil.
    var ownSoundParts: [String]? { hasTrackSound ? currentSound.ownParts : nil }

    /// Звук, который сейчас звучит, — для записи в трек.
    private var currentSound: TrackSound {
        TrackSound(rate: Double(rate), pitch: pitch, linked: pitchLinked, reverb: reverb, eq: trackEq)
    }

    private func persistTempo() {
        if hasTrackSound, let ref = current?.ref {
            LibraryStore.shared.rememberSound(currentSound, for: ref)
            return
        }
        let settings = SettingsStore.shared
        if settings.double("player.pitch") != pitch { settings.set("player.pitch", .double(pitch)) }
        if settings.bool("player.pitch_linked") != pitchLinked { settings.set("player.pitch_linked", pitchLinked) }
        if settings.double("player.reverb") != reverb { settings.set("player.reverb", .double(reverb)) }
    }

    /// Тон и реверб — в обработку звука; связанный тон — алгоритм AVPlayer у всех элементов обеих дек.
    private func applyTempo() {
        AudioTap.params.updateEffects(pitchRatio: pitchLinked ? 1 : TrackSound.pitchRatio(pitch), reverb: reverb)
        guard !blendHold else { return }
        let algorithm = pitchAlgorithm
        for deck in decks {
            for item in deck.items() where item.audioTimePitchAlgorithm != algorithm {
                item.audioTimePitchAlgorithm = algorithm
            }
        }
        if let item = preloaded?.item, item.audioTimePitchAlgorithm != algorithm { item.audioTimePitchAlgorithm = algorithm }
    }

    private var pitchAlgorithm: AVAudioTimePitchAlgorithm { pitchLinked ? .varispeed : .timeDomain }

    /// «Следующим» / «В очередь».
    func enqueue(_ track: Track, next: Bool) {
        if RemoteControl.shared.forwardEnqueue(track, next: next) { return }
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
        // CDN VK отдаёт поток только клиенту с тем же User-Agent, что и у API (Kate Mobile)
        let options: [String: Any] = VK.isCDN(url) ? [AVURLAssetHTTPUserAgentKey: VK.userAgent] : [:]
        let item = AVPlayerItem(asset: AVURLAsset(url: url, options: options))
        item.audioTimePitchAlgorithm = pitchAlgorithm
        // буфер вперёд — чтобы мобильная сеть не рвала звук
        item.preferredForwardBufferDuration = 30
        return item
    }

    /// Скачанный (или из офлайн-кэша волны) — из файла, без сети; fresh (файл не открылся или ссылка
    /// протухла) — из сети.
    /// Не играет со своего сервиса — тот же трек из резервного (`MusicCore.playable`), broken — свой
    /// поток уже не открылся в плеере.
    /// blend — сведение включено: для SoundCloud вместо HLS берётся склеенный файл, если он уже есть
    /// (`BlendStitchCache`, BLEND §13) — тогда звук идёт через `AudioTap` и в переходе слышны фильтры и эхо.
    private static func source(for track: Track, fresh: Bool, safe: Bool = false, broken: Bool = false,
                               blend: Bool = false) async throws -> MusicCore.Playable {
        // офлайн: AVPlayer ходит в сеть мимо сторожа — поэтому только файл, остальное не играет (OFFLINE.md §5)
        let offline = OfflineFlag.isOn
        if offline || (!fresh && !safe), let local = DownloadStore.shared.localURL(track.ref) {
            return .init(source: .file(url: local, quality: DownloadStore.shared.quality(track.ref) ?? "Скачан"), via: nil)
        }
        if offline || (!fresh && !safe), let cached = WaveCache.shared.localURL(track.ref) {
            return .init(source: .file(url: cached, quality: WaveCache.shared.quality(track.ref) ?? "Офлайн"), via: nil)
        }
        let stitched = blend ? BlendStitchCache.shared.localURL(track.ref, touch: true) : nil
        if let file = BlendStitchPlan.source(ref: track.ref, blendOn: blend, fresh: !offline && (fresh || safe),
                                             stitched: stitched) {
            return .init(source: file, via: nil)
        }
        if offline { throw ServiceError(message: t("Нет в офлайне — скачай трек, пока есть сеть")) }
        return try await MusicCore.shared.playable(track, fresh: fresh, safe: safe, broken: broken)
    }

    /// Офлайн включили (`OfflineMode`, OFFLINE.md §9): из «Далее» уходит недоступное; играет недоступный —
    /// затихает и встаёт на паузу (следующий сам не стартует).
    func offlineChanged() {
        if !OfflineFlag.isOn { BlendAnalysisHub.shared.forgetFailures() }
        guard OfflineFlag.isOn, !order.isEmpty else { return }
        dropPreload()
        let pruned = OfflineQueue.prune(order: order, pos: pos) { Self.isLocal(self.tracks[$0].ref) }
        order = pruned.order
        pos = pruned.pos
        saveSnapshot(force: true)
        guard let current, !Self.isLocal(current.ref), isPlaying else { return }
        Task {
            let start = player.volume
            for step in stride(from: OfflineQueue.fadeSteps - 1, through: 0, by: -1) {
                player.volume = start * Float(step) / Float(OfflineQueue.fadeSteps)
                try? await Task.sleep(for: .milliseconds(OfflineQueue.fadeStepMs))
            }
            pause()
            applyVolumes()
        }
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
        queueEnded = false
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
            brokenTried = false
            resetListening()
        }
        let safe = safeNext
        safeNext = false
        let broken = brokenNext
        brokenNext = false
        // откуда начать: свежая ссылка — с того же места, восстановленный трек — с запомненной секунды
        let start = fresh ? position : (pendingStart?.ref == track.ref ? pendingStart?.seconds ?? 0 : 0)
        pendingStart = nil
        blend.abort()
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
        // свой звук трека («Для этого трека»), иначе общий тон и реверб и 1× (SPEC §4.3)
        if !fresh { applyTrackSound(for: track.ref) }
        nowPlaying.update()
        Task {
            do {
                let playable = try await Self.source(for: track, fresh: fresh, safe: safe, broken: broken, blend: self.blendOn)
                guard token == self.loadToken else { return }
                let source = playable.source
                if let toast = FallbackPlan.toast(playable.via) { self.message = toast }
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
                        self.failStreak = 0
                        let seconds = item.duration.seconds
                        if seconds.isFinite, seconds > 0 { self.duration = seconds }
                        // эквалайзер и выравниватель — у файла (HLS их не пропускает)
                        if !self.isHLS {
                            let deck = self.blendDeck(for: item, on: self.player, hls: false)
                            AudioTap.attach(to: item, leveler: self.current?.loudness == nil, blend: deck.dsp)
                        }
                        self.nowPlaying.update()
                    case .failed:
                        if let deck = self.blendDecks[ObjectIdentifier(item)], self.blend.onDeckError(deck) { return }
                        guard let track = self.current else { return }
                        if !self.retried {
                            self.retried = true
                            self.load(autoplay: true, fresh: true)
                        } else if !self.safeRetried {
                            self.safeRetried = true
                            self.safeNext = true
                            self.load(autoplay: true, fresh: true)
                        } else if !self.brokenTried {
                            self.brokenTried = true
                            self.brokenNext = true
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
        message = t("Не играет «{title}»: {reason}", ["title": track.title, "reason": t(error.localizedDescription)])
        failStreak += 1
        // не открылась вся очередь подряд — стоп
        guard failStreak < order.count else {
            failStreak = 0
            pause()
            return
        }
        // пропустить трек; очередь кончилась — просто стоп
        if let target = QueueMath.nextPos(pos, length: order.count, repeat: repeatMode == .one ? .off : repeatMode, manual: true),
           target != pos {
            pos = target
            load(autoplay: true)
        } else {
            failStreak = 0
        }
    }

    private func dropPreload() {
        if let preloaded {
            if preloaded.forBlend, blend.phase != .idle {
                // это B сведения: затихнет и отпустится сам (`release`)
                blend.cancel()
            } else if preloaded.onStandby {
                standby.removeAllItems()
            } else {
                player.remove(preloaded.item)
            }
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
        // сведение ведёт переход само — обычная подгрузка и кроссфейд не нужны
        if considerBlend(seconds: seconds) { return }
        let crossfade = overlapSec
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
        let crossfade = overlapSec
        guard gapless || crossfade > 0, preloaded == nil, !preloading, outgoing == nil, repeatMode != .one,
              sleep?.isEndOfTrack != true, let currentItem,
              let target = QueueMath.nextPos(pos, length: order.count, repeat: repeatMode, manual: false), target != pos else { return }
        let track = tracks[order[target]]
        let token = loadToken
        let overlap = crossfade > 0
        preloading = true
        Task {
            defer { if token == self.loadToken { self.preloading = false } }
            guard let playable = try? await Self.source(for: track, fresh: false, blend: self.blendOn),
                  token == self.loadToken, self.currentItem === currentItem, self.preloaded == nil, self.outgoing == nil else { return }
            let source = playable.source
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
            self.preloaded = Preloaded(pos: target, item: item, onStandby: overlap, quality: Self.label(source), hls: hls, via: playable.via)
            if !hls {
                let leveler = track.loudness == nil
                self.preloadStatus = item.publisher(for: \.status)
                    .receive(on: DispatchQueue.main)
                    .sink { [weak item] status in
                        MainActor.assumeIsolated {
                            guard status == .readyToPlay, let item else { return }
                            let deck = self.blendDeck(for: item, on: self.standbyOrPlayer(holding: item), hls: false)
                            AudioTap.attach(to: item, leveler: leveler, blend: deck.dsp)
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
        brokenTried = false
        resetListening()
        position = 0
        quality = next.quality
        if let toast = FallbackPlan.toast(next.via) { message = toast }
        isHLS = next.hls
        if let track = current {
            duration = Double(track.durationMs) / 1000
            applyTrackSound(for: track.ref)
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
        // A доиграл посреди сведения — сразу на B
        if blend.isActive && blend.finishNow() { return }
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
                queueEnded = true
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
            queueEnded = true
            return
        }
        pos = target
        load(autoplay: true)
    }

    /// «Авто похожие»: до конца очереди меньше трёх треков — дописать похожие (повтор трека — не надо).
    private func topUpAutoplay() {
        // офлайн: похожие и волна — из сети, не добираем
        guard !OfflineFlag.isOn else { return }
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
    }

    /// Копим реально прослушанное (перемотка не считается) и засчитываем прослушивание на пороге
    /// min(30 с, половины трека) — как Windows `plays`.
    private func listened(at seconds: Double) {
        defer { lastTick = seconds }
        guard isPlaying, let last = lastTick else { return }
        let delta = seconds - last
        guard delta > 0, delta < 2 else { return }
        listenedMs += delta * 1000
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

    /// Sonar Mix: сиды из Любимых и недавнего, похожие SoundCloud и Яндекса, учится на лайках и
    /// пропусках, без 👎, бесконечно догружается. Уже играет — пауза / продолжить.
    func playMyWave() {
        if RemoteControl.shared.forwardWave() { return }
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
        // офлайн: волне нужна сеть (виджет, Siri) — честно сказать, а не ждать отказа сторожа
        guard !OfflineFlag.isOn else {
            message = t("Нет доступа к сети: включён офлайн-режим")
            return
        }
        waveLoading = true
        Task {
            defer { self.waveLoading = false }
            do {
                let list = try await self.wave.start(seed: seed, mode: self.waveMode)
                // волна по треку при пульте: список собран здесь, играет ПК
                if RemoteControl.shared.forward(list, from: 0) { return }
                if self.shuffle { self.shuffle = false }
                self.play(list, at: 0, context: seed.map { "Sonar Mix по «\($0.title)»" } ?? "Sonar Mix")
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
        guard !OfflineFlag.isOn, !waveMoreLoading, order.count - pos - 1 < Autoplay.left else { return }
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
        // у трека со своим звуком — его кривая
        AudioTap.params.update(gains: trackEq ?? Equalizer.parse(settings.string(Equalizer.gainsKey)),
                               eqEnabled: settings.bool(Equalizer.enabledKey),
                               normalize: settings.bool("audio.normalize"))
        let wasCrossfade = crossfade
        let wasNormalize = normalize
        crossfade = Double(PlayerPrefs.crossfade(settings))
        gapless = settings.bool("audio.gapless")
        normalize = settings.bool("audio.normalize")
        // подгруженный лежит не там, где нужен новому режиму (очередь деки ⇄ вторая дека) — подгрузить заново
        if let preloaded, preloaded.onStandby != (overlapSec > 0) || (!gapless && overlapSec == 0) { dropPreload() }
        // громкость — вне слежения за настройками (иначе оно подписалось бы на позицию и очередь)
        if wasCrossfade != crossfade || wasNormalize != normalize { Task { self.updateFades() } }
        let offline = settings.bool("storage.wave_offline")
        if offline != waveOffline {
            waveOffline = offline
            Task { self.refreshWaveCache() }
        }
        let kbps = MusicCore.qualityKbps(AudioQuality.current(settings).rawValue)
        let viaYandex = settings.bool("audio.sc_via_yandex")
        let youTubeHigh = YouTubeQuality.current(settings) == .high
        let fallback = FallbackSettings(enabled: settings.bool(FallbackPlan.enabledKey), saved: settings.string(FallbackPlan.orderKey))
        if appliedQuality?.kbps != kbps || appliedQuality?.viaYandex != viaYandex || appliedQuality?.youTubeHigh != youTubeHigh
            || appliedQuality?.fallback != fallback {
            appliedQuality = (kbps, viaYandex, youTubeHigh, fallback)
            Task { await MusicCore.shared.configure(maxKbps: kbps, soundCloudViaYandex: viaYandex, youTubeHigh: youTubeHigh, fallback: fallback) }
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
        let volume = fadeFactor(now: now) * sleepFactor
        // HLS в сведении: громкость кривых — у плеера, поверх обычной (`BlendPlayerDeck`)
        let deck = currentItem.flatMap { blendDecks[ObjectIdentifier($0)] }
        deck?.baseGain = volume
        player.volume = Float(volume * (deck?.hlsGain ?? 1))
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

    /// «Почему этот трек» для меню трека «⋮»: у трека волны — всегда, тумблер строки в плеере не важен
    /// (в меню человек спрашивает сам).
    func waveWhy(for track: Track) -> String? {
        guard isWave else { return nil }
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
            applyTrackSound(for: track.ref)
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

// MARK: - Сведение (docs/BLEND.md §13)

// shortcut: хост в том же файле, что и движок, — ему нужны закрытые деки, подгрузка и `advance`. Общие тон и реверб
// `AudioTap.params` на время перехода звучат на обоих деках (на ПК — свои у каждого); свой звук B — со смены.
extension PlaybackEngine: BlendHost {
    /// Сведение включено (или идёт вечеринка) — переходам нужен второй дек даже без кроссфейда.
    var blendOn: Bool { SettingsStore.shared.bool("audio.blend") || BlendPartyStore.shared.isActive }

    /// Длина наложения для обычного перехода: кроссфейд из настроек, а со сведением — запасной, если пара не сложится.
    fileprivate var overlapSec: Double {
        crossfade > 0 ? crossfade : (blendOn ? BlendPrefs.crossfadeDefaultSec : 0)
    }

    /// Дек сведения у элемента: один на элемент, отпущенные выбрасываются.
    fileprivate func blendDeck(for item: AVPlayerItem, on player: AVQueuePlayer, hls: Bool) -> BlendPlayerDeck {
        blendDecks = blendDecks.filter { $0.value.isLoaded }
        if let deck = blendDecks[ObjectIdentifier(item)] { return deck }
        let deck = BlendPlayerDeck(player: player, item: item, hls: hls)
        blendDecks[ObjectIdentifier(item)] = deck
        return deck
    }

    fileprivate func standbyOrPlayer(holding item: AVPlayerItem) -> AVQueuePlayer {
        decks.first { $0.items().contains { $0 === item } } ?? player
    }

    /// Тик текущего трека → контроллер. true — переход ведёт сведение.
    fileprivate func considerBlend(seconds: Double) -> Bool {
        guard let track = current, let currentItem, repeatMode != .one else { return false }
        BlendPartyStore.shared.step()
        let next = upNext.first?.ref
        let on = blendOn
        if on {
            // анализ текущего и следующего — заранее, к моменту перехода он уже готов
            let hub = BlendAnalysisHub.shared
            if hub.peek(track.ref) == nil { hub.request(track.ref) }
            if let next, hub.peek(next) == nil { hub.request(next) }
            // анализ следующего уже был, а склеенного файла нет — склеить, чтобы дек B играл файл, а не HLS
            if let upcoming = upNext.first { hub.prefetchStitch(upcoming) }
        }
        return blend.consider(BlendConsider(
            a: track.ref, b: next,
            deckA: blendDeck(for: currentItem, on: player, hls: isHLS),
            posMs: seconds * 1000, durMs: duration * 1000,
            enabled: on && sleep?.isEndOfTrack != true && outgoing == nil,
            rateA: Double(rate), linkedA: pitchLinked
        ))
    }

    func now() -> Double {
        ProcessInfo.processInfo.systemUptime
    }

    func after(_ sec: Double, _ run: @escaping @MainActor () -> Void) -> BlendTimer {
        BlendTaskTimer(sec, run)
    }

    func settings() -> BlendSettings {
        let store = SettingsStore.shared
        func raw(_ key: String) -> Any? {
            switch store.value(key) {
            case .bool(let v)?: return v as Any
            case .int(let v)?: return v as Any
            case .double(let v)?: return v as Any
            case .string(let v)?: return v as Any
            case nil: return nil
            }
        }
        var settings = BlendPrefs.blendSettings(BlendKeys(
            type: raw("audio.blend_type"), length: raw("audio.blend_length"), cut: raw("audio.blend_cut"),
            tempo: raw("audio.blend_tempo"), key: raw("audio.blend_key")
        ))
        settings.ratings = BlendRatings.shared.balance
        return settings
    }

    func analysis(_ ref: String) -> BlendAnalysis? {
        let hub = BlendAnalysisHub.shared
        if let found = hub.peek(ref) { return found }
        hub.request(ref)
        return nil
    }

    func sound(_ ref: String) -> BlendSound {
        if let own = LibraryStore.shared.sound(for: ref) {
            return BlendSound(rate: own.rate, pitch: own.pitch, linked: own.linked)
        }
        let settings = SettingsStore.shared
        return BlendSound(rate: 1, pitch: settings.double("player.pitch"), linked: settings.bool("player.pitch_linked"))
    }

    func load(_ ref: String, startSec: Double, done: @escaping @MainActor ((any BlendDeckControl)?) -> Void) {
        guard let target = QueueMath.nextPos(pos, length: order.count, repeat: repeatMode, manual: false),
              target != pos, tracks[order[target]].ref == ref else {
            done(nil)
            return
        }
        let track = tracks[order[target]]
        dropPreload()
        stopOutgoing()
        let token = loadToken
        Task {
            guard let playable = try? await Self.source(for: track, fresh: false, blend: self.blendOn), token == self.loadToken else {
                done(nil)
                return
            }
            let source = playable.source
            let item = self.makeItem(source)
            let hls = Self.streamsHLS(source)
            let standby = self.standby
            standby.pause()
            standby.removeAllItems()
            standby.volume = 0
            standby.insert(item, after: nil)
            self.preloaded = Preloaded(pos: target, item: item, onStandby: true, quality: Self.label(source), hls: hls,
                                       via: playable.via, forBlend: true)
            let deck = self.blendDeck(for: item, on: standby, hls: hls)
            guard await Self.blendReady(item), token == self.loadToken, self.preloaded?.item === item else {
                if self.preloaded?.item === item { self.release(deck) }
                done(nil)
                return
            }
            if !hls { AudioTap.attach(to: item, leveler: track.loudness == nil, blend: deck.dsp) }
            await item.seek(to: CMTime(seconds: max(0, startSec), preferredTimescale: 600),
                            toleranceBefore: .zero, toleranceAfter: .zero)
            guard token == self.loadToken, self.preloaded?.item === item else {
                done(nil)
                return
            }
            deck.baseGain = Loudness.gain(lufs: track.loudness, enabled: self.normalize)
            standby.volume = Float(deck.baseGain)
            done(deck)
        }
    }

    /// Ждать готовности элемента второго дека не дольше стольких секунд.
    private static let blendReadySec = 10.0
    private static let blendReadyPollNs: UInt64 = 100_000_000

    private static func blendReady(_ item: AVPlayerItem) async -> Bool {
        let deadline = Date().addingTimeInterval(blendReadySec)
        while Date() < deadline {
            switch item.status {
            case .readyToPlay: return true
            case .failed: return false
            default: try? await Task.sleep(nanoseconds: blendReadyPollNs)
            }
        }
        return false
    }

    func promote(_ deck: any BlendDeckControl, listenedMs: Double) {
        guard let next = preloaded, next.forBlend, (deck as? BlendPlayerDeck)?.item === next.item else { return }
        finishPlay(skipped: false)
        preloaded = nil
        preloadStatus = nil
        active = 1 - active
        advance(to: next)
        self.listenedMs = listenedMs
        isPlaying = true
        updateFades()
        if let done = blend.done { BlendRatings.shared.open(done) }
    }

    func release(_ deck: any BlendDeckControl) {
        guard let deck = deck as? BlendPlayerDeck else { return }
        if preloaded?.item === deck.item {
            preloaded = nil
            preloadStatus = nil
        }
        deck.stop()
        // текущий трек не трогаем: отпускают только ушедший A или так и не ставший текущим B
        if deck.item !== currentItem {
            if deck.player.currentItem === deck.item { deck.player.pause() }
            deck.player.remove(deck.item)
        }
        blendDecks[ObjectIdentifier(deck.item)] = nil
    }

    func hold(_ on: Bool) {
        guard on != blendHold else { return }
        blendHold = on
        guard !on else { return }
        // переход кончился: скорость и тон — снова те, что выбраны для текущего трека
        applyRate(rate)
        applyTempo()
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
