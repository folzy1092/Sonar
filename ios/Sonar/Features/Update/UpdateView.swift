import SwiftUI

/// Заголовок и пояснение стадии обновления на устройстве (тексты — как на экране Shadow).
enum SelfUpdateText {
    static func megabytes(_ bytes: Int64) -> String {
        String(format: "%.1f МБ", Double(bytes) / 1_048_576)
    }

    static func percent(_ fraction: Double) -> String {
        "\(Int((max(0, min(1, fraction)) * 100).rounded(.down)))%"
    }

    /// nil — обновление не идёт.
    @MainActor
    static func row(_ updater: SelfUpdater) -> (title: String, detail: String)? {
        let build = updater.build.map { " \($0)" } ?? ""
        switch updater.stage {
        case .idle:
            return nil
        case let .downloading(received, total):
            if total > 0 {
                return ("Загрузка сборки\(build) · \(percent(Double(received) / Double(total)))", "\(megabytes(received)) из \(megabytes(total))")
            }
            return ("Загрузка сборки\(build)…", received > 0 ? megabytes(received) : "")
        case let .unpacking(fraction):
            return ("Распаковка · \(percent(fraction))", "")
        case .signing:
            return ("Подпись сертификатом…", "До минуты. Не сворачивай Sonar, пока идёт подготовка.")
        case let .packing(fraction):
            return ("Упаковка подписанной IPA · \(percent(fraction))", "")
        case .startingServer:
            return ("Подготовка установки…", "")
        case let .waitingForConfirmation(hint):
            if hint {
                // окно было, но загрузка не началась — или окна не было вовсе
                let title = updater.diagnostics?.promptSeen == true ? "Установка не началась" : "Окно установки не появилось"
                return (title, updater.diagnostics?.cause ?? "Нажми «Показать окно установки» или поделись IPA и поставь её через ESign.")
            }
            return ("Подтверди установку в окне iOS", "Нажми «Открыть», потом «Установить». Не сворачивай Sonar, пока не нажмёшь «Установить».")
        case let .sending(sent, total):
            let fraction = total > 0 ? Double(sent) / Double(total) : 0
            return ("Установка: передача в iOS · \(percent(fraction))", "Не закрывай Sonar до конца передачи.")
        case .installing:
            return ("iOS устанавливает обновление", "Sonar сейчас закроется и обновится. Если иконка застряла на «Ожидание», открой её ещё раз.")
        case let .failed(reason):
            return ("Не удалось обновить", reason)
        }
    }
}

/// «Обновление» — открывается из всплывашки и из «Обновлений» в профиле: текущая → новая версия,
/// сколько функций и исправлений, главная кнопка (есть пара — скачать, подписать и поставить; нет —
/// ссылка на IPA), прогресс по стадиям с диагностикой и изменения каждой пропущенной сборки.
struct UpdateView: View {
    @Environment(UpdateChecker.self) private var checker
    @Environment(SelfUpdater.self) private var updater
    @Environment(SigningModel.self) private var signing
    @Environment(\.openURL) private var openURL

    var body: some View {
        SettingsScreen(title: "Обновление") {
            VersionHeader(release: checker.available)
                .cascade(0)

            if SelfUpdateText.row(updater) != nil {
                ProgressCard()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else if let release = checker.available {
                mainAction(release)
                    .cascade(1)
            } else {
                StatusLine()
                    .cascade(1)
            }

            if let release = checker.available, !release.changelog.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(release.changelog.enumerated()), id: \.element.build) { index, entry in
                        ChangelogCard(entry: entry)
                            .cascade(index + 2)
                    }
                }
            } else if let release = checker.available, !release.notes.isEmpty {
                Text(release.notes)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textSecondary)
                    .cascade(2)
            }
        }
        .animation(Motion.spring, value: updater.stage)
        .task {
            if checker.status == nil { await checker.check() }
        }
    }

    @ViewBuilder
    private func mainAction(_ release: UpdateRelease) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if signing.isConfigured {
                PrimaryButton(title: "Обновить до \(release.label)", icon: "arrow.down.circle") {
                    updater.start(release)
                }
            } else {
                PrimaryButton(title: "Скачать IPA \(release.label)", icon: "arrow.down.circle") {
                    openURL(release.downloadURL ?? release.pageURL)
                }
                NavigationLink {
                    SigningPairView()
                } label: {
                    Label("Добавь сертификат — и Sonar будет обновляться сам", systemImage: "key")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PressableStyle())
            }
        }
    }
}

/// «Текущая 0.1.0 (12) → Новая 0.1.1 (15)» и счётчики.
private struct VersionHeader: View {
    let release: UpdateRelease?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                version(caption: "Текущая", value: UpdateChecker.installedLabel)
                if let release {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .transition(.opacity)
                    version(caption: "Новая", value: release.label, accent: true)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
                Spacer(minLength: 0)
            }
            if let release {
                Text(UpdateCounts(release).text)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
                if release.isRequired {
                    Text("ОБЯЗАТЕЛЬНОЕ ОБНОВЛЕНИЕ")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.accentInk)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.danger, in: Capsule())
                }
                if let title = release.title {
                    Text(title)
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(Theme.text)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.line))
    }

    private func version(caption: String, value: String, accent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(caption)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
            Text(value)
                .font(.system(size: 20, weight: .bold).monospacedDigit())
                .foregroundStyle(accent ? Theme.accent : Theme.text)
                .contentTransition(.numericText())
        }
    }
}

/// Статус проверки, когда обновления нет: «Актуальная версия», «Проверяю…», ошибка — и кнопка проверки.
struct StatusLine: View {
    @Environment(UpdateChecker.self) private var checker

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Group {
                    if checker.isChecking {
                        ProgressView().tint(Theme.textSecondary)
                    } else if case .failed = checker.status {
                        Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.danger)
                    } else {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.success)
                    }
                }
                .frame(width: 22)
                Text(text)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .contentTransition(.opacity)
                Spacer()
            }
            .animation(Motion.spring, value: checker.isChecking)
            SecondaryButton(title: "Проверить обновления", icon: "arrow.clockwise") {
                Task { await checker.check() }
            }
            .disabled(checker.isChecking)
        }
    }

    private var text: String {
        if checker.isChecking { return "Проверяю обновления…" }
        switch checker.status {
        case nil: return "Ещё не проверял"
        case .upToDate: return "Актуальная версия"
        case let .available(release): return "Доступна \(release.label)"
        case let .failed(reason): return "Не удалось проверить: \(reason)"
        }
    }
}

/// Прогресс обновления на устройстве: стадия, доля, диагностика и кнопки.
struct ProgressCard: View {
    @Environment(SelfUpdater.self) private var updater

    var body: some View {
        if let row = SelfUpdateText.row(updater) {
            VStack(alignment: .leading, spacing: 12) {
                Text(row.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .contentTransition(.numericText())
                    .animation(Motion.progress, value: row.title)
                if updater.isRunning || updater.stage == .installing {
                    ProgressLine(fraction: updater.stage.fraction)
                }
                if !row.detail.isEmpty {
                    Text(row.detail)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }
                if let line = updater.diagnostics?.line {
                    Text(line)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                        .textSelection(.enabled)
                        .transition(.opacity)
                }
                actions
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.line))
        }
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 10) {
            if case .waitingForConfirmation = updater.stage {
                PrimaryButton(title: "Показать окно установки", icon: "arrow.down.app") {
                    updater.retryInstallPrompt()
                }
            }
            if case .failed = updater.stage, let release = UpdateChecker.shared.available {
                PrimaryButton(title: "Повторить", icon: "arrow.clockwise") {
                    updater.start(release)
                }
            }
            if let ipa = updater.signedIPA, updater.stage != .installing {
                ShareLink(item: ipa) {
                    Label("Поделиться подписанной IPA", systemImage: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(Theme.card, in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.line))
                }
                .buttonStyle(PressableStyle())
            }
            if updater.isRunning {
                SecondaryButton(title: "Отменить", role: .destructive) {
                    updater.cancel()
                }
            }
        }
        .animation(Motion.spring, value: updater.stage)
    }
}

/// Изменения одной сборки: заголовок и строки с метками НОВОЕ / ИСПРАВЛЕНО.
struct ChangelogCard: View {
    let entry: ChangelogEntry
    var installed = false
    var download: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(header)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
                if installed {
                    Text("УСТАНОВЛЕНА")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.accentInk)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.accent, in: Capsule())
                }
            }
            if let title = entry.title {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.text)
            }
            ForEach(Array(entry.lines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let label = line.label {
                        Text(label)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(label == "НОВОЕ" ? Theme.accent : Theme.success)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background((label == "НОВОЕ" ? Theme.accent : Theme.success).opacity(0.14), in: Capsule())
                    } else {
                        Circle().fill(Theme.textTertiary).frame(width: 4, height: 4).offset(y: -3)
                    }
                    Text(line.text)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.text.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let download {
                Link(destination: download) {
                    Label("Скачать IPA", systemImage: "arrow.down.circle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
                .padding(.top, 2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.line))
    }

    private var header: String {
        var text = "СБОРКА \(entry.build)"
        if let version = entry.version { text += " · \(version)" }
        if !entry.date.isEmpty { text += " · \(ChangelogEntry.dateText(entry.date))" }
        return text
    }
}

/// «Архив версий» — все сборки для iPhone из changelog.json со ссылкой на IPA (прочитать, что менялось,
/// или откатиться).
struct VersionArchiveView: View {
    @Environment(UpdateChecker.self) private var checker

    var body: some View {
        SettingsScreen(title: "Архив версий") {
            if let archive = checker.archive {
                if archive.isEmpty {
                    Text("Пока пусто: сборки появятся здесь, когда их объявят.")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.textSecondary)
                        .cascade(0)
                } else {
                    ForEach(Array(archive.enumerated()), id: \.element.build) { index, entry in
                        ChangelogCard(entry: entry, installed: entry.build == UpdateChecker.installedBuild,
                                      download: entry.ipaURL ?? UpdateFeed.ipaURL(build: entry.build))
                            .cascade(index)
                    }
                }
            } else {
                ProgressView()
                    .tint(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
            }
            Link(destination: UpdateFeed.latestIPAURL) {
                Label("Последняя сборка из main", systemImage: "shippingbox")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .task { await checker.loadArchive() }
    }
}

/// На пол экрана (владелец, 2026-11-17): iOS ставит обновление, только когда Sonar свёрнут — поэтому прямо
/// говорим «выйди на рабочий стол». Только когда iOS уже забирает IPA (нажато «Открыть» → «Установить»):
/// раньше лист закрывал окно Safari «Открыть в iTunes?» и звал на рабочий стол до установки, а там
/// ничего не происходило (владелец, 2026-11-19).
struct HomeScreenHint: View {
    let title: String
    let text: String
    @State private var bounce = false

    nonisolated static func text(for stage: SelfUpdateStage) -> (title: String, text: String)? {
        switch stage {
        case .sending, .installing:
            return ("Sonar ждёт, пока ты выйдешь на рабочий стол",
                    "Обновление уже у iOS. Сверни Sonar — смахни вверх от нижнего края, установка начнётся сама. Любимые и настройки сохранятся.")
        default:
            return nil
        }
    }

    var body: some View {
        VStack(spacing: 18) {
            Capsule().fill(Theme.text.opacity(0.25)).frame(width: 40, height: 5)
            SonarIcon(.chevronDown, size: 40)
                .rotationEffect(.degrees(180))
                .foregroundStyle(Theme.accent)
                .offset(y: bounce ? -10 : 4)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: bounce)
            Text(title)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.center)
            Text(text)
                .font(.system(size: 16))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 26)
        .padding(.top, 14)
        .padding(.bottom, 40)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 380, alignment: .top)
        .background(.ultraThinMaterial, in: UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32, style: .continuous))
        .overlay(UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32, style: .continuous).strokeBorder(Theme.line))
        .ignoresSafeArea(edges: .bottom)
        .onAppear { bounce = true }
    }
}
