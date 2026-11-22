import PhotosUI
import SwiftUI
import UIKit

/// Профиль → Интерфейс → Вид (ПК `pages/settings/Look.svelte` + «Стиль», скрины владельца раздела «Вид»):
/// тема (тёмная / светлая / как в системе), цвет — под обложку или одна из 13 готовых тем образцами,
/// стиль Sonar (поверхность), фон приложения (стандартный / цвет обложки / сама обложка / свой из
/// галереи), прозрачность и тип стекла, скругление, мини-плеер, анимации. Всё применяется сразу.
struct LookSettingsView: View {
    enum Sheet: String, Identifiable {
        case style, background, glass, corners, strength
        var id: String { rawValue }
    }

    @Environment(SettingsStore.self) private var settings
    @State private var sheet: Sheet?
    @State private var showPhotos = false
    @State private var photo: PhotosPickerItem?
    @State private var pickAfterSheet = false
    @State private var failed = false

    private var theme: ThemeStore { ThemeStore.shared }
    private var mode: AppearanceMode { AppearanceMode(rawValue: settings.string(LookKey.mode)) ?? .dark }
    private var backdrop: BackdropMode { BackdropMode(rawValue: settings.string(LookKey.background)) ?? .coverColor }
    private var glassType: GlassType { GlassType(rawValue: settings.string(LookKey.glassType)) ?? .ultra }
    private var surface: Surface { Surface(rawValue: settings.string(LookKey.surface)) ?? .classic }
    private var opacity: Int { Int(settings.number(LookKey.opacity, fallback: 80).rounded()) }
    private var corners: MiniStyle.Corners { MiniStyle.current(settings).corners }
    private var strength: CoverStrength { CoverStrength(setting: settings.string(LookKey.coverStrength)) }

    /// Выбранный стиль: готовый, если его поверхность совпадает; иначе «Свой».
    private var styleTitle: String {
        let id = settings.string(LookKey.style)
        if let preset = StylePreset.named(id), preset.surface == surface { return preset.title }
        return "Свой · \(surface.title)"
    }

    var body: some View {
        LookScreen(title: "Вид") {
            LookCaption(text: "Тема").cascade(0)
            modeTiles.cascade(1)

            LookCaption(text: "Цвет").cascade(2)
            swatches.cascade(3)
            if settings.bool(LookKey.coverTheme) {
                // сила темы под обложку — только когда цвет берётся с обложки (ПК Look.svelte)
                LookCard {
                    LookRow(title: t("Сила темы под обложку"), value: t(strength.title), icon: .contrast) { sheet = .strength }
                }
                .cascade(4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            LookCard {
                LookRow(title: "Стиль", value: styleTitle, icon: .paintBrush) { sheet = .style }
                LookRow(title: "Фон", value: backdropValue, icon: backdropIcon(backdrop)) { sheet = .background }
                if backdrop == .custom {
                    Button { showPhotos = true } label: {
                        LookRowLabel(title: BackdropStore.shared.image == nil ? "Выбрать картинку" : "Другая картинка",
                                     value: "Из галереи, хранится на телефоне", icon: .imagePlus)
                    }
                    .buttonStyle(PressableStyle(scale: 0.99))
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                if backdrop.isPicture {
                    LookSlider(title: "Затемнение", range: 0 ... 90, step: 5, value: number(LookKey.bgDim))
                        .transition(.opacity)
                    LookSlider(title: "Размытие", range: 0 ... 40, unit: "", value: number(LookKey.bgBlur))
                        .transition(.opacity)
                }
            }
            .cascade(5)

            LookCard {
                LookToggle(title: "Прозрачность", value: settings.bool(LookKey.glass) ? "Включено (\(opacity)%)" : "Выключено",
                           isOn: binding(LookKey.glass))
                if settings.bool(LookKey.glass) {
                    LookSlider(title: "Непрозрачность", range: 15 ... 100, value: number(LookKey.opacity))
                        .transition(.opacity)
                    LookRow(title: "Тип стекла", value: glassType.title, icon: glassIcon(glassType)) { sheet = .glass }
                        .transition(.opacity)
                }
            }
            .cascade(6)

            LookCard {
                LookRow(title: "Скругление", value: corners.title, icon: corners.icon) { sheet = .corners }
                NavigationLink { MiniPlayerSettingsView() } label: {
                    LookRowLabel(title: "Мини-плеер", value: MiniStyle.current(settings).preset.title, icon: .capsule)
                }
                .buttonStyle(PressableStyle(scale: 0.99))
            }
            .cascade(7)

            LookCard {
                LookToggle(title: "Анимации",
                           value: settings.bool(LookKey.animations) ? "Переходы, листы, списки" : "Только короткие переходы",
                           isOn: binding(LookKey.animations))
            }
            .cascade(8)
        }
        .animation(Motion.spring, value: backdrop)
        .animation(Motion.spring, value: settings.bool(LookKey.glass))
        .animation(Motion.spring, value: settings.bool(LookKey.coverTheme))
        .sheet(item: $sheet, onDismiss: {
            if pickAfterSheet {
                pickAfterSheet = false
                showPhotos = true
            }
        }) { kind in
            sheetContent(kind)
        }
        .photosPicker(isPresented: $showPhotos, selection: $photo, matching: .images)
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task { await usePhoto(item) }
        }
        .alert("Не получилось открыть картинку", isPresented: $failed) {
            Button("Понятно", role: .cancel) {}
        }
    }

    // MARK: Тема и цвет

    private var modeTiles: some View {
        HStack(spacing: 10) {
            ForEach(AppearanceMode.allCases) { item in
                LookTile(icon: modeIcon(item), title: item.title, selected: mode == item) {
                    settings.set(LookKey.mode, .string(item.rawValue))
                    Haptics.select()
                }
            }
        }
    }

    /// «Под трек» и 13 готовых тем: два кружка — акцент и фон (как ПК). Готовая тема выключает «Под трек».
    private var swatches: some View {
        let cover = settings.bool(LookKey.coverTheme)
        let preset = settings.string(LookKey.preset)
        let light = theme.tokens.light
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
            swatch(title: "Под трек", colors: LookTheme.swatch(theme.coverAccent ?? RGB(196, 164, 132), surface: surface, light: light),
                   on: cover) {
                settings.set(LookKey.coverTheme, true)
            }
            ForEach(ThemePreset.all) { item in
                swatch(title: item.title,
                       colors: LookTheme.swatch(item.accent, black: item.black, surface: surface, light: light),
                       on: !cover && preset == item.id) {
                    settings.set(LookKey.preset, .string(item.id))
                    settings.set(LookKey.coverTheme, false)
                }
            }
        }
    }

    private func swatch(title: String, colors: (accent: RGB, bg: RGB), on: Bool, pick: @escaping @MainActor () -> Void) -> some View {
        Button {
            pick()
            Haptics.select()
        } label: {
            VStack(spacing: 8) {
                HStack(spacing: -7) {
                    Circle().fill(Color(colors.accent)).frame(width: 22, height: 22)
                    Circle().fill(Color(colors.bg)).frame(width: 22, height: 22)
                        .overlay(Circle().strokeBorder(Theme.line))
                }
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(on ? Theme.text : Theme.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 70)
            .background(on ? Theme.raisedHigh : Theme.raised.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(on ? Theme.accent.opacity(0.7) : .clear, lineWidth: 1.5))
        }
        .buttonStyle(PressableStyle(scale: 0.94))
        .accessibilityLabel(title)
        .accessibilityAddTraits(on ? .isSelected : [])
        .animation(Motion.spring, value: on)
    }

    // MARK: Листы

    @ViewBuilder
    private func sheetContent(_ kind: Sheet) -> some View {
        switch kind {
        case .style:
            let options = StylePreset.all.map { LookChoice(id: $0.id, title: $0.title, subtitle: "Поверхность «\($0.surface.title)»", icon: .layers) }
            LookChoiceSheet(options: options, selected: currentStyleID) { id in applyStyle(id) }
                .lookSheet(height: LookChoiceSheet.height(options.count, subtitles: true))
        case .background:
            let options = BackdropMode.allCases.map { LookChoice(id: $0.rawValue, title: $0.title, icon: backdropIcon($0)) }
            LookChoiceSheet(options: options, selected: backdrop.rawValue) { id in
                guard let next = BackdropMode(rawValue: id) else { return }
                if next == .custom, BackdropStore.shared.image == nil {
                    // своей картинки ещё нет — сначала галерея, фон включится, когда картинка выбрана
                    pickAfterSheet = true
                    sheet = nil
                } else {
                    settings.set(LookKey.background, .string(id))
                }
            }
            .lookSheet(height: LookChoiceSheet.height(options.count))
        case .glass:
            let options = GlassType.allCases.map { LookChoice(id: $0.rawValue, title: $0.title, subtitle: $0.subtitle, icon: glassIcon($0)) }
            LookChoiceSheet(options: options, selected: glassType.rawValue) { id in
                settings.set(LookKey.glassType, .string(id))
            }
            .lookSheet(height: LookChoiceSheet.height(options.count, subtitles: true))
        case .corners:
            let options = MiniStyle.Corners.allCases.map { LookChoice(id: $0.rawValue, title: $0.title, icon: $0.icon) }
            LookChoiceSheet(options: options, selected: corners.rawValue) { id in
                guard let next = MiniStyle.Corners(rawValue: id) else { return }
                // тот же ключ, что «Скругление границ» мини-плеера: заготовка сама станет «Своей»
                var style = MiniStyle.current(settings)
                style.corners = next
                style.save(settings)
            }
            .lookSheet(height: LookChoiceSheet.height(options.count))
        case .strength:
            let options = CoverStrength.allCases.map { LookChoice(id: $0.rawValue, title: t($0.title), icon: .contrast) }
            LookChoiceSheet(options: options, selected: strength.rawValue) { id in
                settings.set(LookKey.coverStrength, .string(id))
            }
            .lookSheet(height: LookChoiceSheet.height(options.count))
        }
    }

    private var currentStyleID: String {
        let id = settings.string(LookKey.style)
        if let preset = StylePreset.named(id), preset.surface == surface { return id }
        return ""
    }

    /// Готовый стиль ставит все оси, как ПК `theme.applyStyle`.
    private func applyStyle(_ id: String) {
        guard let preset = StylePreset.named(id) else { return }
        for (key, value) in preset.axes { settings.set(key, value) }
        settings.set(LookKey.style, .string(id))
    }

    // MARK: Своя картинка

    private func usePhoto(_ item: PhotosPickerItem) async {
        defer { photo = nil }
        guard let data = try? await item.loadTransferable(type: Data.self), BackdropStore.shared.save(data) else {
            failed = true
            return
        }
        settings.set(LookKey.background, .string(BackdropMode.custom.rawValue))
    }

    // MARK: Помощники

    private var backdropValue: String {
        if backdrop == .custom, BackdropStore.shared.image == nil { return "Свой — картинка не выбрана" }
        return backdrop.title
    }

    private func binding(_ key: String) -> Binding<Bool> {
        Binding(get: { settings.bool(key) }, set: { settings.set(key, $0) })
    }

    private func number(_ key: String) -> Binding<Double> {
        Binding(get: { settings.number(key, fallback: 0) }, set: { settings.set(key, .int(Int($0.rounded()))) })
    }

    private func modeIcon(_ mode: AppearanceMode) -> IconName {
        switch mode {
        case .dark: .moon
        case .light: .sun
        case .system: .contrast
        }
    }

    private func backdropIcon(_ mode: BackdropMode) -> IconName {
        switch mode {
        case .standard: .background
        case .coverColor: .palette
        case .cover: .pic
        case .custom: .imagePlus
        }
    }

    private func glassIcon(_ type: GlassType) -> IconName {
        switch type {
        case .balance: .contrast
        case .ultra: .drop
        case .noBlur: .dropOff
        }
    }
}
