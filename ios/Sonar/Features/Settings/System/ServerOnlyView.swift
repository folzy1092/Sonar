import SwiftUI

/// Разделы, которым нужен сервер Sonar (Аккаунт → Безопасность / Приватность, Интеграции → Ключ API):
/// без сервера они не работают, поэтому честная заглушка — что там будет, без кнопок-пустышек.
/// `ServerOnlyView(.security)`, `ServerOnlyView(.privacy)`, `ServerOnlyView(.apiKey)`.
struct ServerOnlyView: View {
    enum Kind: String, CaseIterable, Identifiable {
        case security, privacy, apiKey
        var id: String { rawValue }

        var title: String {
            switch self {
            case .security: "Безопасность"
            case .privacy: "Приватность"
            case .apiKey: "Ключ API"
            }
        }

        var icon: IconName {
            switch self {
            case .security: .shield
            case .privacy: .eyeClosed
            case .apiKey: .key
            }
        }

        var summary: String {
            switch self {
            case .security: "Вход в аккаунт Sonar и всё, что его защищает."
            case .privacy: "Настройки приватности пока в разработке."
            case .apiKey: "Ключ, по которому твои боты и сервисы берут из Sonar то, что ты сейчас слушаешь."
            }
        }

        /// Что появится — по SPEC / TZ / BOT.md.
        var features: [(IconName, String)] {
            switch self {
            case .security:
                [(.lock, "Смена пароля"),
                 (.telegram, "Вход через Telegram-бота @SonarMusicApp"),
                 (.server, "Устройства, где ты вошёл, — выйти на любом"),
                 (.fingerprint, "Подтверждение входа по ссылке из бота")]
            case .privacy:
                // приватность пока не делаем (решение владельца) — только честная пометка
                []
            case .apiKey:
                [(.key, "Создать, перевыпустить или удалить ключ — показывается один раз"),
                 (.headphone, "«Сейчас играет» для selfbot и других сервисов (GET /oauth/now)"),
                 (.chart, "Треки и статистика из API Sonar")]
            }
        }

        /// Приватность — «В разработке» (с замком), остальное ждёт сервер.
        var badge: String { self == .privacy ? "В разработке" : "Появится вместе с сервером" }
    }

    let kind: Kind

    init(_ kind: Kind) {
        self.kind = kind
    }

    var body: some View {
        SystemScreen(title: t(kind.title)) {
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Theme.accent.opacity(0.12))
                        .frame(width: 120, height: 120)
                    Circle()
                        .strokeBorder(Theme.accent.opacity(0.25), lineWidth: 1)
                        .frame(width: 92, height: 92)
                    SonarIcon(kind.icon, filled: true, size: 42)
                        .foregroundStyle(Theme.accent)
                }
                HStack(spacing: 6) {
                    SonarIcon(kind == .privacy ? .lock : .server, size: 14)
                    Text(t(kind.badge))
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(Theme.raised.opacity(0.8), in: Capsule())
                Text(t(kind.summary))
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
            .cascade(0)

            if !kind.features.isEmpty {
                SystemSection(title: t("Что здесь будет"), footer: t("Сервер Sonar ещё не запущен — всё остальное работает прямо на телефоне.")) {
                    ForEach(Array(kind.features.enumerated()), id: \.offset) { index, item in
                        if index > 0 { RowDivider() }
                        SystemRow(icon: item.0, title: t(item.1))
                            .opacity(0.8)
                    }
                }
                .cascade(1)
            }
        }
    }
}
