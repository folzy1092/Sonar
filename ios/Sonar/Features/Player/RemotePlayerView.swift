import SwiftUI

/// Полный плеер в режиме пульта: показывает и переключает то, что играет на ПК («Играет на …»). Звук —
/// на ПК; позицию досчитываем своими часами между `state`. Повтор и перемешивание — только показываем
/// (их меняют на ПК), очередь «Далее» — тап играет трек на ПК.
struct RemotePlayerView: View {
    @Binding var showDevices: Bool
    @Environment(Router.self) private var router
    @Environment(PlaybackEngine.self) private var engine
    @State private var scrubbing: Double?
    @State private var volume: Double?
    @State private var dragDown: CGFloat = 0

    private var remote: RemoteControl { RemoteControl.shared }
    /// Обновление позиции на экране.
    private static let tick: TimeInterval = 0.5

    var body: some View {
        let state = remote.state
        ZStack {
            backdrop(state?.track)
            ScrollView {
                VStack(spacing: 0) {
                    topBar
                    cover(state?.track)
                        .padding(.top, 18)
                    titleBlock(state)
                        .padding(.top, 22)
                    if let state, state.track != nil {
                        TimelineView(.periodic(from: .now, by: Self.tick)) { context in
                            progress(state, now: context.date)
                        }
                        .padding(.top, 18)
                    }
                    controls(state)
                        .padding(.top, 16)
                    volumeRow(state)
                        .padding(.top, 16)
                    queue(state)
                        .padding(.top, 22)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
        }
        .offset(y: max(0, dragDown))
        .overlay(alignment: .top) { toast }
        .animation(Motion.spring, value: engine.message)
        .animation(Motion.spring, value: state?.track?.ref)
        .animation(Motion.spring, value: remote.isConnected)
        .onAppear { remote.reconnectIfNeeded() }
    }

    private func close() {
        router.playerOpen = false
    }

    private func backdrop(_ track: Track?) -> some View {
        ZStack {
            Theme.background
            CoverImage(url: track?.coverURL, cornerRadius: 0)
                .blur(radius: 60)
                .opacity(0.55)
                .id(track?.ref)
                .transition(.opacity)
            LinearGradient(colors: [.clear, Theme.scrim.opacity(0.75)], startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
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
            HStack(spacing: 8) {
                SonarIcon(.computer, size: 15)
                Text(t("Играет на {name}", ["name": remote.pcName]))
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                if !remote.isConnected {
                    ProgressView().controlSize(.mini).tint(Theme.text)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 16)
            .frame(height: 40)
            .background(.ultraThinMaterial, in: Capsule())
            Spacer()
            deviceButton
        }
    }

    private var deviceButton: some View {
        Button { showDevices = true } label: {
            SonarIcon(.computer, filled: true, size: 24)
                .foregroundStyle(Theme.accent)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(PressableStyle(scale: 0.88))
        .accessibilityLabel(t("Где играть"))
    }

    private func cover(_ track: Track?) -> some View {
        ZStack {
            if let track {
                CoverImage(url: track.coverURL, cornerRadius: 22)
                    .id(track.ref)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            } else {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Theme.card)
                    .overlay { SonarIcon(.computer, size: 64).foregroundStyle(Theme.textTertiary) }
                    .transition(.opacity)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 340)
        .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
        .gesture(
            // вниз — закрыть плеер, как у обычного
            DragGesture(minimumDistance: 20)
                .onChanged { value in dragDown = max(0, value.translation.height) }
                .onEnded { value in
                    if value.translation.height > 140 { close() }
                    withAnimation(Motion.spring) { dragDown = 0 }
                }
        )
    }

    private func titleBlock(_ state: RemoteState?) -> some View {
        VStack(spacing: 6) {
            if let track = state?.track {
                Text(track.title)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .textSelection(.enabled)
                Text(track.artist)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
            } else {
                Text(t("На ПК ничего не играет"))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .id(state?.track?.ref ?? "")
        .transition(.opacity.combined(with: .offset(y: 8)))
    }

    private func progress(_ state: RemoteState, now: Date) -> some View {
        let duration = max(state.duration, 1)
        let position = scrubbing ?? remote.position(at: now)
        return VStack(spacing: 6) {
            Slider(value: Binding(get: { min(position, duration) }, set: { scrubbing = $0 }), in: 0...duration) { editing in
                guard !editing, let target = scrubbing else { return }
                remote.send(.seek(ms: Int(target * 1000)))
                scrubbing = nil
            }
            .tint(Theme.accent)
            HStack {
                Text(FullPlayerView.time(position))
                Spacer()
                Text(FullPlayerView.time(state.duration))
            }
            .font(.system(size: 13).monospacedDigit())
            .foregroundStyle(Theme.textSecondary)
        }
    }

    private func controls(_ state: RemoteState?) -> some View {
        let playing = state?.playing ?? false
        let repeatMode = state?.repeatMode ?? .off
        return HStack {
            // повтор и перемешивание меняют на ПК — здесь только видно, что включено
            SonarIcon(repeatMode == .one ? .repeatOne : .repeatAll, size: 24)
                .foregroundStyle(repeatMode == .off ? Theme.textTertiary : Theme.accent)
                .accessibilityLabel(repeatMode == .off ? t("Повтор выключен") : t("Повтор включён"))
            Spacer()
            Button { remote.send(.prev) } label: { SonarIcon(.prev, filled: true, size: 30) }
                .accessibilityLabel(t("Предыдущий"))
            Spacer()
            Button { remote.send(.toggle) } label: {
                SonarIcon(playing ? .pause : .play, filled: true, size: 34)
                    .contentTransition(.opacity)
                    .foregroundStyle(Theme.accentInk)
                    .frame(width: 72, height: 72)
                    .background(Theme.accent, in: Circle())
                    .shadow(color: Theme.glow.opacity(0.4), radius: 16, y: 4)
            }
            .accessibilityLabel(playing ? t("Пауза") : t("Играть"))
            Spacer()
            Button { remote.send(.next) } label: { SonarIcon(.next, filled: true, size: 30) }
                .accessibilityLabel(t("Следующий"))
            Spacer()
            SonarIcon(.shuffle, size: 24)
                .foregroundStyle(state?.shuffle == true ? Theme.accent : Theme.textTertiary)
                .accessibilityLabel(state?.shuffle == true ? t("Перемешивание включено") : t("Перемешивание выключено"))
        }
        .foregroundStyle(Theme.text)
        .buttonStyle(PressableStyle(scale: 0.88))
        .padding(.horizontal, 22)
        .frame(height: 88)
        .background(.ultraThinMaterial, in: Capsule())
        .disabled(!remote.isConnected)
        .opacity(remote.isConnected ? 1 : 0.6)
        .animation(Motion.spring, value: playing)
    }

    private func volumeRow(_ state: RemoteState?) -> some View {
        let liked = state?.liked ?? false
        return HStack(spacing: 16) {
            if let track = state?.track {
                Button {
                    remote.send(.like(ref: track.ref, value: !liked))
                } label: {
                    SonarIcon(.heart, filled: liked, size: 26)
                        .foregroundStyle(liked ? Theme.accent : Theme.text)
                        .scaleEffect(liked ? 1.08 : 1)
                }
                .buttonStyle(PressableStyle(scale: 0.85))
                .accessibilityLabel(liked ? t("Убрать из Любимых") : t("В Любимые"))
                .transition(.scale.combined(with: .opacity))
            }
            SonarIcon(.volume, size: 20)
                .foregroundStyle(Theme.textSecondary)
            Slider(value: Binding(get: { volume ?? state?.volume ?? 1 }, set: { volume = $0 }), in: 0...1) { editing in
                guard !editing, let value = volume else { return }
                remote.send(.volume(value))
                volume = nil
            }
            .tint(Theme.text)
            .accessibilityLabel(t("Громкость на ПК"))
        }
        .padding(.horizontal, 22)
        .frame(height: 56)
        .background(.ultraThinMaterial, in: Capsule())
        .disabled(!remote.isConnected)
        .animation(Motion.spring, value: liked)
    }

    @ViewBuilder
    private func queue(_ state: RemoteState?) -> some View {
        let upNext = state?.queue ?? []
        VStack(alignment: .leading, spacing: 4) {
            if upNext.isEmpty {
                Button { remote.send(.playWave) } label: {
                    HStack(spacing: 10) {
                        SonarIcon(.wave, size: 22)
                        Text(t("Моя волна на ПК"))
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(.ultraThinMaterial, in: Capsule())
                }
                .buttonStyle(PressableStyle())
                .disabled(!remote.isConnected)
                .transition(.opacity)
            } else {
                Text(state?.contextTitle.flatMap { $0.isEmpty ? nil : t("Далее · {name}", ["name": $0]) } ?? t("Далее"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.bottom, 6)
                ForEach(Array(upNext.enumerated()), id: \.offset) { index, track in
                    Button { remote.send(.queuePlayIndex(index)) } label: { queueRow(track) }
                        .buttonStyle(PressableStyle())
                        .disabled(!remote.isConnected)
                }
            }
        }
        .animation(Motion.spring, value: upNext.map(\.ref))
    }

    private func queueRow(_ track: Track) -> some View {
        HStack(spacing: 12) {
            CoverImage(url: track.coverURL, cornerRadius: 8)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(track.artist)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(FullPlayerView.time(Double(track.durationMs) / 1000))
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var toast: some View {
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
}

/// Мини-плеер в режиме пульта: обложка трека ПК в кольце прогресса, название и «Играет на <ПК>», пауза.
/// Тап — полный плеер пульта.
struct RemoteMiniPlayer: View {
    var compact = false
    let open: @MainActor () -> Void

    private var remote: RemoteControl { RemoteControl.shared }

    var body: some View {
        let state = remote.state
        let playing = state?.playing ?? false
        HStack(spacing: compact ? 10 : 12) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                CoverRing(url: state?.track?.coverURL, progress: fraction(state, now: context.date),
                          side: compact ? 42 : 48, loading: !remote.isConnected)
            }
            .id(state?.track?.ref)
            .transition(.scale(scale: 0.7).combined(with: .opacity))
            VStack(alignment: .leading, spacing: 1) {
                MarqueeText(text: state?.track?.title ?? t("На ПК ничего не играет"),
                            font: .system(size: compact ? 16 : 17, weight: .medium), color: Theme.text)
                HStack(spacing: 5) {
                    SonarIcon(.computer, size: compact ? 12 : 13)
                    Text(t("Играет на {name}", ["name": remote.pcName]))
                        .lineLimit(1)
                }
                .font(.system(size: compact ? 13 : 14, weight: .medium))
                .foregroundStyle(Theme.accent)
            }
            .id(state?.track?.ref)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            Spacer(minLength: 0)
            Button {
                remote.send(.toggle)
            } label: {
                SonarIcon(playing ? .pause : .play, filled: true, size: 26)
                    .foregroundStyle(Theme.text)
                    .contentTransition(.opacity)
                    .frame(width: 44, height: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle(scale: 0.82))
            .accessibilityLabel(playing ? t("Пауза") : t("Играть"))
        }
        .padding(.leading, compact ? 7 : 9)
        .padding(.trailing, compact ? 6 : 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .animation(Motion.spring, value: state?.track?.ref)
        .animation(Motion.spring, value: playing)
    }

    private func fraction(_ state: RemoteState?, now: Date) -> Double {
        guard let state, state.duration > 0 else { return 0 }
        return min(1, max(0, remote.position(at: now) / state.duration))
    }
}
