import SwiftUI

/// «Играть из» (`TrackSourcePlan`): «Авто» или сервис, где этот трек нашёлся. Двойники ищутся при открытии
/// (`MusicCore.playSources`, как резерв); у играющего трека выбор сразу перезапускает его с того же места.
struct TrackSourceSheet: View {
    let track: Track
    /// Выбор сделан — текст плашки для листа трека.
    let picked: @MainActor (String) -> Void
    @Environment(PlaybackEngine.self) private var engine
    @Environment(LibraryStore.self) private var library
    @State private var services: [ServiceID]?

    private var choices: [TrackSourcePlan.Choice] {
        TrackSourcePlan.choices(ref: track.ref, services: services ?? [], pinned: library.source(for: track.ref))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(t("Играть из"))
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 6)
                .padding(.bottom, 10)
            if services == nil {
                HStack(spacing: 12) {
                    ProgressView().tint(Theme.textSecondary)
                    Text(t("Ищем трек в других сервисах…"))
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.horizontal, 6)
                .transition(.opacity)
            } else if choices.isEmpty {
                Text(t("В других сервисах этот трек не нашёлся"))
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 6)
                    .transition(.opacity)
            } else {
                ForEach(choices) { choice in
                    row(choice)
                }
                .transition(.opacity)
            }
        }
        .animation(Motion.spring, value: services)
        .task {
            let track = track
            let found = await MusicCore.shared.playSources(for: track)
            services = found
        }
    }

    private func row(_ choice: TrackSourcePlan.Choice) -> some View {
        let on = library.source(for: track.ref) == choice.service
        return Button {
            pick(choice.service, on: on)
        } label: {
            HStack(spacing: 18) {
                Group {
                    if let id = choice.service {
                        SonarIcon(LibraryServices.icon(id), size: 22)
                    } else {
                        SonarIcon(.wave, size: 22)
                    }
                }
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name(choice.service))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Theme.text)
                    if choice.service == nil {
                        Text(t("как решит Sonar"))
                            .font(.system(size: 13.5))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer(minLength: 0)
                if on {
                    SonarIcon(.check, size: 18)
                        .foregroundStyle(Theme.accent)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.97))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func name(_ service: ServiceID?) -> String {
        guard let service else { return t("Авто") }
        return t(ServiceRegistry.info(service).name)
    }

    private func pick(_ service: ServiceID?, on: Bool) {
        guard !on else { return picked("") }
        withAnimation(Motion.spring) { library.rememberSource(service, for: track.ref) }
        engine.sourceChanged(track.ref)
        picked(service == nil ? t("Трек снова играет как решит Sonar") : t("Играть из: {service}", ["service": name(service)]))
    }
}
