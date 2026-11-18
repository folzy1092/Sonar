import SwiftUI

/// Что открыть в конструкторе: новый умный плейлист (`editing == nil`) или правка существующего.
struct SmartDraft: Identifiable {
    let id = UUID()
    var editing: String?
    var name: String
    var rules: SmartRules

    @MainActor
    static var blank: SmartDraft {
        SmartDraft(editing: nil, name: "", rules: .blank)
    }
}

/// Конструктор умного плейлиста — как `SmartEditor.svelte` на ПК: шаблоны (у нового), название, источник,
/// условия (все / любое), порядок и лимит; внизу — сколько треков подходит прямо сейчас.
struct SmartEditorSheet: View {
    let editing: String?
    /// Готово: id созданного / изменённого плейлиста.
    let done: @MainActor (String) -> Void
    @State private var name: String
    @State private var rules: SmartRules
    @State private var history = SmartHistory(rows: [])
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    private var store: SmartPlaylistStore { SmartPlaylistStore.shared }
    private var playlists: PlaylistStore { PlaylistStore.shared }

    init(draft: SmartDraft, done: @escaping @MainActor (String) -> Void) {
        editing = draft.editing
        self.done = done
        _name = State(initialValue: draft.name)
        _rules = State(initialValue: draft.rules)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 18)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if editing == nil { templates }
                    nameField
                    section(t("Откуда брать треки")) { sourcePicker }
                    section(t("Условия")) { conditions }
                    section(t("Порядок и лимит")) { order }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.vertical, 18)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.immediately)
            preview
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 14)
        }
        .animation(Motion.spring, value: rules)
        .onAppear { history = SmartRunner.history() }
    }

    // MARK: - Шапка

    private var problem: String? { SmartEngine.problem(rules.normalized) }

    private var canSave: Bool {
        PlaylistMath.cleanName(name) != nil && problem == nil
    }

    private var header: some View {
        HStack(spacing: 12) {
            CircleButton(icon: .close, label: t("Отмена")) { dismiss() }
            Spacer()
            HStack(spacing: 6) {
                SonarIcon(.sparkles, filled: true, size: 18).foregroundStyle(Theme.accent)
                Text(editing == nil ? t("Умный плейлист") : t("Правила плейлиста"))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.text)
            }
            Spacer()
            CircleButton(icon: .check, label: editing == nil ? t("Создать") : t("Сохранить"), action: save)
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.4)
        }
    }

    private var templates: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(SmartTemplate.all) { template in
                    Button {
                        name = t(template.name)
                        rules = template.rules
                    } label: {
                        Text(t(template.name))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(rules == template.rules ? Theme.accentInk : Theme.text)
                            .padding(.horizontal, 14)
                            .frame(height: 36)
                            .background(rules == template.rules ? Theme.accent : Theme.raised.opacity(0.92), in: Capsule())
                    }
                    .buttonStyle(PressableStyle(scale: 0.95))
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var nameField: some View {
        TextField(t("Например, «Вечерний топ»"), text: $name)
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 18)
            .frame(height: 54)
            .background(Theme.raised.opacity(0.92), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .accessibilityLabel(t("Название"))
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .textCase(.uppercase)
            content()
        }
    }

    // MARK: - Источник

    private var sourceTitle: String {
        switch rules.source {
        case .liked: t("Любимые")
        case .played: t("Всё прослушанное")
        case let .playlist(id): playlists.playlist(id)?.name ?? t("Плейлист")
        }
    }

    private var sourcePicker: some View {
        Menu {
            Button(t("Любимые")) { rules.source = .liked }
            Button(t("Всё прослушанное")) { rules.source = .played }
            Menu(t("Плейлист")) {
                if playlists.playlists.isEmpty {
                    Text(t("Своих плейлистов пока нет"))
                }
                ForEach(playlists.playlists) { playlist in
                    Button(playlist.name) { rules.source = .playlist(id: playlist.id) }
                }
            }
        } label: {
            SmartChip(text: sourceTitle, wide: true)
        }
    }

    // MARK: - Условия

    @ViewBuilder
    private var conditions: some View {
        if rules.conditions.count >= 2 {
            Menu {
                Button(t("подходят все")) { rules.match = .all }
                Button(t("подходит любое")) { rules.match = .any }
            } label: {
                SmartChip(text: rules.match == .all ? t("подходят все") : t("подходит любое"))
            }
        }
        if rules.conditions.isEmpty {
            Text(t("Без условий — все треки источника."))
                .font(.system(size: 15))
                .foregroundStyle(Theme.textSecondary)
        }
        ForEach(rules.conditions.indices, id: \.self) { index in
            SmartConditionRow(condition: conditionBinding(index)) {
                rules.conditions.remove(at: index)
            }
            .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
        }
        if rules.conditions.count < SmartRules.maxConditions {
            Menu {
                ForEach(SmartField.allCases, id: \.self) { field in
                    Button(fieldTitle(field)) { rules.conditions.append(field.makeDefault()) }
                }
            } label: {
                HStack(spacing: 8) {
                    SonarIcon(.plus, size: 18)
                    Text(t("Добавить условие")).font(.system(size: 15, weight: .medium))
                }
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 14)
                .frame(height: 40)
                .background(Theme.accentSoft, in: Capsule())
            }
        }
    }

    /// Привязка к условию по номеру: удалённое условие (гонка с перерисовкой) не падает.
    private func conditionBinding(_ index: Int) -> Binding<SmartCondition> {
        Binding(
            get: { rules.conditions.indices.contains(index) ? rules.conditions[index] : .added(days: 14) },
            set: { value in
                guard rules.conditions.indices.contains(index) else { return }
                rules.conditions[index] = value
            }
        )
    }

    private func fieldTitle(_ field: SmartField) -> String {
        switch field {
        case .plays: t("Сколько раз слушал")
        case .lastPlayed: t("Когда слушал последний раз")
        case .added: t("Когда добавлен")
        case .service: t("Сервис")
        case .artist: t("Исполнитель")
        case .duration: t("Длительность")
        }
    }

    // MARK: - Порядок

    private static let sortTitles: [(SmartSortBy, String)] = [
        (.added, "По дате добавления"), (.plays, "По числу прослушиваний"), (.lastPlayed, "По последнему прослушиванию"),
        (.title, "По названию"), (.artist, "По исполнителю"), (.duration, "По длительности"),
    ]

    private var sort: SmartSort { rules.sort ?? SmartSort(by: .added) }

    private var order: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(Self.sortTitles.indices, id: \.self) { index in
                        let (by, title) = Self.sortTitles[index]
                        Button(t(title)) { rules.sort = SmartSort(by: by, days: sort.days, desc: sort.desc) }
                    }
                } label: {
                    SmartChip(text: t(Self.sortTitles.first { $0.0 == sort.by }?.1 ?? "По дате добавления"))
                }
                Menu {
                    Button(t("сначала больше / новее")) { rules.sort = SmartSort(by: sort.by, days: sort.days, desc: true) }
                    Button(t("сначала меньше / старее")) { rules.sort = SmartSort(by: sort.by, days: sort.days, desc: false) }
                } label: {
                    SmartChip(text: sort.desc ? t("сначала больше / новее") : t("сначала меньше / старее"))
                }
            }
            HStack(spacing: 8) {
                if sort.by == .plays {
                    Text(t("за")).foregroundStyle(Theme.textSecondary)
                    SmartNumberField(value: Binding(
                        get: { sort.days ?? 0 },
                        set: { rules.sort = SmartSort(by: sort.by, days: $0 == 0 ? nil : $0, desc: sort.desc) }
                    ), label: t("Дней"))
                    Text(t("дн.")).foregroundStyle(Theme.textSecondary)
                    Spacer(minLength: 12)
                }
                Text(t("Лимит треков")).foregroundStyle(Theme.textSecondary)
                SmartNumberField(value: Binding(
                    get: { rules.limit ?? 0 },
                    set: { rules.limit = $0 == 0 ? nil : $0 }
                ), label: t("Лимит треков"))
            }
            .font(.system(size: 15))
        }
    }

    // MARK: - Сейчас подходит

    private var outcome: SmartOutcome {
        let normalized = rules.normalized
        guard SmartEngine.problem(normalized) == nil else { return .invalid }
        guard let list = SmartSources.candidates(normalized.source, liked: library.liked, likedAt: library.likedAt,
                                                 playlists: playlists.playlists, played: PlayLog.shared.tracks,
                                                 history: history) else { return .sourceMissing }
        return .tracks(SmartEngine.evaluate(normalized, candidates: list, history: history,
                                            now: Int(Date().timeIntervalSince1970 * 1000)))
    }

    private var previewText: String {
        if let problem { return t(problem) }
        switch outcome {
        case .invalid: return t("Правила не читаются")
        case .sourceMissing: return t("Исходного плейлиста больше нет")
        case let .tracks(list) where list.isEmpty: return t("Пока ни один трек не подходит")
        case let .tracks(list):
            let ms = list.reduce(0) { $0 + $1.durationMs }
            return t("Подходит: {tracks}, {time}", ["tracks": tracksCount(list.count), "time": PlaylistDuration.text(ms: ms)])
        }
    }

    private var preview: some View {
        HStack(spacing: 10) {
            SonarIcon(.sparkles, filled: true, size: 18).foregroundStyle(problem == nil ? Theme.accent : Theme.danger)
            Text(previewText)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(problem == nil ? Theme.text : Theme.danger)
                .contentTransition(.numericText())
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Theme.raised.opacity(0.7), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .animation(Motion.spring, value: previewText)
    }

    private func save() {
        let clean = rules.normalized
        if let editing {
            guard store.update(editing, name: name, rules: clean) else { return }
            done(editing)
        } else {
            guard let id = store.create(name: name, rules: clean) else { return }
            done(id)
        }
        dismiss()
    }
}

/// Одно условие: подпись, сравнение и значение. Значение меняется копией условия через привязку.
struct SmartConditionRow: View {
    @Binding var condition: SmartCondition
    let remove: @MainActor () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                controls
            }
            .font(.system(size: 15))
            Spacer(minLength: 0)
            Button(action: remove) {
                SonarIcon(.close, size: 16)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(Theme.raised, in: Circle())
            }
            .buttonStyle(PressableStyle(scale: 0.9))
            .accessibilityLabel(t("Убрать условие"))
        }
        .padding(12)
        .background(Theme.raised.opacity(0.6), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private var controls: some View {
        switch condition {
        case let .plays(days, op, value):
            label(t("Прослушиваний"))
            HStack(spacing: 8) {
                cmpMenu(op) { condition = .plays(days: days, op: $0, value: value) }
                SmartNumberField(value: Binding(get: { value }, set: { condition = .plays(days: days, op: op, value: $0) }),
                                 label: t("Сколько раз"))
            }
            HStack(spacing: 8) {
                label(t("за"))
                SmartNumberField(value: Binding(get: { days ?? 0 }, set: { condition = .plays(days: $0 == 0 ? nil : $0, op: op, value: value) }),
                                 label: t("Дней"))
                label((days ?? 0) > 0 ? t("дн.") : t("дн. (0 — за всё время)"))
            }
        case let .lastPlayed(op, days):
            label(t("Последний раз слушал"))
            HStack(spacing: 8) {
                Menu {
                    Button(t("раньше, чем")) { condition = .lastPlayed(op: .before, days: days) }
                    Button(t("позже, чем")) { condition = .lastPlayed(op: .after, days: days) }
                } label: {
                    SmartChip(text: op == .before ? t("раньше, чем") : t("позже, чем"))
                }
                SmartNumberField(value: Binding(get: { days }, set: { condition = .lastPlayed(op: op, days: $0) }), label: t("Дней"))
                label(t("дн. назад"))
            }
        case let .added(days):
            label(t("Добавлен за последние"))
            HStack(spacing: 8) {
                SmartNumberField(value: Binding(get: { days }, set: { condition = .added(days: $0) }), label: t("Дней"))
                label(t("дн."))
            }
        case let .service(op, value):
            label(t("Сервис"))
            HStack(spacing: 8) {
                isMenu(op) { condition = .service(op: $0, value: value) }
                Menu {
                    ForEach(ServiceRegistry.implemented, id: \.id) { info in
                        Button(t(info.name)) { condition = .service(op: op, value: info.id.rawValue) }
                    }
                } label: {
                    SmartChip(text: ServiceID(rawValue: value).map { t(ServiceRegistry.info($0).name) } ?? "—")
                }
            }
        case let .artist(op, value):
            label(t("Исполнитель"))
            HStack(spacing: 8) {
                isMenu(op) { condition = .artist(op: $0, value: value) }
                TextField(t("Имя или часть имени"), text: Binding(get: { value }, set: { condition = .artist(op: op, value: $0) }))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(Theme.surface, in: Capsule())
            }
        case let .duration(op, value):
            label(t("Длительность"))
            HStack(spacing: 8) {
                cmpMenu(op) { condition = .duration(op: $0, value: value) }
                SmartNumberField(value: Binding(get: { Int((Double(value) / 60).rounded()) },
                                                set: { condition = .duration(op: op, value: $0 * 60) }),
                                 label: t("Минут"))
                label(t("мин"))
            }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text).foregroundStyle(Theme.textSecondary)
    }

    private func cmpMenu(_ op: SmartCmp, _ set: @escaping @MainActor (SmartCmp) -> Void) -> some View {
        Menu {
            Button(t("не меньше")) { set(.gte) }
            Button(t("не больше")) { set(.lte) }
        } label: {
            SmartChip(text: op == .gte ? t("не меньше") : t("не больше"))
        }
    }

    private func isMenu(_ op: SmartIs, _ set: @escaping @MainActor (SmartIs) -> Void) -> some View {
        Menu {
            Button(t("условие::это")) { set(.is) }
            Button(t("условие::не")) { set(.not) }
        } label: {
            SmartChip(text: op == .is ? t("условие::это") : t("условие::не"))
        }
    }
}

/// Капсула-выбор конструктора: текущее значение и стрелка; список открывает `Menu` по нажатию.
struct SmartChip: View {
    let text: String
    var wide = false

    var body: some View {
        HStack(spacing: 6) {
            Text(text)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
                .contentTransition(.opacity)
            if wide { Spacer(minLength: 4) }
            SonarIcon(.chevronDown, size: 14).foregroundStyle(Theme.textSecondary)
        }
        .foregroundStyle(Theme.text)
        .padding(.horizontal, 14)
        .frame(maxWidth: wide ? .infinity : nil)
        .frame(height: 36)
        .background(Theme.raised.opacity(0.92), in: Capsule())
    }
}

/// Поле числа конструктора: только цифры, пусто — 0.
struct SmartNumberField: View {
    @Binding var value: Int
    let label: String

    var body: some View {
        TextField("0", value: $value, format: .number)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .monospacedDigit()
            .foregroundStyle(Theme.text)
            .frame(width: 64, height: 36)
            .background(Theme.surface, in: Capsule())
            .accessibilityLabel(label)
    }
}
