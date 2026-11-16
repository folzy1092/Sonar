import SwiftUI

/// Поиск: поле, переключатель источника SoundCloud ⇄ Яндекс, вставленная ссылка → карточка «что за ней».
/// Тап по треку играет выдачу с этого места. Вкладки «Альбомы / Артисты / Плейлисты» и история — следом.
struct SearchView: View {
    @Environment(PlaybackEngine.self) private var engine
    @Environment(ChromeState.self) private var chrome
    @State private var query = ""
    @State private var source: Service = .soundcloud
    @State private var results: [Track] = []
    @State private var link: LinkItem?
    @State private var error: String?
    @State private var loading = false
    @State private var task: Task<Void, Never>?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary)
                TextField("Что включить?", text: $query)
                    .focused($focused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit { search(immediately: true) }
                if !query.isEmpty {
                    Button { query = ""; results = []; link = nil; error = nil } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textTertiary)
                    }
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 50)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.line))

            Picker("Источник", selection: $source) {
                ForEach(Service.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if loading {
                        ProgressView().tint(Theme.textSecondary).frame(maxWidth: .infinity).padding(.top, 30)
                    } else if let error {
                        Text(error)
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.top, 30)
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                    } else if let link {
                        LinkCard(item: link)
                    } else if results.isEmpty, !query.isEmpty {
                        Text("Ничего не нашлось")
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 30)
                    }
                    ForEach(Array(results.enumerated()), id: \.element.ref) { index, track in
                        TrackRow(track: track, playing: engine.current?.ref == track.ref) {
                            focused = false
                            engine.play(results, at: index, context: "Поиск")
                        }
                        .cascade(index)
                    }
                }
                .padding(.bottom, 150)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.immediately)
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, offset in
                chrome.scrolled(to: offset)
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 8)
        .background(Theme.background.ignoresSafeArea())
        .onChange(of: query) { search(immediately: false) }
        .onChange(of: source) { search(immediately: true) }
        .animation(Motion.spring, value: loading)
    }

    /// С задержкой, пока печатают; ссылка — сразу разбирается.
    private func search(immediately: Bool) {
        task?.cancel()
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            results = []
            link = nil
            error = nil
            loading = false
            return
        }
        let service = source
        task = Task {
            if !immediately { try? await Task.sleep(for: .milliseconds(350)) }
            guard !Task.isCancelled else { return }
            loading = true
            defer { if !Task.isCancelled { loading = false } }
            do {
                if ServiceLink.looksLikeLink(text) {
                    let item = try await MusicCore.shared.resolveLink(text)
                    guard !Task.isCancelled else { return }
                    link = item
                    results = []
                    if case let .track(track) = item { results = [track] }
                } else {
                    let found = try await MusicCore.shared.search(text, in: service)
                    guard !Task.isCancelled else { return }
                    link = nil
                    results = found
                }
                error = nil
            } catch {
                guard !Task.isCancelled else { return }
                results = []
                link = nil
                self.error = error.localizedDescription
            }
        }
    }
}

/// Что нашлось по ссылке: альбом, артист или плейлист (страницы — следующим шагом).
private struct LinkCard: View {
    let item: LinkItem

    var body: some View {
        switch item {
        case .track:
            EmptyView()
        case let .album(album):
            card(cover: album.coverURL, title: album.title, subtitle: "Альбом · \(album.artist)")
        case let .artist(artist):
            card(cover: artist.avatarURL, title: artist.name, subtitle: "Исполнитель")
        case let .playlist(playlist):
            card(cover: playlist.coverURL, title: playlist.title, subtitle: "Плейлист · \(playlist.owner)")
        }
    }

    private func card(cover: String?, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            CoverImage(url: cover, cornerRadius: 12).frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.text)
                Text(subtitle).font(.system(size: 14)).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }
}
