import PhotosUI
import SwiftUI
import UIKit

/// Аватар локального профиля (`profile.avatar`): картинка в круге с обводкой акцентом (`photo_1`); нет
/// картинки — первая буква имени на акценте темы. Смена — плавно.
struct ProfileAvatar: View {
    var size: CGFloat = 72
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        let raw = settings.string(LookKey.profileAvatar)
        let image = AvatarCache.image(for: raw)
        let line = max(2, size * 0.035)
        let gap = max(2, size * 0.04)
        let inner = size - (line + gap) * 2
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else {
                Theme.accent
                Text(LocalProfile.initial(LocalProfile.name(settings)))
                    .font(.system(size: inner * 0.44, weight: .heavy))
                    .foregroundStyle(Theme.accentInk)
                    .contentTransition(.opacity)
                    .transition(.opacity)
            }
        }
        .frame(width: inner, height: inner)
        .clipShape(Circle())
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(Theme.accent, lineWidth: line))
        .animation(.easeInOut(duration: 0.35), value: raw.count)
        .accessibilityHidden(true)
    }
}

/// Разобранные аватары: data URL → картинка один раз (строка большая, разбирать на каждом кадре дорого).
@MainActor
enum AvatarCache {
    private static var last: (key: String, image: UIImage?)?

    static func image(for dataURL: String) -> UIImage? {
        if dataURL.isEmpty { return nil }
        if let last, last.key == dataURL { return last.image }
        let image = LocalProfile.imageData(dataURL).flatMap(UIImage.init(data:))
        last = (dataURL, image)
        return image
    }

    /// Квадрат по центру, 256×256, JPEG — как ПК `avatarFromFile` (там WebP), для `profile.avatar`.
    static func avatarDataURL(from data: Data) -> String? {
        guard let source = UIImage(data: data) else { return nil }
        let side = min(source.size.width, source.size.height)
        guard side > 0 else { return nil }
        let target = CGSize(width: 256, height: 256)
        let scale = target.width / side
        let drawSize = CGSize(width: source.size.width * scale, height: source.size.height * scale)
        let origin = CGPoint(x: (target.width - drawSize.width) / 2, y: (target.height - drawSize.height) / 2)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let square = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            source.draw(in: CGRect(origin: origin, size: drawSize))
        }
        return square.jpegData(compressionQuality: 0.85).map(LocalProfile.dataURL(jpeg:))
    }
}

/// Профиль → Аккаунт → Профиль (ПК `pages/settings/Profile.svelte`): аватар из галереи, отображаемое имя
/// (приветствие на главной) и @username. До сервера — на телефоне в настройках `profile.*`; с сервером —
/// `GET /me` / `PATCH /me` (API.md).
struct ProfileEditView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var name = ""
    @State private var username = ""
    @State private var photo: PhotosPickerItem?
    @State private var failed = false
    @State private var loaded = false
    @State private var copied = false
    /// Возврат «Ссылка скопирована» → «Копировать…»; повторное нажатие отменяет прежний (ПК — `clearTimeout`).
    @State private var copiedReset: Task<Void, Never>?
    @FocusState private var focus: Field?

    private enum Field { case name, username }

    private var userOK: Bool { LocalProfile.usernameValid(username) }
    private var hasAvatar: Bool { !settings.string(LookKey.profileAvatar).isEmpty }

    var body: some View {
        LookScreen(title: "Профиль") {
            head.cascade(0)

            LookCard {
                field(title: "Отображаемое имя",
                      hint: "Его видно на главной: «Добрый вечер, …»",
                      placeholder: "Как тебя называть", text: $name, field: .name)
                Rectangle().fill(Theme.line).frame(height: 1).padding(.horizontal, 22)
                field(title: "Имя пользователя",
                      hint: userOK ? "Латиница, цифры и «_», 3–32 знака" : "Только латиница, цифры и «_», от 3 до 32 знаков",
                      placeholder: "username", text: $username, field: .username, prefix: "@", bad: !userOK)
            }
            .cascade(1)

            share.cascade(2)

            Text("Сейчас профиль хранится на этом телефоне. С сервером Sonar он станет общим для всех устройств и друзей.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 6)
                .cascade(3)
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            name = settings.string(LookKey.profileName)
            username = settings.string(LookKey.profileUsername)
        }
        .onChange(of: focus) { old, _ in
            if old == .name { saveName() }
            if old == .username { saveUsername() }
        }
        .onDisappear {
            saveName()
            saveUsername()
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task { await usePhoto(item) }
        }
        .alert("Не получилось открыть картинку", isPresented: $failed) {
            Button("Понятно", role: .cancel) {}
        }
        .animation(Motion.spring, value: userOK)
        .animation(Motion.spring, value: hasAvatar)
    }

    /// Аватар с кружком камеры — собран заранее: замыкание метки PhotosPicker не на главном акторе.
    private var avatarLabel: some View {
        ProfileAvatar(size: 104)
            .overlay(alignment: .bottomTrailing) {
                SonarIcon(.camera, size: 17)
                    .foregroundStyle(Theme.accentInk)
                    .frame(width: 34, height: 34)
                    .background(Theme.accent, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.background, lineWidth: 3))
            }
    }

    private var head: some View {
        let label = avatarLabel
        return VStack(spacing: 12) {
            PhotosPicker(selection: $photo, matching: .images) {
                label
            }
            .buttonStyle(PressableStyle(scale: 0.95))
            .accessibilityLabel("Выбрать аватар")

            HStack(spacing: 8) {
                Text(LocalProfile.cleanName(name).isEmpty ? LocalProfile.fallbackName : LocalProfile.cleanName(name))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .contentTransition(.opacity)
                // значок разработчика — по нику, который сейчас вписан (`SonarDeep.subscriptionOf`)
                if SonarDeep.subscriptionOf(username: username).tier == .dev {
                    DevBadge(size: 11)
                        .transition(.opacity)
                }
            }
            .animation(Motion.spring, value: SonarDeep.subscriptionOf(username: username).tier)
            Text(LocalProfile.cleanUsername(username).isEmpty ? "без @username" : "@\(LocalProfile.cleanUsername(username))")
                .font(.system(size: 15))
                .foregroundStyle(Theme.textSecondary)
                .contentTransition(.opacity)
            if hasAvatar {
                Button("Убрать аватар") {
                    settings.set(LookKey.profileAvatar, .string(""))
                    Haptics.select()
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.accent)
                .buttonStyle(PressableStyle())
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    /// «Копировать ссылку на профиль» (ПК `CopyProfileLink.svelte`): `https://try-sonar.ru/@username`
    /// в буфер, значок ссылки → галочка на пару секунд. Без @username — кнопка неактивна.
    private var share: some View {
        let url = LocalProfile.profileURL(username)
        return VStack(spacing: 8) {
            Button {
                guard let url else { return }
                UIPasteboard.general.string = url
                Haptics.success()
                withAnimation(Motion.quick) { copied = true }
                copiedReset?.cancel()
                copiedReset = Task {
                    try? await Task.sleep(for: .seconds(1.8))
                    guard !Task.isCancelled else { return }
                    withAnimation(Motion.quick) { copied = false }
                }
            } label: {
                HStack(spacing: 8) {
                    SonarIcon(copied ? .check : .link, size: 17)
                    Text(copied ? t("Ссылка скопирована") : t("Копировать ссылку на профиль"))
                        .contentTransition(.opacity)
                }
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(copied ? Theme.accent : Theme.text)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(Theme.card, in: Capsule())
                .overlay(Capsule().strokeBorder(copied ? Theme.accent.opacity(0.5) : Theme.line))
            }
            .buttonStyle(PressableStyle())
            .disabled(url == nil)
            .opacity(url == nil ? 0.45 : 1)

            Text(url ?? t("Задай @username — тогда появится ссылка"))
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .contentTransition(.opacity)
            Text(t("Страница по ссылке заработает, когда у Sonar появится сервер."))
                .font(.system(size: 13))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .animation(Motion.quick, value: url)
    }

    private func field(title: String, hint: String, placeholder: String, text: Binding<String>, field: Field,
                       prefix: String? = nil, bad: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 17))
                .foregroundStyle(Theme.text)
            HStack(spacing: 4) {
                if let prefix {
                    Text(prefix).foregroundStyle(Theme.textTertiary)
                }
                TextField(placeholder, text: text)
                    .focused($focus, equals: field)
                    .textInputAutocapitalization(field == .username ? .never : .words)
                    .autocorrectionDisabled(field == .username)
                    .submitLabel(.done)
                    .onSubmit { focus = nil }
                    .onChange(of: text.wrappedValue) { _, value in
                        let limit = field == .name ? LocalProfile.nameLimit : 33
                        if value.count > limit { text.wrappedValue = String(value.prefix(limit)) }
                    }
            }
            .font(.system(size: 17))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 14)
            .frame(height: 46)
            .background(Theme.surface0.opacity(0.8), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(bad ? Theme.danger : (focus == field ? Theme.accent.opacity(0.7) : Theme.line), lineWidth: 1))
            Text(hint)
                .font(.system(size: 13))
                .foregroundStyle(bad ? Theme.danger : Theme.textTertiary)
                .contentTransition(.opacity)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .animation(Motion.quick, value: focus)
    }

    private func saveName() {
        let clean = LocalProfile.cleanName(name)
        if clean != settings.string(LookKey.profileName) { settings.set(LookKey.profileName, .string(clean)) }
    }

    private func saveUsername() {
        guard userOK else { return }
        let clean = LocalProfile.cleanUsername(username)
        if clean != settings.string(LookKey.profileUsername) { settings.set(LookKey.profileUsername, .string(clean)) }
    }

    private func usePhoto(_ item: PhotosPickerItem) async {
        defer { photo = nil }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let url = AvatarCache.avatarDataURL(from: data) else {
            failed = true
            return
        }
        withAnimation(.easeInOut(duration: 0.35)) { settings.set(LookKey.profileAvatar, .string(url)) }
    }
}
