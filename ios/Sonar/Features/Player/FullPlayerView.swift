import SwiftUI
import UIKit

/// Полный плеер (`reference/mobile/player.jpg`): сверху ⌄ · контекст «❤ Любимые ⤮» · ⋮, обложка на весь
/// фон с затемнением к низу, название и исполнитель (выделяются и копируются), ползунок, время и «Далее»,
/// кнопки в капсуле (повтор · назад · пауза · вперёд · перемешать), снизу лайк и скорость. Свайп вниз
/// закрывает.
///
/// Вид — Профиль → Вид плеера (`player.*`): стиль (большая обложка / квадрат / пластинка), фон, выравнивание
/// названия, ползунок, кнопка «играть», аватарки артистов. Свайп вбок и двойной / тройной тап по обложке —
/// Профиль → Жесты (`gestures.player.*`, `gestures.cover.*`).
struct FullPlayerView: View {
    @Environment(PlaybackEngine.self) private var engine
    @Environment(LibraryStore.self) private var library
    @Environment(SettingsStore.self) private var settings
    /// Плеер закрывает флаг в Router, а не `dismiss` окружения — тот в этом месте не срабатывал (плеер не закрывался).
    @Environment(Router.self) private var router
    /// Свайп по обложке вбок — она чуть едет за пальцем.
    @State private var coverShift: CGFloat = 0
    /// Где обложка — свайп вбок считается, только если начат на ней.
    @State private var coverFrame: CGRect = .zero
    /// Большое сердце по двойному тапу.
    @State private var likeBurst = 0
    @State private var burstShown = false
    /// Пластинка: угол, накопленный до последней паузы, и когда снова закрутилась.
    @State private var spinBase: Double = 0
    @State private var spinStart: Date?

    private var style: PlayerStyle { .current(settings) }
    @State private var scrubbing: Double?
    @State private var showQueue = false
    @State private var showSpeed = false
    /// Шторка «Сведение» (docs/BLEND.md §10.1).
    @State private var showBlend = false
    @State private var dragDown: CGFloat = 0
    /// Текст песни на весь экран (`IMG_6787..6790`); держится между открытиями плеера.
    @AppStorage("player.lyrics_open") private var showLyrics = false
    /// Кнопки спрятаны: текст открыт, экран не трогали ~2,5 с, и сменилась строка.
    @State private var chromeHidden = false
    @State private var lastTouch = Date()
    @State private var showLyricsMenu = false
    /// T в тексте зажата — кнопка чуть проседает, как остальные.
    @State private var lyricsCirclePressed = false
    /// Меню трека (⋮). Своё: общий лист в RootView не показывается поверх полноэкранного плеера.
    @State private var trackMenu: TrackMenuItem?
    @Environment(ChromeState.self) private var chrome

    private var lyricsStore: LyricsStore { LyricsStore.shared }
    /// «Где играть»: этот iPhone или Sonar на ПК (пульт).
    @State private var showDevices = false

    var body: some View {
        Group {
            if RemoteControl.shared.isActive {
                RemotePlayerView(showDevices: $showDevices)
                    .transition(.opacity)
            } else {
                localPlayer
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: RemoteControl.shared.isActive)
        .sheet(isPresented: $showDevices) {
            DevicePickerSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(30)
                .presentationBackground(Theme.background)
        }
    }

    private var localPlayer: some View {
        ZStack {
            if showLyrics {
                lyricsBackground
                    .transition(.opacity)
                lyricsLayer
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .transition(.opacity)
            } else if style == .large {
                background
                    .transition(.opacity)
            } else {
                backdrop
                    .transition(.opacity)
            }
            // верх экрана — смахнуть вниз, чтобы свернуть (и в тексте, где вертикаль листает строки);
            // тап сюда, пока шапка спрятана, только возвращает кнопки — в строку не проваливается
            Color.clear
                .frame(height: Self.closeZone)
                .contentShape(Rectangle())
                .onTapGesture { touched() }
                .highPriorityGesture(closeDrag)
                .frame(maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea(edges: .top)
                .zIndex(1)
            VStack(spacing: 0) {
                // в тексте при простое шапка уходит вместе с кнопками — остаётся только текст
                // (просьба владельца 2026-11-21); первый тап возвращает всё, тап по шапке не перематывает строку
                Group {
                    if showLyrics { lyricsTopBar } else { topBar }
                }
                .highPriorityGesture(closeDrag)
                .opacity(chromeHidden ? 0 : 1)
                .offset(y: chromeHidden ? -16 : 0)
                .allowsHitTesting(!chromeHidden)
                if showLyrics {
                    Spacer(minLength: 20)
                } else {
                    coverArea
                }
                if let track = engine.current, !showLyrics {
                    titleBlock(track)
                        .id(track.ref)
                        .transition(.opacity.combined(with: .offset(y: 8)))
                }
                VStack(spacing: 0) {
                    slider
                        .padding(.top, 22)
                    timeRow
                        .padding(.top, 8)
                    controls
                        .padding(.top, 18)
                    if !showLyrics {
                        bottomRow
                            .padding(.top, 14)
                            .transition(.opacity.combined(with: .offset(y: 10)))
                    }
                }
                .opacity(chromeHidden ? 0 : 1)
                .offset(y: chromeHidden ? 24 : 0)
                .allowsHitTesting(!chromeHidden)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 10)
            .zIndex(2)
        }
        .coordinateSpace(.named(Self.space))
        .offset(y: max(0, dragDown))
        .gesture(
            // вниз — закрыть; вбок по обложке — жест из настроек (следующий / предыдущий / лайк)
            DragGesture(coordinateSpace: .named(Self.space))
                .onChanged { value in
                    let dx = value.translation.width, dy = value.translation.height
                    if onCover(value.startLocation), abs(dx) > abs(dy), !showLyrics {
                        let direction: SwipeDirection = dx < 0 ? .left : .right
                        coverShift = dx * (Gestures.action(settings, .player, direction) == .off ? 0.08 : 0.35)
                        dragDown = 0
                    } else {
                        dragDown = dy
                    }
                }
                .onEnded { value in
                    let dx = value.translation.width, dy = value.translation.height
                    if onCover(value.startLocation), !showLyrics,
                       let action = Gestures.resolve(settings, .player, dx: dx, dy: dy) {
                        GestureRunner.perform(action, track: engine.current)
                    } else if dy > 140, abs(dy) > abs(dx) {
                        close()
                    }
                    withAnimation(Motion.spring) {
                        dragDown = 0
                        coverShift = 0
                    }
                },
            // в тексте вертикальный жест — прокрутка строк, закрывать плеер нельзя
            including: showLyrics ? .subviews : .all
        )
        .animation(.easeInOut(duration: 0.45), value: showLyrics)
        .animation(.easeInOut(duration: 0.6), value: chromeHidden)
        .task(id: engine.current?.ref) {
            if let track = engine.current { await lyricsStore.load(for: track) }
            // следующий в очереди — заранее, чтобы текст открывался сразу
            if let next = engine.upNext.first { await lyricsStore.preload(next) }
        }
        .onChange(of: lyricsStore.translationMessage) { _, message in
            if let message {
                engine.message = t(message)
                lyricsStore.translationMessage = nil
            }
        }
        .onChange(of: showLyrics) { _, open in
            if !open { chromeHidden = false }
            lastTouch = Date()
        }
        // простой ~2,5 с в тексте — по таймеру, а не только по смене строки: в проигрыше и у текста
        // без времени строки не меняются
        .task(id: showLyrics) {
            guard showLyrics else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                idleCheck()
            }
        }
        .statusBarHidden(showLyrics && chromeHidden)
        .persistentSystemOverlays(showLyrics && chromeHidden ? .hidden : .automatic)
        .sheet(isPresented: $showLyricsMenu) {
            if let track = engine.current {
                LyricsMenuSheet(track: track)
                    .presentationDetents([.height(470)])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(30)
                    .presentationBackground(Theme.background)
            }
        }
        .animation(Motion.spring, value: engine.current?.ref)
        .sheet(item: $trackMenu) { item in
            TrackSheet(item: item)
                .presentationDetents([.fraction(0.86), .large])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(30)
                .presentationBackground(Theme.background)
        }
        .sheet(isPresented: $showQueue) {
            QueueSheet()
                .presentationDetents([.large])
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showSpeed) {
            SpeedSheet()
                // тон, реверб и «Для этого трека» — выше; таймер сна по настройке `player.sleep_button` — ещё выше
                .presentationDetents([.height(settings.bool("player.sleep_button") ? 700 : 600), .large])
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showBlend) {
            BlendSheet()
                .presentationDetents([.fraction(0.8), .large])
                .presentationBackground(.ultraThinMaterial)
        }
        .overlay(alignment: .top) {
            if let message = engine.message {
                Text(message)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 60)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { withAnimation(Motion.spring) { engine.message = nil } }
            }
        }
        .animation(Motion.spring, value: engine.message)
        .animation(.easeInOut(duration: 0.45), value: style)
        .onChange(of: engine.isPlaying, initial: true) { _, playing in
            // пластинка: пауза — замирает на месте, а не прыгает
            if playing {
                spinStart = Date()
            } else if let start = spinStart {
                spinBase += Date().timeIntervalSince(start) * Self.spinSpeed
                spinStart = nil
            }
        }
    }

    // MARK: - Обложка: стили, жесты

    nonisolated private static let space = "player"
    /// Градусов в секунду: оборот за 24 с — спокойно, как на ПК (`Player.svelte` `vinyl-spin`).
    private static let spinSpeed = 15.0

    private func onCover(_ point: CGPoint) -> Bool {
        coverFrame.insetBy(dx: -8, dy: -8).contains(point)
    }

    /// Между шапкой и названием: у «Большого» — прозрачная область поверх обложки-фона, у «Обычного» —
    /// квадрат, у «Пластинки» — круглая вращающаяся обложка. Тапы — из настроек жестов.
    private var coverArea: some View {
        Group {
            switch style {
            case .large:
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .standard:
                CoverImage(url: engine.current?.coverURL, cornerRadius: 22)
                    .aspectRatio(1, contentMode: .fit)
                    .shadow(color: .black.opacity(0.45), radius: 24, y: 12)
                    .scaleEffect(engine.isPlaying ? 1 : 0.92)
                    .animation(Motion.spring, value: engine.isPlaying)
                    .id(engine.current?.ref)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .vinyl:
                vinyl
                    .padding(.horizontal, 6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.vertical, style == .large ? 0 : 18)
        .contentShape(Rectangle())
        .offset(x: coverShift)
        .gesture(coverTaps)
        .overlay { likeBurstView }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { coverFrame = $0 }
        .animation(.easeInOut(duration: 0.45), value: engine.current?.ref)
    }

    /// «Пластинка»: просто круглая обложка во всю площадь, медленно вращается, пока играет — без диска,
    /// бороздок и иглы (владелец 2026-11-22: «не в буквальном смысле»; как на ПК).
    private var vinyl: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: !engine.isPlaying)) { context in
            let angle = spinBase + (spinStart.map { context.date.timeIntervalSince($0) } ?? 0) * Self.spinSpeed
            GeometryReader { proxy in
                let side = min(proxy.size.width, proxy.size.height)
                CoverImage(url: engine.current?.coverURL, cornerRadius: side / 2)
                    .frame(width: side, height: side)
                    .clipShape(Circle())
                    .id(engine.current?.ref)
                    .transition(.opacity)
                    .rotationEffect(.degrees(angle))
                    .shadow(color: .black.opacity(0.45), radius: 24, y: 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .aspectRatio(1, contentMode: .fit)
        }
    }

    /// Двойной / тройной тап (`gestures.cover.*`). Тройной выключен — двойной срабатывает без ожидания.
    private var coverTaps: AnyGesture<Void> {
        let double = Gestures.action(settings, .double_tap)
        let triple = Gestures.action(settings, .triple_tap)
        let doubleTap = TapGesture(count: 2).onEnded { coverTapped(double) }
        guard triple != .off else { return AnyGesture(doubleTap) }
        return AnyGesture(
            TapGesture(count: 3).onEnded { coverTapped(triple) }
                .exclusively(before: doubleTap)
                .map { _ in () }
        )
    }

    private func coverTapped(_ action: GestureAction) {
        guard action != .off, let track = engine.current else { return }
        if action == .like {
            // двойной тап ставит лайк (не снимает) — как в соцсетях; сердце вспыхивает
            if !library.isLiked(track) { library.toggleLike(track) }
            Haptics.hold()
            likeBurst += 1
            return
        }
        GestureRunner.perform(action, track: track)
    }

    private var likeBurstView: some View {
        SonarIcon(.heart, filled: true, size: 110)
            .foregroundStyle(Theme.accent)
            .shadow(color: .black.opacity(0.35), radius: 18)
            .scaleEffect(burstShown ? 1 : 0.4)
            .opacity(burstShown ? 1 : 0)
            .allowsHitTesting(false)
            .onChange(of: likeBurst) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { burstShown = true }
                Task {
                    try? await Task.sleep(for: .milliseconds(650))
                    withAnimation(.easeOut(duration: 0.3)) { burstShown = false }
                }
            }
    }

    /// Фон «Обычного» и «Пластинки» (`player.background`): без фона, размытая обложка или цвет обложки.
    private var backdrop: some View {
        GeometryReader { proxy in
            ZStack {
                Theme.background
                switch PlayerBackground.current(settings) {
                case .none:
                    EmptyView()
                case .cover_blur:
                    CoverImage(url: engine.current?.coverURL, cornerRadius: 0)
                        .frame(width: proxy.size.width * 1.5, height: proxy.size.height * 1.2)
                        .blur(radius: 60)
                        .saturation(1.2)
                        .opacity(0.7)
                        .id(engine.current?.ref)
                        .transition(.opacity)
                    LinearGradient(colors: [.black.opacity(0.2), .black.opacity(0.45), .black.opacity(0.8)],
                                   startPoint: .top, endPoint: .bottom)
                case .cover_color:
                    LinearGradient(colors: [Theme.tint.opacity(0.9), Theme.glow.opacity(0.35), Theme.background],
                                   startPoint: .top, endPoint: .bottom)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.6), value: engine.current?.ref)
        .animation(.easeInOut(duration: 0.4), value: PlayerBackground.current(settings))
    }

    // MARK: - Текст песни

    /// Фон текста: обложка, сильно размытая и затемнённая, — цветные пятна, как на скринах.
    private var lyricsBackground: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black
                CoverImage(url: engine.current?.coverURL, cornerRadius: 0)
                    .frame(width: proxy.size.width * 1.6, height: proxy.size.height * 1.2)
                    .blur(radius: 70)
                    .saturation(1.3)
                    .opacity(0.85)
                    .id(engine.current?.ref)
                    .transition(.opacity)
                LinearGradient(colors: [.black.opacity(0.15), .black.opacity(0.35), .black.opacity(0.7)],
                               startPoint: .top, endPoint: .bottom)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.8), value: engine.current?.ref)
    }

    @ViewBuilder
    private var lyricsLayer: some View {
        if let track = engine.current {
            Group {
                if let lyrics = lyricsStore.lyrics, lyricsStore.trackRef == track.ref, !lyrics.lines.isEmpty {
                    LyricsView(
                        lyrics: lyrics,
                        offset: lyricsStore.offset(for: track.ref),
                        look: LyricsLook.current(),
                        translation: lyricsStore.translation,
                        topInset: 110,
                        bottomInset: chromeHidden ? 120 : 250,
                        onSeek: { engine.seek(to: $0) },
                        onTouch: touched,
                        onLineChange: { _ in lineChanged() }
                    )
                    .id(track.ref)
                } else if lyricsStore.loading {
                    ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 12) {
                        SonarIcon(.lyrics, size: 34).foregroundStyle(Color.white.opacity(0.6))
                        Text(lyricsStore.failed ?? "Текст не найден")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.75))
                        Button("Найти заново") { Task { await lyricsStore.reload(for: track) } }
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            // строки, ушедшие под шапку, гаснут — шапка читается и не спорит с текстом
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .clear, location: 0.35),
                                           .init(color: .black, location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: Self.lyricsFade)
                    Color.black
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { touched() }
            .onLongPressGesture(minimumDuration: 0.45) {
                Haptics.hold()
                showLyricsMenu = true
            }
        }
    }

    /// Высота затухания текста под шапкой (шапка — 52 pt).
    private static let lyricsFade: CGFloat = 110

    /// Шапка в тексте: ⌄ · капсула с треком (тап — обратно к обложке) · ⋮ (меню текста).
    private var lyricsTopBar: some View {
        HStack(spacing: 10) {
            Button { close() } label: {
                SonarIcon(.chevronDown, size: 28)
                    .foregroundStyle(Theme.text)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(PressableStyle(scale: 0.88))
            Button { showLyrics = false } label: {
                HStack(spacing: 10) {
                    CoverImage(url: engine.current?.coverURL, cornerRadius: 9)
                        .frame(width: 38, height: 38)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(engine.current?.title ?? "")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                        Text(engine.current?.artist ?? "")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, 6)
                .padding(.trailing, 14)
                .frame(height: 52)
                .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Вернуться к обложке")
            translateButton
            // ⋮ — то же меню трека, что и без текста; меню текста — зажать текст или кнопку T
            Button {
                touched()
                if let track = engine.current { trackMenu = TrackMenuItem(track: track) }
            } label: {
                SonarIcon(.more, size: 26)
                    .foregroundStyle(Theme.text)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle(scale: 0.88))
            .accessibilityLabel("Меню трека")
        }
        // промежутки между кнопками тоже шапка: тап — показать кнопки, а не перемотать строку под ней
        .contentShape(Rectangle())
        .onTapGesture { touched() }
    }

    /// Перевод текста на язык интерфейса — на виду в шапке (раньше был только в меню текста по долгому
    /// нажатию, и его никто не находил). Включён — подсвечен и держится для следующих треков.
    private var translateButton: some View {
        let on = lyricsStore.translationLanguage != nil
        return Button {
            touched()
            Haptics.tap()
            if on { lyricsStore.clearTranslation() } else { Task { await lyricsStore.translate(to: currentLang().rawValue) } }
        } label: {
            ZStack {
                if lyricsStore.translating {
                    ProgressView().tint(Theme.text).transition(.opacity)
                } else {
                    SonarIcon(.translate, size: 23)
                        .foregroundStyle(on ? Theme.accentInk : Theme.text)
                        .transition(.opacity)
                }
            }
            .frame(width: 44, height: 44)
            .background(on ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.ultraThinMaterial), in: Circle())
            .contentShape(Circle())
            .animation(Motion.spring, value: on)
            .animation(Motion.spring, value: lyricsStore.translating)
        }
        .buttonStyle(PressableStyle(scale: 0.88))
        .accessibilityLabel(t(on ? "Без перевода" : "Перевести"))
    }

    /// Касание экрана — кнопки возвращаются, отсчёт простоя сначала.
    private func touched() {
        lastTouch = Date()
        if chromeHidden { chromeHidden = false }
    }

    /// Новая строка: если ~2,5 с не трогали и музыка играет — кнопки плавно уходят.
    private func lineChanged() {
        idleCheck()
    }

    /// Простой в тексте: ~2,5 с без касаний, музыка играет, никаких листов и жестов — прячем всё, кроме текста.
    private func idleCheck() {
        guard showLyrics, !chromeHidden, engine.isPlaying, !showLyricsMenu, trackMenu == nil, !showQueue,
              !showSpeed, !showBlend, !showDevices, dragDown == 0, scrubbing == nil else { return }
        if Date().timeIntervalSince(lastTouch) > 2.5 { chromeHidden = true }
    }

    /// Высота полосы сверху, за которую плеер смахивается вниз.
    private static let closeZone: CGFloat = 150

    /// Смахнуть вниз за верх экрана — свернуть плеер.
    private var closeDrag: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .onChanged { value in
                let dy = value.translation.height
                if dy > 0, dy > abs(value.translation.width) { dragDown = dy }
            }
            .onEnded { value in
                let dy = value.translation.height
                if dy > 0, dy > abs(value.translation.width), dy > 120 || value.predictedEndTranslation.height > 320 {
                    close()
                }
                withAnimation(Motion.spring) { dragDown = 0 }
                touched()
            }
    }

    /// Обложка на весь экран, к низу — в чёрный.
    private var background: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                Color.black
                CoverImage(url: engine.current?.coverURL, cornerRadius: 0)
                    .frame(width: proxy.size.width, height: proxy.size.height * 0.72)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .offset(x: coverShift * 0.6)
                    .id(engine.current?.ref)
                    .transition(.opacity)
                LinearGradient(colors: [.clear, .black.opacity(0.6), .black], startPoint: .init(x: 0.5, y: 0.35), endPoint: .init(x: 0.5, y: 0.78))
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.45), value: engine.current?.ref)
    }

    private var topBar: some View {
        HStack {
            Button { close() } label: {
                SonarIcon(.chevronDown, size: 28)
                    .foregroundStyle(Theme.text)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(PressableStyle(scale: 0.88))
            Spacer()
            Button { showQueue = true } label: {
                HStack(spacing: 8) {
                    SonarIcon(.heart, filled: true, size: 15)
                    Text(engine.contextTitle.isEmpty ? "Очередь" : engine.contextTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    if engine.shuffle {
                        SonarIcon(.shuffle, size: 12)
                            .foregroundStyle(Theme.accentInk)
                            .frame(width: 20, height: 20)
                            .background(Theme.accent, in: Circle())
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 16)
                .frame(height: 40)
                .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(PressableStyle())
            .animation(Motion.spring, value: engine.shuffle)
            Spacer()
            Button {
                if let track = engine.current { trackMenu = TrackMenuItem(track: track) }
            } label: {
                SonarIcon(.more, size: 26)
                    .foregroundStyle(Theme.text)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle(scale: 0.88))
            .disabled(engine.current == nil)
            .accessibilityLabel("Меню трека")
        }
    }

    private static let titleLines = 4
    private static let titleMinScale: CGFloat = 0.74

    private func titleBlock(_ track: Track) -> some View {
        let align = TitleAlign.current(settings)
        let horizontal: HorizontalAlignment = align == .left ? .leading : align == .right ? .trailing : .center
        let frameAlign: Alignment = align == .left ? .leading : align == .right ? .trailing : .center
        let text: TextAlignment = align == .left ? .leading : align == .right ? .trailing : .center
        return VStack(alignment: horizontal, spacing: 6) {
            // до 4 строк; не влезло — шрифт мельче (до ~18 pt), многоточие только после этого
            // (POLISH_PROMPT п. 6). С открытым текстом песни блока нет — там своя строка трека
            Text(track.title)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(text)
                .lineLimit(Self.titleLines)
                .minimumScaleFactor(Self.titleMinScale)
                .textSelection(.enabled)
            artistLink(track)
            // «Почему этот трек» — у треков волны, одной строкой
            if let reason = engine.waveReason(for: track) {
                HStack(spacing: 5) {
                    SonarIcon(.sparkles, size: 13)
                    Text(reason)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .transition(.opacity.combined(with: .offset(y: 4)))
                .accessibilityLabel("Почему этот трек: \(reason)")
            }
            if let quality = engine.quality {
                Text(quality)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.1), in: Capsule())
                    .transition(.opacity)
            }
            if let parts = engine.ownSoundParts {
                OwnSoundChip(parts: parts) { showSpeed = true }
            }
        }
        .frame(maxWidth: .infinity, alignment: frameAlign)
        .animation(Motion.spring, value: engine.quality)
        .animation(Motion.spring, value: engine.ownSoundParts)
        .animation(Motion.spring, value: align)
    }

    /// Исполнитель — тап открывает его страницу (плеер уезжает вниз); несколько — список на выбор.
    /// Долгое нажатие — «Скопировать».
    @ViewBuilder
    private func artistLink(_ track: Track) -> some View {
        let label = HStack(spacing: 6) {
            if settings.bool("player.artist_avatars"), let avatar = track.artists.first?.avatarURL {
                CoverImage(url: avatar, cornerRadius: 10)
                    .frame(width: 20, height: 20)
            }
            Text(track.artist)
                .font(.system(size: 16))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        Group {
            if track.artists.filter({ !$0.ref.isEmpty }).count > 1 {
                Menu {
                    ForEach(track.artists.filter { !$0.ref.isEmpty }, id: \.self) { artist in
                        Button(artist.name) { openArtist(artist) }
                    }
                } label: { label }
            } else if let artist = track.artists.first(where: { !$0.ref.isEmpty }) {
                Button { openArtist(artist) } label: { label }
                    .buttonStyle(PressableStyle())
            } else {
                label
            }
        }
        .contextMenu {
            Button { UIPasteboard.general.string = track.artist } label: { Text("Скопировать") }
        }
        .accessibilityLabel("Исполнитель: \(track.artist)")
    }

    private func openArtist(_ artist: ArtistRef) {
        router.push(.artist(ref: artist.ref, name: artist.name), on: chrome.tab, chrome: chrome)
    }

    private var slider: some View {
        let value = scrubbing ?? engine.position
        let fraction = engine.duration > 0 ? min(1, max(0, value / engine.duration)) : 0
        return PlayerSlider(style: .current(settings), fraction: fraction, playing: engine.isPlaying,
                            seed: engine.current?.ref ?? "", scrubbing: scrubbing != nil,
                            onScrub: { part in withAnimation(Motion.quick) { scrubbing = part * engine.duration } },
                            onCommit: {
                                if let scrubbing { engine.seek(to: scrubbing) }
                                withAnimation(Motion.quick) { scrubbing = nil }
                            })
            .animation(Motion.spring, value: SliderStyle.current(settings))
    }

    private func close() {
        router.playerOpen = false
    }

    private var timeRow: some View {
        HStack {
            Text(Self.time(scrubbing ?? engine.position))
            Spacer()
            if let next = engine.upNext.first {
                // последние 10 с (`queue.preview`) — «Дальше через N с» и подсветка
                let left = engine.duration - (scrubbing ?? engine.position)
                let soon = settings.bool("queue.preview") && engine.duration > 0 && left <= 10 && left > 0
                // тап по «Далее» — очередь (переключить трек — свайпом по обложке или кнопкой ⏭)
                Button { showQueue = true } label: {
                    HStack(spacing: 6) {
                        CoverImage(url: next.coverURL, cornerRadius: 4).frame(width: 20, height: 20)
                        Text(next.title).lineLimit(1).frame(maxWidth: 110)
                        Text(soon ? "через \(Int(left.rounded(.up))) с" : "Далее")
                            .foregroundStyle(soon ? Theme.text : Theme.textSecondary)
                            .contentTransition(.numericText())
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(.ultraThinMaterial, in: Capsule())
                    .background(Theme.accent.opacity(soon ? 0.35 : 0), in: Capsule())
                    .scaleEffect(soon ? 1.04 : 1)
                    .animation(Motion.spring, value: soon)
                }
                .buttonStyle(PressableStyle())
                .transition(.opacity)
            }
            Spacer()
            Text(Self.time(engine.duration))
        }
        .font(.system(size: 13).monospacedDigit())
        .foregroundStyle(Theme.textSecondary)
    }

    /// Ряд кнопок. С открытым текстом — компактный (`PlayerControlsLayout.compact`): капсула мельче,
    /// слева ♥, справа T — закрыть текст.
    private var controls: some View {
        let layout = PlayerControlsLayout.current(lyricsOpen: showLyrics)
        return HStack(spacing: layout.gap) {
            if layout.hasSideButtons, let track = engine.current {
                likeCircle(track, side: layout.sideButton)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
            transport(layout)
            if layout.hasSideButtons {
                lyricsCircle(side: layout.sideButton)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .foregroundStyle(Theme.text)
        .buttonStyle(PressableStyle(scale: 0.88))
    }

    /// Капсула ⟲ ⏮ ▶ ⏭ ⤨.
    private func transport(_ layout: PlayerControlsLayout) -> some View {
        HStack(spacing: 0) {
            Button { engine.cycleRepeat() } label: {
                PlayerToggleIcon(
                    icon: RepeatUI.icon(engine.repeatMode),
                    active: engine.repeatMode != .off,
                    stateKey: engine.repeatMode.rawValue,
                    size: layout.toggleIcon
                )
            }
            .accessibilityLabel(t("Повтор"))
            .accessibilityValue(RepeatUI.value(of: t(RepeatUI.labelKey(engine.repeatMode))))
            Spacer(minLength: PlayerControlsLayout.minSpacing)
            Button { engine.previous() } label: { skipIcon(.prev, layout) }
            Spacer(minLength: PlayerControlsLayout.minSpacing)
            Button { engine.toggle() } label: {
                playButton
                    .scaleEffect(layout.playScale)
                    .frame(width: layout.playSide, height: layout.playSide)
            }
            Spacer(minLength: PlayerControlsLayout.minSpacing)
            Button { engine.next() } label: { skipIcon(.next, layout) }
            Spacer(minLength: PlayerControlsLayout.minSpacing)
            Button { engine.toggleShuffle() } label: {
                PlayerToggleIcon(icon: .shuffle, active: engine.shuffle, stateKey: "\(engine.shuffle)",
                                 size: layout.toggleIcon)
            }
            .accessibilityLabel(t("Перемешивание"))
            .accessibilityValue(RepeatUI.value(of: t(RepeatUI.shuffleKey(engine.shuffle))))
        }
        .font(.system(size: 22))
        .padding(.horizontal, layout.capsulePadding)
        .frame(height: layout.rowHeight)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func skipIcon(_ icon: IconName, _ layout: PlayerControlsLayout) -> some View {
        SonarIcon(icon, filled: true, size: layout.skipIcon)
            .frame(width: layout.skipIcon + PlayerControlsLayout.skipPad,
                   height: layout.skipIcon + PlayerControlsLayout.skipPad)
            .contentShape(Rectangle())
    }

    /// ♥ слева от капсулы, когда открыт текст.
    private func likeCircle(_ track: Track, side: CGFloat) -> some View {
        let liked = library.isLiked(track)
        return Button { withAnimation(Motion.spring) { library.toggleLike(track) } } label: {
            SonarIcon(.heart, filled: liked, size: 22)
                .foregroundStyle(liked ? Theme.accent : Theme.text)
                .scaleEffect(liked ? 1.08 : 1)
                .frame(width: side, height: side)
                .background(.ultraThinMaterial, in: Circle())
        }
        .accessibilityLabel(t(liked ? "Убрать из Любимых" : "В Любимые"))
    }

    /// T справа от капсулы, когда открыт текст: подсвечена. Тап — обратно к обложке, зажать — меню
    /// текста (как зажать сам текст).
    private func lyricsCircle(side: CGFloat) -> some View {
        SonarIcon(.letterT, size: 22)
            .foregroundStyle(Theme.accentInk)
            .frame(width: side, height: side)
            .background(Theme.accent, in: Circle())
            .contentShape(Circle())
            .scaleEffect(lyricsCirclePressed ? 0.88 : 1)
            .animation(Motion.spring, value: lyricsCirclePressed)
            .onTapGesture { Haptics.tap(); showLyrics = false }
            .onLongPressGesture(minimumDuration: 0.45) {
                Haptics.hold()
                touched()
                showLyricsMenu = true
            } onPressingChanged: { lyricsCirclePressed = $0 }
            .accessibilityElement()
            .accessibilityAddTraits([.isButton, .isSelected])
            .accessibilityLabel(t("Текст песни"))
            .accessibilityAction(named: t("Меню текста")) { showLyricsMenu = true }
    }

    /// «Играть» в стиле `player.play_button`: круг, квадрат со скруглением или просто значок.
    @ViewBuilder
    private var playButton: some View {
        let icon = SonarIcon(engine.isPlaying ? .pause : .play, filled: true, size: 34).contentTransition(.opacity)
        switch PlayButtonStyle.current(settings) {
        case .circle:
            icon
                .foregroundStyle(Theme.accentInk)
                .frame(width: 72, height: 72)
                .background(Theme.accent, in: Circle())
                .shadow(color: Theme.glow.opacity(0.4), radius: 16, y: 4)
                .transition(.scale(scale: 0.8).combined(with: .opacity))
        case .square:
            icon
                .foregroundStyle(Theme.accentInk)
                .frame(width: 70, height: 70)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: Theme.glow.opacity(0.4), radius: 16, y: 4)
                .transition(.scale(scale: 0.8).combined(with: .opacity))
        case .clean:
            SonarIcon(engine.isPlaying ? .pause : .play, filled: true, size: 46)
                .contentTransition(.opacity)
                .foregroundStyle(Theme.text)
                .frame(width: 72, height: 72)
                .transition(.scale(scale: 0.8).combined(with: .opacity))
        }
    }

    /// Сведение (`BlendButton.svelte`): включено или идёт вечеринка — значок акцентом; ждёт оценка — точка в углу.
    private var blendButton: some View {
        let ratings = BlendRatings.shared
        let asking = ratings.ask != nil && ratings.answer == nil
        return Button { showBlend = true } label: {
            SonarIcon(.crossfade, size: 26)
                .foregroundStyle(engine.blendOn ? Theme.accent : Theme.text)
                .overlay(alignment: .topTrailing) {
                    if asking {
                        Circle()
                            .fill(Theme.accent)
                            .frame(width: 7, height: 7)
                            .offset(x: 4, y: -3)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(Motion.spring, value: asking)
        }
        .accessibilityLabel(engine.blendOn
            ? t("Сведение") + " · " + t(BlendView.buttonLabel(on: true, type: engine.settings().type))
            : t("Сведение"))
    }

    /// Низ (`player.jpg`): слева капсула ♥ · + · ⤓, справа — T (текст) и ползунки (скорость).
    private var bottomRow: some View {
        HStack {
            if let track = engine.current {
                HStack(spacing: 26) {
                    Button { withAnimation(Motion.spring) { library.toggleLike(track) } } label: {
                        SonarIcon(.heart, filled: library.isLiked(track), size: 26)
                            .foregroundStyle(library.isLiked(track) ? Theme.accent : Theme.text)
                            .scaleEffect(library.isLiked(track) ? 1.08 : 1)
                    }
                    .accessibilityLabel(library.isLiked(track) ? "Убрать из Любимых" : "В Любимые")
                    Button {
                        engine.message = "Свои плейлисты Sonar появятся вместе с сервером"
                    } label: { SonarIcon(.plus, size: 26) }
                        .accessibilityLabel("В плейлист")
                    downloadButton(track)
                }
                .padding(.horizontal, 22)
                .frame(height: 52)
                .background(.ultraThinMaterial, in: Capsule())
            }
            Spacer()
            HStack(spacing: 20) {
                Button { showDevices = true } label: {
                    SonarIcon(.computer, size: 26)
                        .foregroundStyle(Theme.text)
                }
                .accessibilityLabel(t("Где играть"))
                // T: тап — текст, зажать — меню текста
                SonarIcon(.letterT, size: 26)
                    .foregroundStyle(lyricsStore.lyrics != nil && lyricsStore.trackRef == engine.current?.ref
                        ? Theme.text : Theme.textTertiary)
                    .frame(width: 26, height: 44)
                    .contentShape(Rectangle())
                    .onTapGesture { Haptics.tap(); showLyrics = true }
                    .onLongPressGesture(minimumDuration: 0.45) {
                        Haptics.hold()
                        showLyricsMenu = true
                    }
                    .accessibilityElement()
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("Текст песни")
                    .accessibilityAction(named: "Меню текста") { showLyricsMenu = true }
                blendButton
                Button { showSpeed = true } label: {
                    SonarIcon(.sliders, size: 26)
                        .foregroundStyle(engine.rate == 1 && engine.sleep == nil ? Theme.text : Theme.accent)
                        // включён таймер сна — луна в углу
                        .overlay(alignment: .topTrailing) {
                            if engine.sleep != nil {
                                SonarIcon(.moon, filled: true, size: 12)
                                    .foregroundStyle(Theme.accent)
                                    .offset(x: 7, y: -6)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .animation(Motion.spring, value: engine.sleep != nil)
                }
                .accessibilityLabel(engine.rate == 1 ? "Скорость и таймер сна" : "Скорость \(String(format: "%g", engine.rate))×, таймер сна")
            }
            .padding(.horizontal, 22)
            .frame(height: 52)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .foregroundStyle(Theme.text)
        .buttonStyle(PressableStyle(scale: 0.9))
    }

    /// ⤓: скачать / качается (кольцо) / скачан (заливка, тап — удалить).
    private func downloadButton(_ track: Track) -> some View {
        let downloads = DownloadStore.shared
        return Button {
            if downloads.isDownloaded(track.ref) {
                downloads.remove(track.ref)
                engine.message = "Загрузка удалена"
            } else if downloads.progress[track.ref] == nil {
                downloads.download(track)
            }
        } label: {
            ZStack {
                if let progress = downloads.progress[track.ref] {
                    Circle().stroke(Theme.text.opacity(0.2), lineWidth: 2.5)
                    Circle().trim(from: 0, to: progress)
                        .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                } else {
                    SonarIcon(.download, filled: downloads.isDownloaded(track.ref), size: 26)
                        .foregroundStyle(downloads.isDownloaded(track.ref) ? Theme.accent : Theme.text)
                }
            }
            .frame(width: 26, height: 26)
        }
        .accessibilityLabel(downloads.isDownloaded(track.ref) ? "Удалить загрузку" : "Скачать")
    }

    static func time(_ seconds: Double) -> String {
        let total = Int(max(0, seconds.isFinite ? seconds : 0))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Скорость (`photo_30`): крупно 1.0×, кнопки 0.75 · 1 · 1.25 · 1.5 · 2, шаги ползунком, «Запомнить» для трека.
/// Лист скорости: скорость, тон (свой или связанный со скоростью — slowed), реверб, «Для этого трека» и таймер
/// сна. Звук трека запоминается вместе с кривой эквалайзера и едет на все устройства (`TrackSound`).
struct SpeedSheet: View {
    @Environment(PlaybackEngine.self) private var engine
    @Environment(SettingsStore.self) private var settings
    private let presets: [Float] = [0.75, 1, 1.25, 1.5, 2]

    /// 1 → «1.0×», 1.25 → «1.25×», 1.5 → «1.5×».
    static func label(_ rate: Float) -> String {
        let text = String(format: "%.2f", rate)
        return (text.hasSuffix("0") ? String(text.dropLast()) : text) + "×"
    }

    var body: some View {
        ScrollView {
        VStack(spacing: 18) {
            Text(Self.label(engine.rate))
                .font(.system(size: 54, weight: .heavy).monospacedDigit())
                .foregroundStyle(Theme.text)
                .contentTransition(.numericText(value: Double(engine.rate)))
                .padding(.top, 22)
            HStack(spacing: 8) {
                ForEach(presets, id: \.self) { value in
                    Button { withAnimation(Motion.spring) { engine.setRate(value) } } label: {
                        Text(String(format: "%g×", value))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(engine.rate == value ? Theme.accentInk : Theme.text)
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .background(engine.rate == value ? AnyShapeStyle(Theme.text) : AnyShapeStyle(Color.white.opacity(0.08)), in: Capsule())
                    }
                    .buttonStyle(PressableStyle(scale: 0.92))
                }
            }
            // скорость — «барабан», как на ПК: шаг 0.01, деление каждые 0.05, подпись каждые 0.25
            DrumRuler(value: Double(engine.rate), range: 0.5 ... 2, step: 0.01, medium: 5, major: 25,
                      label: { String(format: "%g×", $0) }, reset: 1) { engine.setRate(Float($0)) }
                .accessibilityLabel(t("Скорость"))
            tempoControls
            // таймер сна — только с настройкой `player.sleep_button` (выключили — запущенный отменяется)
            if settings.bool("player.sleep_button") {
                SleepTimerSection()
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 24)
        .animation(Motion.spring, value: engine.rate)
        .animation(Motion.spring, value: engine.reverb > 0)
        .animation(Motion.spring, value: engine.hasTrackSound)
        }
        .scrollIndicators(.hidden)
    }

    /// Сила реверба, к которой он вернётся, когда его снова включат.
    @State private var reverbStrength = 0.35

    /// Тон, связь тона со скоростью, реверб и «Для этого трека» (как меню скорости ПК, `SpeedButton.svelte`).
    @ViewBuilder
    private var tempoControls: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(t("Тон"))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.text)
                Spacer()
                stepButton(.dash, label: t("Тон ниже")) { engine.setPitch(engine.semitones - 0.5) }
                Text(Self.pitchLabel(engine.semitones))
                    .font(.system(size: 16, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.text)
                    .contentTransition(.numericText(value: engine.semitones))
                    .frame(minWidth: 66)
                    .onTapGesture(count: 2) { withAnimation(Motion.spring) { engine.setPitch(0) } }
                stepButton(.plus, label: t("Тон выше")) { engine.setPitch(engine.semitones + 0.5) }
            }
            .padding(.top, 8)
            .animation(Motion.spring, value: engine.semitones)
            // тон — «барабан»: шаг 0.1 пт, деление каждые 0.5, подпись каждый полутон
            DrumRuler(value: engine.semitones, range: -12 ... 12, step: 0.1, medium: 5, major: 10,
                      label: { st in
                          let n = Int(st.rounded())
                          return n == 0 ? "0" : (n > 0 ? "+" : "−") + "\(abs(n))"
                      }) { engine.setPitch($0) }
                .accessibilityLabel(t("Тон"))
                .padding(.bottom, 10)
            Divider().overlay(Theme.line)
            toggleRow(t("Связать тон со скоростью"), t("Slowed / sped up: скорость меняет высоту звука"),
                      isOn: Binding(get: { engine.pitchLinked }, set: { engine.setPitchLinked($0) }))
            Divider().overlay(Theme.line)
            toggleRow(t("Реверберация"), t("Атмосферное пространство и объёмная глубина"),
                      isOn: Binding(get: { engine.reverb > 0 }, set: { on in
                          engine.setReverb(on ? max(0.05, reverbStrength) : 0)
                      }))
            if engine.reverb > 0 {
                HStack(spacing: 12) {
                    // сила реверба — «барабан»: шаг 1 %, подпись каждые 25 %, двойной тап — 35 %, как на ПК
                    DrumRuler(value: engine.reverb, range: 0.01 ... 1, step: 0.01, medium: 5, major: 25,
                              label: { "\(Int(($0 * 100).rounded())) %" }, reset: 0.35, height: 50) { value in
                        reverbStrength = value
                        engine.setReverb(value)
                    }
                    .accessibilityLabel(t("Реверберация"))
                    Text("\(Int((engine.reverb * 100).rounded())) %")
                        .font(.system(size: 14, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                        .contentTransition(.numericText(value: engine.reverb))
                        .frame(width: 48, alignment: .trailing)
                }
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if engine.current != nil {
                Divider().overlay(Theme.line)
                toggleRow(t("Для этого трека"), t("Скорость, тон, реверб и эквалайзер — только у этого трека и на всех твоих устройствах"),
                          isOn: Binding(get: { engine.hasTrackSound }, set: { engine.setTrackSound($0) }))
            }
        }
        .padding(.horizontal, 14)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        // поток HLS AVPlayer играет мимо обработки звука — честно говорим, что из этого слышно
        if engine.isHLS, (!engine.pitchLinked && engine.pitch != 0) || engine.reverb > 0 {
            HintCard(icon: .info, text: t("Этот трек идёт потоком HLS — свой тон и реверб на нём не слышны. Slowed со связанным тоном работает"))
                .transition(.opacity)
        }
    }

    /// −1.5 → «−1.5 st», 0 → «0 st».
    nonisolated static func pitchLabel(_ semitones: Double) -> String {
        let value = (semitones * 10).rounded() / 10
        if value == 0 { return "0 st" }
        return (value > 0 ? "+" : "−") + String(format: "%.1f", abs(value)) + " st"
    }

    private func stepButton(_ icon: IconName, label: String, action: @escaping @MainActor () -> Void) -> some View {
        Button {
            withAnimation(Motion.spring) { action() }
            Haptics.select()
        } label: {
            SonarIcon(icon, size: 16)
                .foregroundStyle(Theme.text)
                .frame(width: 36, height: 36)
                .background(Color.white.opacity(0.08), in: Circle())
        }
        .buttonStyle(PressableStyle(scale: 0.88))
        .accessibilityLabel(label)
    }

    private func toggleRow(_ title: String, _ subtitle: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: Binding(get: { isOn.wrappedValue }, set: { value in
            withAnimation(Motion.spring) { isOn.wrappedValue = value }
            Haptics.select()
        })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.text)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(Theme.accent)
        .padding(.vertical, 10)
    }
}

/// Очередь (`photo_2, 3`): контекст сверху, разделы Ранее · Сейчас играет · Далее, открыт на текущем.
/// Вид строк — `queue.view` (обычный — без обложек), свайпы по «Далее» — Профиль → Жесты → Очередь.
struct QueueSheet: View {
    @Environment(PlaybackEngine.self) private var engine
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    if !engine.history.isEmpty {
                        // «Ранее» — как раздел очереди на странице плеера ПК (одно название на обеих платформах)
                        Section {
                            ForEach(Array(engine.history.enumerated()), id: \.offset) { _, track in
                                row(track).opacity(0.55)
                            }
                        } header: {
                            Text(t("Ранее"))
                        }
                    }
                    if let current = engine.current {
                        Section("Сейчас играет") {
                            row(current, playing: true).id("current")
                        }
                    }
                    Section {
                        // тумблер как в SoundCloud и в панели «Далее» Windows (general.similar_autoplay)
                        Toggle(isOn: Binding(get: { settings.bool("general.similar_autoplay") },
                                             set: { settings.set("general.similar_autoplay", $0) })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Авто похожие").font(.system(size: 15, weight: .medium))
                                Text("Когда очередь кончается — играть похожие").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                            }
                        }
                        .tint(Theme.accent)
                        .listRowBackground(Color.clear)
                    }
                    if !engine.upNext.isEmpty {
                        Section("Далее") {
                            ForEach(Array(engine.upNext.enumerated()), id: \.offset) { index, track in
                                Button { engine.jump(toUpcoming: index) } label: { row(track) }
                                    .buttonStyle(.plain)
                                    .trackSwipe(.queue, track: track, handle: { action in swiped(action, track: track, offset: index) })
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .onAppear { proxy.scrollTo("current", anchor: .top) }
            }
            .navigationTitle(engine.contextTitle.isEmpty ? "Очередь" : engine.contextTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { engine.toggleShuffle() } label: {
                        PlayerToggleIcon(icon: .shuffle, active: engine.shuffle, stateKey: "\(engine.shuffle)", size: 20)
                    }
                    .accessibilityLabel(t("Перемешивание"))
                    .accessibilityValue(RepeatUI.value(of: t(RepeatUI.shuffleKey(engine.shuffle))))
                }
            }
        }
    }

    /// Жест по строке «Далее»: в очереди «следующим» и «в конец» переставляют трек, «удалить» — убирает.
    private func swiped(_ action: GestureAction, track: Track, offset: Int) {
        switch action {
        case .delete:
            withAnimation(Motion.spring) { engine.removeUpcoming(offset) }
            engine.message = "Убрано из очереди: «\(track.title)»"
        case .play_next:
            withAnimation(Motion.spring) { engine.moveUpcoming(offset, toEnd: false) }
            engine.message = "Следующим: «\(track.title)»"
        case .enqueue:
            withAnimation(Motion.spring) { engine.moveUpcoming(offset, toEnd: true) }
            engine.message = "В конце очереди: «\(track.title)»"
        default:
            GestureRunner.perform(action, track: track)
            return
        }
        Haptics.tap()
    }

    private func row(_ track: Track, playing: Bool = false) -> some View {
        let extended = QueueView.current(settings) == .extended
        return HStack(spacing: 12) {
            if extended {
                CoverImage(url: track.coverURL, cornerRadius: 6).frame(width: 42, height: 42)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            } else if playing {
                EqualizerBars(playing: engine.isPlaying, color: Theme.accent)
                    .frame(width: 20)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title).font(.system(size: 15, weight: .medium)).foregroundStyle(playing ? Theme.accent : Theme.text).lineLimit(1)
                Text(track.artist).font(.system(size: 13)).foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
            Spacer()
        }
        .padding(.vertical, extended ? 0 : 2)
        .listRowBackground(Color.clear)
        .contentShape(Rectangle())
        .animation(Motion.spring, value: extended)
    }
}
