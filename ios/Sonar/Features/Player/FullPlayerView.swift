import SwiftUI

/// Полный плеер (`reference/mobile/player.jpg`): сверху ⌄ · контекст «❤ Любимые ⤮» · ⋮, обложка на весь
/// фон с затемнением к низу, название и исполнитель (выделяются и копируются), ползунок, время и «Далее»,
/// кнопки в капсуле (повтор · назад · пауза · вперёд · перемешать), снизу лайк и скорость. Свайп вниз
/// закрывает.
struct FullPlayerView: View {
    @Environment(PlaybackEngine.self) private var engine
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var scrubbing: Double?
    @State private var showQueue = false
    @State private var showSpeed = false
    @State private var dragDown: CGFloat = 0

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 20)
                if let track = engine.current {
                    titleBlock(track)
                        .id(track.ref)
                        .transition(.opacity.combined(with: .offset(y: 8)))
                }
                slider
                    .padding(.top, 22)
                timeRow
                    .padding(.top, 8)
                controls
                    .padding(.top, 18)
                bottomRow
                    .padding(.top, 14)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 10)
        }
        .offset(y: max(0, dragDown))
        .gesture(
            DragGesture()
                .onChanged { dragDown = $0.translation.height }
                .onEnded { value in
                    if value.translation.height > 140 { dismiss() } else { withAnimation(Motion.spring) { dragDown = 0 } }
                }
        )
        .animation(Motion.spring, value: engine.current?.ref)
        .sheet(isPresented: $showQueue) {
            QueueSheet()
                .presentationDetents([.large])
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showSpeed) {
            SpeedSheet()
                .presentationDetents([.height(330)])
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
    }

    /// Обложка на весь экран, к низу — в чёрный.
    private var background: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                Color.black
                CoverImage(url: engine.current?.coverURL, cornerRadius: 0)
                    .frame(width: proxy.size.width, height: proxy.size.height * 0.72)
                    .frame(maxHeight: .infinity, alignment: .top)
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
            Button { dismiss() } label: {
                SonarIcon(.chevronDown, size: 28)
                    .foregroundStyle(Theme.text)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(PressableStyle(scale: 0.88))
            Spacer()
            Button { showQueue = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "heart.fill").font(.system(size: 13))
                    Text(engine.contextTitle.isEmpty ? "Очередь" : engine.contextTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    if engine.shuffle {
                        Image(systemName: "shuffle")
                            .font(.system(size: 10, weight: .bold))
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
            Button { showQueue = true } label: {
                SonarIcon(.more, size: 26)
                    .foregroundStyle(Theme.text)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(PressableStyle(scale: 0.88))
        }
    }

    private func titleBlock(_ track: Track) -> some View {
        VStack(spacing: 6) {
            Text(track.title)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .textSelection(.enabled)
            HStack(spacing: 6) {
                if let avatar = track.artists.first?.avatarURL {
                    CoverImage(url: avatar, cornerRadius: 10)
                        .frame(width: 20, height: 20)
                }
                Text(track.artist)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
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
        }
        .frame(maxWidth: .infinity)
        .animation(Motion.spring, value: engine.quality)
    }

    private var slider: some View {
        GeometryReader { proxy in
            let value = scrubbing ?? engine.position
            let fraction = engine.duration > 0 ? min(1, max(0, value / engine.duration)) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.22))
                Capsule().fill(Color.white).frame(width: proxy.size.width * fraction)
            }
            .frame(height: scrubbing == nil ? 4 : 8)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        withAnimation(Motion.quick) {
                            scrubbing = max(0, min(1, drag.location.x / proxy.size.width)) * engine.duration
                        }
                    }
                    .onEnded { _ in
                        if let scrubbing { engine.seek(to: scrubbing) }
                        withAnimation(Motion.quick) { scrubbing = nil }
                    }
            )
        }
        .frame(height: 24)
    }

    private var timeRow: some View {
        HStack {
            Text(Self.time(scrubbing ?? engine.position))
            Spacer()
            if let next = engine.upNext.first {
                Button { engine.next() } label: {
                    HStack(spacing: 6) {
                        CoverImage(url: next.coverURL, cornerRadius: 4).frame(width: 20, height: 20)
                        Text(next.title).lineLimit(1).frame(maxWidth: 110)
                        Text("Далее").foregroundStyle(Theme.textSecondary)
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(.ultraThinMaterial, in: Capsule())
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

    private var controls: some View {
        HStack {
            Button { engine.cycleRepeat() } label: {
                SonarIcon(engine.repeatMode == .one ? .repeatOne : .repeatAll, size: 26)
                    .foregroundStyle(engine.repeatMode == .off ? Theme.textSecondary : Theme.accent)
            }
            Spacer()
            Button { engine.previous() } label: { SonarIcon(.prev, filled: true, size: 30) }
            Spacer()
            Button { engine.toggle() } label: {
                SonarIcon(engine.isPlaying ? .pause : .play, filled: true, size: 34)
                    .foregroundStyle(Theme.accentInk)
                    .contentTransition(.opacity)
                    .frame(width: 72, height: 72)
                    .background(Theme.accent, in: Circle())
                    .shadow(color: Theme.glow.opacity(0.4), radius: 16, y: 4)
            }
            Spacer()
            Button { engine.next() } label: { SonarIcon(.next, filled: true, size: 30) }
            Spacer()
            Button { engine.toggleShuffle() } label: {
                SonarIcon(.shuffle, size: 26)
                    .foregroundStyle(engine.shuffle ? Theme.accent : Theme.textSecondary)
            }
        }
        .font(.system(size: 22))
        .foregroundStyle(Theme.text)
        .buttonStyle(PressableStyle(scale: 0.88))
        .padding(.horizontal, 22)
        .frame(height: 88)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var bottomRow: some View {
        HStack {
            HStack(spacing: 22) {
                if let track = engine.current {
                    Button { withAnimation(Motion.spring) { library.toggleLike(track) } } label: {
                        SonarIcon(.heart, filled: library.isLiked(track), size: 26)
                            .foregroundStyle(library.isLiked(track) ? Theme.accent : Theme.text)
                            .scaleEffect(library.isLiked(track) ? 1.08 : 1)
                    }
                }
                Button { showQueue = true } label: { SonarIcon(.queue, size: 26) }
            }
            .padding(.horizontal, 20)
            .frame(height: 50)
            .background(.ultraThinMaterial, in: Capsule())
            Spacer()
            Button { showSpeed = true } label: {
                Text(engine.rate == 1 ? "1×" : String(format: "%g×", engine.rate))
                    .font(.system(size: 15, weight: .semibold).monospacedDigit())
                    .foregroundStyle(engine.rate == 1 ? Theme.text : Theme.accent)
                    .padding(.horizontal, 20)
                    .frame(height: 50)
                    .background(.ultraThinMaterial, in: Capsule())
            }
        }
        .font(.system(size: 20))
        .foregroundStyle(Theme.text)
        .buttonStyle(PressableStyle(scale: 0.9))
    }

    static func time(_ seconds: Double) -> String {
        let total = Int(max(0, seconds.isFinite ? seconds : 0))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Скорость (`photo_30`): крупно 1.0×, кнопки 0.75 · 1 · 1.25 · 1.5 · 2, шаги ползунком, «Запомнить» для трека.
struct SpeedSheet: View {
    @Environment(PlaybackEngine.self) private var engine
    @Environment(LibraryStore.self) private var library
    private let presets: [Float] = [0.75, 1, 1.25, 1.5, 2]

    /// 1 → «1.0×», 1.25 → «1.25×», 1.5 → «1.5×».
    static func label(_ rate: Float) -> String {
        let text = String(format: "%.2f", rate)
        return (text.hasSuffix("0") ? String(text.dropLast()) : text) + "×"
    }
    private let steps: [Float] = stride(from: 0.5, through: 2, by: 0.25).map { Float($0) }

    var body: some View {
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
            HStack(spacing: 2) {
                ForEach(steps, id: \.self) { value in
                    Rectangle()
                        .fill(value <= engine.rate ? Color.white.opacity(0.85) : Color.white.opacity(0.1))
                        .frame(height: 28)
                        .onTapGesture { withAnimation(Motion.spring) { engine.setRate(value) } }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            if let track = engine.current {
                let remembered = library.speed(for: track.ref) != nil
                Button {
                    withAnimation(Motion.spring) {
                        library.rememberSpeed(remembered ? nil : engine.rate, for: track.ref)
                    }
                } label: {
                    Label(remembered ? "Запомнено для трека" : "Запомнить", systemImage: remembered ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(remembered ? Theme.accent : Theme.text)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.line))
                }
                .buttonStyle(PressableStyle())
            }
        }
        .padding(.horizontal, 18)
        .animation(Motion.spring, value: engine.rate)
    }
}

/// Очередь (`photo_2, 3`): контекст сверху, разделы Предыдущие · Сейчас играет · Далее, открыт на текущем.
struct QueueSheet: View {
    @Environment(PlaybackEngine.self) private var engine
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    if !engine.history.isEmpty {
                        Section("Предыдущие") {
                            ForEach(Array(engine.history.enumerated()), id: \.offset) { _, track in
                                row(track).opacity(0.55)
                            }
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
                        Image(systemName: "shuffle").foregroundStyle(engine.shuffle ? Theme.accent : Theme.textSecondary)
                    }
                }
            }
        }
    }

    private func row(_ track: Track, playing: Bool = false) -> some View {
        HStack(spacing: 12) {
            CoverImage(url: track.coverURL, cornerRadius: 6).frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title).font(.system(size: 15, weight: .medium)).foregroundStyle(playing ? Theme.accent : Theme.text).lineLimit(1)
                Text(track.artist).font(.system(size: 13)).foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
            Spacer()
        }
        .listRowBackground(Color.clear)
        .contentShape(Rectangle())
    }
}
