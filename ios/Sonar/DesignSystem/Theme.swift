import SwiftUI
import UIKit

/// Цвета интерфейса. Тема — под обложку текущего трека или готовая (SPEC §4.4, как ПК-клиент):
/// `ThemeStore` берёт исходный цвет и считает фон, поверхности и текст по формулам выбранной поверхности
/// стиля (`Palette`, Интерфейс → Вид), тёмные или светлые. Ничего не играет или обложка серая — монохром.
@MainActor
enum Theme {
    private static var tokens: ThemeTokens { ThemeStore.shared.tokens }

    static var background: Color { Color(tokens.bg) }
    static var surface0: Color { Color(tokens.s0) }
    static var surface: Color { Color(tokens.s1) }
    /// Круглые кнопки, капсулы, плашки — поверхность 2, как на скринах (`IMG_6770`).
    static var raised: Color { Color(tokens.s2) }
    static var raisedHigh: Color { Color(tokens.s3) }
    /// Карточки настроек — полупрозрачные, как стекло на `photo_1..3`.
    static var card: Color { Color(tokens.text).opacity(0.07) }
    static var cardPressed: Color { Color(tokens.text).opacity(0.12) }
    static var text: Color { Color(tokens.text) }
    static var textSecondary: Color { Color(tokens.t2).opacity(0.85) }
    static var textTertiary: Color { Color(tokens.t3).opacity(0.75) }
    static var line: Color { Color(tokens.text).opacity(0.08) }
    static var border: Color { Color(tokens.border) }
    static var accent: Color { Color(tokens.accent) }
    /// Текст и значки на акценте.
    static var accentInk: Color { Color(tokens.ink) }
    /// Мягкий акцент: мини-плеер, выбранное.
    static var accentSoft: Color { Color(tokens.accent).opacity(tokens.softAlpha) }
    static var tint: Color { Color(tokens.tint) }
    static var glow: Color { Color(tokens.glow) }
    static var track: Color { Color(tokens.track) }
    static var isLight: Bool { tokens.light }
    /// Затемнение под текст на картинках: в светлой теме — светлое.
    static var scrim: Color { tokens.light ? .white : .black }
    nonisolated static let danger = Color(red: 1.0, green: 0.55, blue: 0.6)
    nonisolated static let success = Color(red: 0.42, green: 0.86, blue: 0.56)

    nonisolated static let cardRadius: CGFloat = 18
    nonisolated static let gutter: CGFloat = 16
}

extension Color {
    init(_ c: RGB) {
        self.init(.sRGB, red: c.r / 255, green: c.g / 255, blue: c.b / 255, opacity: 1)
    }
}

/// Тема. Следит за текущим треком (обложка → картинка 48×48 → `Palette.pickAccent`, цвета кэшируются) и
/// за настройками Вида (`LookInputs`: тёмная / светлая / как в системе, под обложку или готовая тема,
/// поверхность стиля). Смена плавная (450 мс, `Motion.settle`) — меняются фон, акцент, мини-плеер, кнопки.
@MainActor
@Observable
final class ThemeStore {
    static let shared = ThemeStore()

    private(set) var tokens = LookTheme.tokens(LookInputs(), coverAccent: nil, systemDark: true)
    /// Монохромная тема (ничего не играет / серая обложка) — акцент белый.
    var isMono: Bool { tokens.mono }
    /// Цвет текущей обложки (образец «Под трек» в настройках); nil — нет или серая.
    private(set) var coverAccent: RGB?
    /// Средняя светлота текущей обложки (тема уходит за ней, `appearance.cover_strength`); nil — нет обложки.
    @ObservationIgnored private var coverLightness: Double?
    /// Схема для `preferredColorScheme`: nil — как в системе.
    private(set) var colorScheme: ColorScheme? = .dark

    @ObservationIgnored private var inputs = LookInputs()
    @ObservationIgnored private var systemDark = true
    @ObservationIgnored private var coverURL: String?
    @ObservationIgnored private var cache: [String: CoverSample?] = [:]
    @ObservationIgnored private var task: Task<Void, Never>?

    /// Новая обложка (или nil — ничего не играет).
    func follow(cover url: String?) {
        guard url != coverURL else { return }
        coverURL = url
        task?.cancel()
        guard let url, let link = URL(string: url) else {
            setCover(nil)
            return
        }
        if let known = cache[url] {
            setCover(known)
            return
        }
        task = Task { [weak self] in
            let sample = await Self.sample(of: link)
            guard !Task.isCancelled, let self else { return }
            self.cache[url] = sample
            if self.cache.count > Self.cacheLimit { self.cache.removeAll() }
            if self.coverURL == url { self.setCover(sample) }
        }
    }

    /// Настройки Вида поменялись (или системная тема — при «Как в системе»).
    func update(_ next: LookInputs, systemDark: Bool) {
        let scheme: ColorScheme? = switch next.mode {
        case .dark: .dark
        case .light: .light
        case .system: nil
        }
        if scheme != colorScheme { colorScheme = scheme }
        guard next != inputs || systemDark != self.systemDark else { return }
        inputs = next
        self.systemDark = systemDark
        recompute()
    }

    private static let cacheLimit = 300

    private func setCover(_ sample: CoverSample?) {
        coverAccent = sample?.accent
        coverLightness = sample?.lightness
        if inputs.coverTheme { recompute() }
    }

    private func recompute() {
        let next = LookTheme.tokens(inputs, coverAccent: coverAccent, coverLightness: coverLightness, systemDark: systemDark)
        guard next != tokens else { return }
        withAnimation(Motion.settle) { tokens = next }
    }

    /// Пиксели уменьшенной обложки → акцент и светлота. Сеть и разбор — вне главного потока. Ещё — цвета
    /// итогов (`RecapModel`).
    nonisolated static func sample(of url: URL) async -> CoverSample? {
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: data)?.cgImage else { return nil }
        let side = 48
        var px = [UInt8](repeating: 0, count: side * side * 4)
        let drawn: Bool = px.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                          bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        return drawn ? Palette.sample(px) : nil
    }
}
