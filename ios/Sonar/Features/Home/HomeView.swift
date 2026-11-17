import SwiftUI

/// Главная (`IMG_6764`, `IMG_6765`, `photo_5`): знак Sonar и колокольчик, поле точек «Моей волны»,
/// заголовок с вопросом под время суток и большая кнопка, подборки «Для вас» и «Открытия» (мозаика из
/// четырёх обложек), «Недавнее» страницами по четыре трека, «Релизы». Данные — `HomeFeed` и
/// `PlayHistory` (на телефоне, без сервера).
struct HomeView: View {
    var active: Bool
    @Environment(PlaybackEngine.self) private var engine
    @Environment(ChromeState.self) private var chrome
    @Environment(Router.self) private var router
    @Environment(UpdateChecker.self) private var checker
    @Environment(LibraryStore.self) private var library
    @State private var showUpdate = false
    @State private var showModes = false
    private var feed: HomeFeed { HomeFeed.shared }
    private var history: PlayHistory { PlayHistory.shared }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                DotField(active: active && !showModes, playing: myWavePlaying, color: Theme.accent) {
                    showModes = true
                }
                    .frame(height: 290)
                    .padding(.horizontal, -Theme.gutter)
                    .padding(.top, 4)
                waveTitle
                    .padding(.top, 6)
                mixes
                    .padding(.top, 34)
                recent
                    .padding(.top, 34)
                releases
                    .padding(.top, 30)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 170)
        }
        .scrollIndicators(.hidden)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, offset in
            if active { chrome.scrolled(to: offset) }
        }
        .refreshable { await feed.refresh(force: true) }
        .animation(Motion.spring, value: engine.waveMode)
        .background(Theme.background.ignoresSafeArea())
        .task { await feed.refresh() }
        .onChange(of: library.liked.count) { Task { await feed.refresh() } }
        .sheet(isPresented: $showModes) {
            WaveModeSheet()
                .presentationDetents([.height(440)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(30)
                .presentationBackground(Theme.background)
        }
        .sheet(isPresented: $showUpdate) {
            NavigationStack { UpdateView() }
                .presentationBackground(Theme.background)
        }
    }

    // MARK: - Шапка и волна

    private var header: some View {
        HStack {
            LogoMark(size: 34)
                .foregroundStyle(Theme.accent)
            Spacer()
            Button {
                if checker.available != nil {
                    showUpdate = true
                } else {
                    router.say("Уведомлений пока нет")
                }
            } label: {
                SonarIcon(.bell, filled: true, size: 28)
                    .foregroundStyle(Theme.accent)
                    .overlay(alignment: .topTrailing) {
                        if checker.available != nil {
                            Circle().fill(Theme.danger).frame(width: 9, height: 9).offset(x: 2, y: -1)
                        }
                    }
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(PressableStyle(scale: 0.88))
            .accessibilityLabel("Уведомления")
        }
        .padding(.top, 8)
    }

    private var waveTitle: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Моя волна")
                    .font(.system(size: 42, weight: .black).width(.expanded))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(Self.question(Date()))
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.textSecondary)
                    .lineSpacing(2)
                if engine.waveMode != .own {
                    Button { showModes = true } label: {
                        HStack(spacing: 6) {
                            SonarIcon(WaveModeSheet.icon(engine.waveMode), filled: true, size: 15)
                            Text(engine.waveMode.title)
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(Theme.accentSoft, in: Capsule())
                    }
                    .buttonStyle(PressableStyle())
                    .padding(.top, 4)
                    .transition(.scale(scale: 0.8, anchor: .leading).combined(with: .opacity))
                }
            }
            Spacer(minLength: 8)
            Button {
                // сама ставит на паузу / продолжает, если «Моя волна» уже играет
                engine.playMyWave()
            } label: {
                ZStack {
                    if engine.waveLoading {
                        ProgressView().tint(Theme.accentInk).scaleEffect(1.2)
                    } else {
                        SonarIcon(myWavePlaying ? .pause : .play, filled: true, size: 34)
                            .foregroundStyle(Theme.accentInk)
                            .transition(.opacity)
                    }
                }
                    .frame(width: 70, height: 70)
                    .background(Theme.accent, in: Circle())
                    .shadow(color: Theme.glow.opacity(0.45), radius: 18, y: 6)
            }
            .buttonStyle(PressableStyle(scale: 0.9))
            .accessibilityLabel(myWavePlaying ? "Пауза" : "Включить Мою волну")
        }
    }

    /// Играет именно «Моя волна» (не «Волна по треку»).
    private var myWavePlaying: Bool {
        engine.isWave && engine.waveSeed == nil && engine.isPlaying
    }

    /// «Что включим этим утром?» — по времени суток.
    static func question(_ date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5 ..< 12: return "Что включим\nэтим утром?"
        case 12 ..< 18: return "Что включим\nэтим днём?"
        case 18 ..< 23: return "Что включим\nэтим вечером?"
        default: return "Что включим\nэтой ночью?"
        }
    }

    // MARK: - Подборки

    @ViewBuilder
    private var mixes: some View {
        if feed.forYou.isEmpty, feed.discoveries.isEmpty {
            if feed.loading {
                HStack(spacing: 16) {
                    MosaicPlaceholder()
                    MosaicPlaceholder()
                }
            } else {
                HintCard(icon: .heart, text: "Лайкни пару треков — здесь появятся подборки «Для вас» и «Открытия»")
            }
        } else {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    if !feed.forYou.isEmpty {
                        MosaicCard(title: "Для вас", subtitle: feed.subtitle(feed.forYou), tracks: feed.forYou) {
                            engine.play(feed.forYou, at: 0, context: "Для вас")
                        }
                        .cascade(0)
                    }
                    if !feed.discoveries.isEmpty {
                        MosaicCard(title: "Открытия", subtitle: feed.subtitle(feed.discoveries), tracks: feed.discoveries) {
                            engine.play(feed.discoveries, at: 0, context: "Открытия")
                        }
                        .cascade(1)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .scrollTargetBehavior(.viewAligned)
        }
    }

    // MARK: - Недавнее

    @ViewBuilder
    private var recent: some View {
        let tracks = Array(history.recent.prefix(16))
        if !tracks.isEmpty {
            RecentPager(tracks: tracks) {
                router.push(.recent, on: .home, chrome: chrome)
            }
        }
    }

    // MARK: - Релизы

    @ViewBuilder
    private var releases: some View {
        if !feed.releases.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("Релизы")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Theme.text)
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(Array(feed.releases.prefix(20).enumerated()), id: \.element.ref) { index, album in
                            ReleaseCard(album: album) {
                                router.push(.album(ref: album.ref, title: album.title), on: .home, chrome: chrome)
                            }
                            .cascade(index)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
                .scrollTargetBehavior(.viewAligned)
            }
        }
    }
}

/// Подборка: мозаика из четырёх обложек, название широким шрифтом, первые артисты.
struct MosaicCard: View {
    let title: String
    let subtitle: String
    let tracks: [Track]
    let action: @MainActor () -> Void

    static let side: CGFloat = 158

    private var covers: [String?] {
        var seen = Set<String>()
        var out: [String?] = []
        for track in tracks {
            guard let cover = track.coverURL, !seen.contains(cover) else { continue }
            seen.insert(cover)
            out.append(cover)
            if out.count == 4 { break }
        }
        while out.count < 4 { out.append(nil) }
        return out
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                let half = Self.side / 2
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        CoverImage(url: covers[0], cornerRadius: 0).frame(width: half, height: half)
                        CoverImage(url: covers[1], cornerRadius: 0).frame(width: half, height: half)
                    }
                    HStack(spacing: 0) {
                        CoverImage(url: covers[2], cornerRadius: 0).frame(width: half, height: half)
                        CoverImage(url: covers[3], cornerRadius: 0).frame(width: half, height: half)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.bottom, 8)
                Text(title)
                    .font(.system(size: 19, weight: .heavy).width(.expanded))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            .frame(width: Self.side, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.96))
    }
}

/// Заглушка подборки, пока грузится: мягко мерцает.
struct MosaicPlaceholder: View {
    @State private var dim = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.raised)
                .frame(width: MosaicCard.side, height: MosaicCard.side)
            Capsule().fill(Theme.raised).frame(width: 90, height: 14)
            Capsule().fill(Theme.raised).frame(width: 130, height: 12)
        }
        .opacity(dim ? 0.45 : 0.9)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { dim = true }
        }
    }
}

/// Подсказка вместо пустого раздела.
struct HintCard: View {
    let icon: IconName
    let text: String

    var body: some View {
        HStack(spacing: 14) {
            SonarIcon(icon, filled: true, size: 26)
                .foregroundStyle(Theme.accent)
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(18)
        .background(Theme.raised.opacity(0.6), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }
}

/// «Недавнее ›» — страницы по четыре трека, листаются вбок, справа точки страниц.
struct RecentPager: View {
    let tracks: [Track]
    let openAll: @MainActor () -> Void
    @Environment(PlaybackEngine.self) private var engine
    @State private var page: Int? = 0

    private var pages: [[Track]] {
        stride(from: 0, to: tracks.count, by: 4).map { Array(tracks[$0 ..< min($0 + 4, tracks.count)]) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button(action: openAll) {
                    HStack(spacing: 8) {
                        Text("Недавнее")
                            .font(.system(size: 30, weight: .semibold))
                        SonarIcon(.chevronRight, size: 22)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .foregroundStyle(Theme.text)
                }
                .buttonStyle(PressableStyle())
                Spacer()
                if pages.count > 1 {
                    PageDots(count: pages.count, current: page ?? 0)
                }
            }
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, list in
                        VStack(spacing: 4) {
                            ForEach(Array(list.enumerated()), id: \.element.ref) { row, track in
                                TrackRow(track: track, playing: engine.current?.ref == track.ref) {
                                    engine.play(tracks, at: index * 4 + row, context: "Недавнее")
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, Theme.gutter)
                        .containerRelativeFrame(.horizontal)
                        .id(index)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $page)
            .padding(.horizontal, -Theme.gutter)
        }
    }
}

/// Точки страниц: текущая — вытянутая капсула.
struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0 ..< count, id: \.self) { i in
                Capsule()
                    .fill(i == current ? Theme.text : Theme.textTertiary.opacity(0.6))
                    .frame(width: i == current ? 22 : 7, height: 7)
            }
        }
        .animation(Motion.spring, value: current)
    }
}

/// Релиз: обложка и название, под ней артист.
struct ReleaseCard: View {
    let album: Album
    let action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                CoverImage(url: album.coverURL, cornerRadius: 18)
                    .frame(width: MosaicCard.side, height: MosaicCard.side)
                    .padding(.bottom, 6)
                Text(album.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(album.artist)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            .frame(width: MosaicCard.side, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.96))
    }
}
