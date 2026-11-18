import SwiftUI
import UIKit

/// Итоги одного периода: подсчёт из журнала (`RecapEngine`, вне главного потока), цвета — из обложки
/// первого трека топа, обложки и аватары — заранее, чтобы `ImageRenderer` нарисовал их на картинке.
@MainActor
@Observable
final class RecapModel {
    let ref: RecapRef
    private(set) var cards: [RecapCard] = []
    private(set) var colors = RecapColors.from(cover: nil)
    private(set) var images: RecapImages = [:]
    private(set) var loading = true

    /// Смена цветов под обложку — плавно.
    private static let tintDuration = 0.6

    init(ref: RecapRef) {
        self.ref = ref
    }

    func load() async {
        let rows = PlayLog.shared.rows
        let tracks = PlayLog.shared.tracks
        let ref = ref
        let recap = await Task.detached(priority: .userInitiated) {
            RecapEngine.compute(rows: rows, tracks: tracks, ref: ref)
        }.value
        cards = RecapEngine.cards(recap)
        loading = false
        guard !cards.isEmpty else { return }

        async let tint = Self.tint(RecapEngine.coverURL(recap))
        async let pictures = Self.download(Self.imageURLs(recap))
        let (accent, loaded) = await (tint, pictures)
        withAnimation(.easeInOut(duration: Self.tintDuration)) { colors = .from(cover: accent) }
        images = loaded.compactMapValues { UIImage(data: $0) }
    }

    private nonisolated static func tint(_ cover: String?) async -> RGB? {
        guard let cover, let url = URL(string: cover) else { return nil }
        return await ThemeStore.sample(of: url)?.accent
    }

    /// Обложки топа и «на повторе», аватары артистов и нового артиста — без повторов.
    private static func imageURLs(_ r: Recap) -> [String] {
        var urls = r.topTracks.compactMap(\.track.coverURL)
        urls += r.topArtists.compactMap(\.avatarURL)
        urls += [r.newArtist?.artist.avatarURL, r.repeatTrack?.track.track.coverURL].compactMap { $0 }
        var seen = Set<String>()
        return urls.filter { seen.insert($0).inserted }
    }

    /// Не загрузилась картинка — на карточке нота вместо неё.
    private nonisolated static func download(_ urls: [String]) async -> [String: Data] {
        await withTaskGroup(of: (String, Data?).self) { group in
            for link in urls {
                group.addTask {
                    guard let url = URL(string: link),
                          let (data, _) = try? await URLSession.shared.data(from: url) else { return (link, nil) }
                    return (link, data)
                }
            }
            var result: [String: Data] = [:]
            for await (link, data) in group {
                if let data { result[link] = data }
            }
            return result
        }
    }
}

/// Итоги на весь экран (как ПК `RecapViewer.svelte`): карточки листаются свайпом, стрелками внизу и
/// клавишами ← → (клавиатура у iPad); под карточкой — «Поделиться» (картинка через `ImageRenderer` →
/// `ShareLink`, там же «Сохранить изображение») и «Скопировать». «Меньше движения» — только прозрачность.
struct RecapView: View {
    let ref: RecapRef
    @State private var model: RecapModel
    @State private var index = 0
    @State private var forward = true
    @State private var shot: RecapShot?
    @State private var toast: String?
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Свайп короче — не листаем.
    private static let swipeDistance: CGFloat = 60
    /// Картинку текущей карточки рисуем, когда листание успокоилось.
    private static let shotDelay: Duration = .milliseconds(250)
    private static let toastTime: Duration = .seconds(2)

    init(ref: RecapRef) {
        self.ref = ref
        _model = State(initialValue: RecapModel(ref: ref))
    }

    private var ink: Color { Color(model.colors.ink) }

    var body: some View {
        ZStack {
            RecapBackdrop(colors: model.colors)
            VStack(spacing: 0) {
                header
                content
                if !model.cards.isEmpty {
                    footer
                }
            }
            if let toast {
                Text(toast)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(model.colors.accentInk))
                    .padding(.horizontal, 18)
                    .frame(height: 42)
                    .background(Color(model.colors.accent), in: Capsule())
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 70)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(Motion.spring, value: toast)
        .preferredColorScheme(.dark)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { step(-1); return .handled }
        .onKeyPress(.rightArrow) { step(1); return .handled }
        .onKeyPress(.escape) { dismiss(); return .handled }
        .task {
            focused = true
            let seen = SettingsStore.shared.string("stats.recap_seen")
            SettingsStore.shared.set("stats.recap_seen", .string(RecapEngine.markSeen(seen, ref.id)))
            await model.load()
        }
        .task(id: ShotKey(index: index, colors: model.colors, images: model.images.count, cards: model.cards.count)) {
            shot = nil
            try? await Task.sleep(for: Self.shotDelay)
            guard !Task.isCancelled else { return }
            shot = render()
        }
        .task(id: toast) {
            guard toast != nil else { return }
            try? await Task.sleep(for: Self.toastTime)
            guard !Task.isCancelled else { return }
            toast = nil
        }
    }

    // MARK: - Шапка

    private var header: some View {
        HStack(spacing: 12) {
            LogoMark(size: 22)
                .foregroundStyle(ink)
            VStack(alignment: .leading, spacing: 1) {
                Text(RecapText.kindTitle(ref))
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(ink.opacity(0.6))
                Text(RecapText.periodTitle(ref))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(ink)
            }
            Spacer()
            roundButton(.close, label: t("Закрыть")) { dismiss() }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 10)
    }

    // MARK: - Карточка

    @ViewBuilder
    private var content: some View {
        if model.loading {
            message(t("Собираю итоги…"), icon: .sparkles)
        } else if model.cards.isEmpty {
            message(t("Мало данных за этот период — послушай ещё немного"), icon: .headphone)
        } else {
            ScrollView {
                RecapCardView(card: model.cards[index], ref: ref, colors: model.colors, images: model.images)
                    .id(index)
                    .transition(pageTransition)
                    .padding(.horizontal, Theme.gutter)
                    .padding(.vertical, 18)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .simultaneousGesture(swipe)
        }
    }

    private var pageTransition: AnyTransition {
        if reduceMotion { return .opacity }
        let edge: Edge = forward ? .trailing : .leading
        return .asymmetric(insertion: .move(edge: edge).combined(with: .opacity),
                           removal: .move(edge: edge == .trailing ? .leading : .trailing).combined(with: .opacity))
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 24).onEnded { value in
            let dx = value.translation.width
            guard abs(dx) > Self.swipeDistance, abs(dx) > abs(value.translation.height) else { return }
            step(dx < 0 ? 1 : -1)
        }
    }

    private func step(_ delta: Int) {
        let next = index + delta
        guard model.cards.indices.contains(next) else { return }
        forward = delta > 0
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : Motion.spring) { index = next }
    }

    private func message(_ text: String, icon: IconName) -> some View {
        VStack(spacing: 14) {
            SonarIcon(icon, filled: true, size: 34)
                .foregroundStyle(Color(model.colors.accent))
            Text(text)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(ink.opacity(0.8))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
    }

    // MARK: - Низ: листание и картинка

    private var footer: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                roundButton(.arrowLeft, label: t("Назад")) { step(-1) }
                    .opacity(index > 0 ? 1 : 0.35)
                    .disabled(index == 0)
                dots
                    .frame(maxWidth: .infinity)
                roundButton(.arrowRight, label: t("Дальше")) { step(1) }
                    .opacity(index < model.cards.count - 1 ? 1 : 0.35)
                    .disabled(index >= model.cards.count - 1)
            }
            HStack(spacing: 10) {
                shareButton
                actionButton(.copy, title: t("Скопировать"), filled: false, action: copy)
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.bottom, 12)
    }

    private var dots: some View {
        HStack(spacing: 5) {
            ForEach(model.cards.indices, id: \.self) { i in
                Capsule()
                    .fill(i == index ? Color(model.colors.accent) : ink.opacity(0.25))
                    .frame(width: i == index ? 18 : 6, height: 6)
            }
        }
        .animation(Motion.spring, value: index)
    }

    @ViewBuilder
    private var shareButton: some View {
        if let shot, shot.index == index {
            ShareLink(item: shot.url, preview: SharePreview(RecapText.periodTitle(ref), image: Image(uiImage: shot.image))) {
                actionLabel(.share, title: t("Поделиться"), filled: true)
            }
            .buttonStyle(PressableStyle())
        } else {
            actionLabel(.share, title: t("Поделиться"), filled: true)
                .opacity(0.5)
        }
    }

    private func actionButton(_ icon: IconName, title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { actionLabel(icon, title: title, filled: filled) }
            .buttonStyle(PressableStyle())
    }

    private func actionLabel(_ icon: IconName, title: String, filled: Bool) -> some View {
        HStack(spacing: 8) {
            SonarIcon(icon, size: 18)
            Text(title).font(.system(size: 15, weight: .semibold))
        }
        .foregroundStyle(filled ? Color(model.colors.accentInk) : ink)
        .frame(maxWidth: .infinity)
        .frame(height: 50)
        .background(filled ? Color(model.colors.accent) : ink.opacity(0.12), in: Capsule())
    }

    private func roundButton(_ icon: IconName, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            SonarIcon(icon, size: 20)
                .foregroundStyle(ink)
                .frame(width: 46, height: 46)
                .background(ink.opacity(0.12), in: Circle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }

    // MARK: - Картинка

    private func render() -> RecapShot? {
        guard model.cards.indices.contains(index) else { return nil }
        return RecapShare.render(card: model.cards[index], index: index, ref: ref, colors: model.colors, images: model.images)
    }

    private func copy() {
        guard let image = (shot?.index == index ? shot : render())?.image else {
            toast = t("Не удалось нарисовать картинку")
            return
        }
        UIPasteboard.general.image = image
        toast = t("Картинка скопирована")
    }
}

/// Что меняет картинку текущей карточки.
private struct ShotKey: Equatable {
    var index: Int
    var colors: RecapColors
    var images: Int
    var cards: Int
}

/// Фон итогов: градиент из цветов обложки и мягкое пятно акцента.
struct RecapBackdrop: View {
    let colors: RecapColors

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(colors.bg), Color(colors.bg2)], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color(colors.accent).opacity(0.32), .clear], center: .topTrailing,
                           startRadius: 10, endRadius: 420)
        }
        .ignoresSafeArea()
    }
}

/// Нарисованная карточка: PNG во временной папке (для `ShareLink`) и сама картинка (буфер, превью).
struct RecapShot {
    var index: Int
    var url: URL
    var image: UIImage
}

/// Картинка карточки через `ImageRenderer`: шапка с периодом, карточка без анимаций, знак Sonar.
@MainActor
enum RecapShare {
    private static let width: CGFloat = 360
    private static let scale: CGFloat = 3

    static func render(card: RecapCard, index: Int, ref: RecapRef, colors: RecapColors, images: RecapImages) -> RecapShot? {
        let view = RecapShareCard(card: card, ref: ref, colors: colors, images: images)
            .frame(width: width)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        guard let image = renderer.uiImage, let png = image.pngData() else { return nil }
        let name = String(format: "Sonar %@ %02d-%@.png", ref.id, index + 1, card.id)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try png.write(to: url, options: .atomic)
        } catch {
            return nil
        }
        return RecapShot(index: index, url: url, image: image)
    }
}

/// То, что попадает на картинку.
struct RecapShareCard: View {
    let card: RecapCard
    let ref: RecapRef
    let colors: RecapColors
    let images: RecapImages

    var body: some View {
        let ink = Color(colors.ink)
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                LogoMark(size: 20)
                    .foregroundStyle(ink)
                Text(verbatim: "Sonar")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(ink)
                Spacer()
                Text("\(RecapText.kindTitle(ref)) · \(RecapText.periodTitle(ref))")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(ink.opacity(0.65))
                    .lineLimit(1)
            }
            RecapCardView(card: card, ref: ref, colors: colors, images: images, live: false)
        }
        .padding(20)
        .background {
            ZStack {
                LinearGradient(colors: [Color(colors.bg), Color(colors.bg2)], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [Color(colors.accent).opacity(0.32), .clear], center: .topTrailing,
                               startRadius: 10, endRadius: 320)
            }
        }
    }
}
