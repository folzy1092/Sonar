import SwiftUI

/// «Вместе» — комнаты и сообщения, предпросмотр до сервера (как ПК `pages/SocialPage.svelte`). Друзья выдуманы
/// (`SocialDemo`), треки — из Любимых, всё в памяти экрана. Кнопки работают по правам роли того, чьими глазами
/// смотрим (`RoomCore`); чат — `DMCore`. «Создать комнату» и «Пригласить» неактивны до сервера.
struct SocialPreviewView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(LibraryStore.self) private var library
    @Environment(PlaybackEngine.self) private var engine

    enum Tab: Hashable { case room, chat }

    @State private var tab: Tab = .room
    @State private var room: Room?
    @State private var threads: [DMThread] = []
    @State private var messages: [DMMessage] = []
    @State private var viewer = ""
    @State private var thread = "dm_friend"
    @State private var draft = ""
    @State private var replyTo: String?
    @State private var notice: String?
    @State private var built = false

    private var me: RoomMember {
        let name = settings.string(LookKey.profileName)
        let username = settings.string(LookKey.profileUsername)
        return RoomMember(username: username.isEmpty ? "me" : username, displayName: name.isEmpty ? t("вместе::Я") : name)
    }

    private var tracks: [Track] { library.liked.filter(\.available) }
    private var byRef: [String: Track] { Dictionary(tracks.map { ($0.ref, $0) }, uniquingKeysWith: { a, _ in a }) }
    private var members: [RoomMember] { SocialDemo.members(me: me, friendName: t("Друг"), friend2Name: t("Второй друг")) }
    private var roomTitle: String {
        let name = settings.string(LookKey.profileName)
        return name.isEmpty ? t("Моя комната") : t("Комната {name}", ["name": name])
    }

    private func nameOf(_ username: String) -> String {
        members.first { $0.username == username }?.displayName ?? username
    }

    var body: some View {
        SystemScreen(title: t("Вместе")) {
            banner.cascade(0)
            SystemSegments(options: [SystemSegments<Tab>.Option(id: .room, title: t("Комната")),
                                     SystemSegments<Tab>.Option(id: .chat, title: t("Сообщения"))],
                           selection: $tab)
                .cascade(1)
            if tab == .room {
                roomTab.transition(.opacity)
            } else {
                chatTab.transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            if let notice {
                Text(notice)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Theme.raisedHigh, in: Capsule())
                    .padding(.bottom, 120)
                    .transition(.opacity)
            }
        }
        .animation(Motion.spring, value: tab)
        .animation(Motion.quick, value: notice)
        .onAppear(perform: build)
    }

    // MARK: — шапка

    private var banner: some View {
        SystemSection(footer: t("Заработает вместе с сервером и друзьями. Сейчас друзья выдуманы, а треки — из твоих Любимых; никуда ничего не уходит.")) {
            SystemRow(icon: .userHeart, title: t("Комнаты и сообщения — предпросмотр"))
            RowDivider()
            SystemButtonRow(icon: .plus, title: t("Создать комнату"), subtitle: t("Появится с сервером"), enabled: false) {}
            RowDivider()
            SystemButtonRow(icon: .share, title: t("Пригласить"), subtitle: t("Появится с сервером"), enabled: false) {}
        }
    }

    // MARK: — комната

    @ViewBuilder private var roomTab: some View {
        if let room, !room.closed {
            SystemSegments(options: [
                SystemSegments<String>.Option(id: me.username, title: t("вместе::Я")),
                SystemSegments<String>.Option(id: SocialDemo.friend, title: t("Друг")),
                SystemSegments<String>.Option(id: SocialDemo.friend2, title: t("Второй друг")),
            ], selection: $viewer)
            nowPlaying(room)
            membersCard(room)
            queueCard(room)
        } else if room?.closed == true {
            SystemSection {
                SystemRow(icon: .close, title: t("Комната закрыта"))
                RowDivider()
                SystemButtonRow(icon: .refresh, title: t("Собрать демо заново"), action: build)
            }
        } else {
            SystemSection(title: t("Нужны Любимые"), footer: t("Поставь лайк паре треков — на них соберётся демо-комната.")) {
                SystemRow(icon: .heart, title: t("Нужны Любимые"))
            }
        }
    }

    private func nowPlaying(_ room: Room) -> some View {
        let current = room.queue.indices.contains(room.pos) ? byRef[room.queue[room.pos].ref] : nil
        let control = RoomCore.canControl(room, viewer)
        return SystemSection(title: roomTitle, footer: control ? t("Пульт у тебя: пауза и перемотка — у всех сразу")
            : t("Пультом управляет {name}", ["name": nameOf(room.leader)])) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    CoverImage(url: current?.coverURL, cornerRadius: 12).frame(width: 72, height: 72)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(current?.title ?? "—").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                        Text(current?.artist ?? "").font(.system(size: 14)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    let duration = max(1, current?.durationMs ?? 1)
                    let position = min(duration, RoomCore.anchorPosition(room, serverNow: Self.ms(context.date)))
                    VStack(spacing: 6) {
                        ProgressView(value: Double(position), total: Double(duration)).tint(Theme.accent)
                        HStack {
                            Text("\(Self.clock(position)) / \(Self.clock(duration))")
                                .font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.textTertiary)
                            Spacer()
                            HStack(spacing: 8) {
                                CircleButton(icon: .prev, size: 38, iconSize: 18, label: t("Предыдущий трек")) { act(.prev) }
                                CircleButton(icon: room.playing ? .pause : .play, size: 44, iconSize: 20, filled: true,
                                             label: room.playing ? t("Пауза") : t("Играть")) {
                                    act(room.playing ? .pause(position: position) : .play(position: nil))
                                }
                                CircleButton(icon: .next, size: 38, iconSize: 18, label: t("Следующий трек")) { act(.next) }
                            }
                            .disabled(!control)
                            .opacity(control ? 1 : 0.4)
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private func membersCard(_ room: Room) -> some View {
        let manage = RoomCore.canManageRoles(room, viewer)
        return SystemSection(title: "\(t("Участники")) · \(room.members.count)",
                             footer: t("Звук у каждого свой: эквалайзер и эффекты не синхронизируются, скорость в комнате — всегда 1×.")) {
            ForEach(Array(room.members.enumerated()), id: \.element.username) { index, member in
                if index > 0 { RowDivider() }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Text(String(nameOf(member.username).prefix(1)).uppercased())
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 36, height: 36)
                            .background(Theme.raisedHigh, in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(nameOf(member.username)).font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.text)
                            Text(RoomCore.mainRole(room, member.username).map { t($0.title) } ?? "")
                                .font(.system(size: 13)).foregroundStyle(Theme.textTertiary)
                        }
                        Spacer(minLength: 0)
                    }
                    if manage && member.username != room.leader {
                        HStack(spacing: 8) {
                            chip(t("Отдать пульт"), on: false) { act(.leaderSet(username: member.username)) }
                            if member.username != room.host {
                                let dj = room.djs.contains(member.username)
                                chip(t("Диджей"), on: dj) { act(.djSet(username: member.username, on: !dj)) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(member.username == viewer ? Theme.accentSoft : .clear)
            }
            if viewer == room.host {
                RowDivider()
                SystemButtonRow(icon: .close, title: t("Закрыть комнату"), tint: Theme.danger) { act(.close) }
            }
        }
    }

    private func queueCard(_ room: Room) -> some View {
        let edit = RoomCore.canEditQueue(room, viewer)
        let control = RoomCore.canControl(room, viewer)
        return SystemSection(title: t("Очередь комнаты")) {
            SystemButtonRow(icon: .plus, title: edit ? t("Добавить, что играет у меня") : t("Предложить, что играет у меня"),
                            enabled: engine.current != nil) {
                guard let ref = engine.current?.ref else { return }
                act(edit ? .queueAdd(ref: ref) : .suggest(ref: ref))
            }
            ForEach(Array(room.queue.enumerated()), id: \.offset) { index, item in
                RowDivider()
                let track = byRef[item.ref]
                HStack(spacing: 12) {
                    Button {
                        act(.jump(index: index))
                    } label: {
                        HStack(spacing: 12) {
                            CoverImage(url: track?.coverURL, cornerRadius: 8).frame(width: 40, height: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(track?.title ?? item.ref).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.text).lineLimit(1)
                                Text("\(track?.artist ?? "") · \(item.addedBy == viewer ? t("Ты") : nameOf(item.addedBy))")
                                    .font(.system(size: 12)).foregroundStyle(Theme.textTertiary).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle(scale: 0.99))
                    .disabled(!control || index == room.pos)
                    if edit && index != room.pos {
                        Button { act(.queueRemove(index: index)) } label: {
                            SonarIcon(.close, size: 16).foregroundStyle(Theme.textTertiary).frame(width: 32, height: 32)
                        }
                        .buttonStyle(PressableStyle(scale: 0.85))
                        .accessibilityLabel(t("Убрать"))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(index == room.pos ? Theme.accentSoft : .clear)
                .opacity(index < room.pos ? 0.55 : 1)
            }
        }
    }

    private func chip(_ title: String, on: Bool, action: @escaping @MainActor () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(on ? Theme.text : Theme.textSecondary)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(on ? Theme.accentSoft : .clear, in: Capsule())
                .overlay(Capsule().strokeBorder(on ? .clear : Theme.line))
        }
        .buttonStyle(PressableStyle(scale: 0.95))
    }

    // MARK: — сообщения

    @ViewBuilder private var chatTab: some View {
        SystemSegments(options: threads.map { th -> SystemSegments<String>.Option in
            let unread = DMCore.unreadCount(th, messages, me: me.username)
            let title = th.roomID != nil ? t("Чат комнаты") : nameOf(th.peer ?? "")
            return .init(id: th.id, title: unread > 0 && th.id != thread ? "\(title) · \(unread)" : title)
        }, selection: $thread)
        .onChange(of: thread) { _, id in markRead(id) }

        let current = threads.first { $0.id == thread }
        let runs = DMCore.groupRuns(DMCore.timeline(messages, thread: thread))
        VStack(alignment: .leading, spacing: 14) {
            ForEach(runs, id: \.first!.id) { run in
                let mine = run[0].from == me.username
                VStack(alignment: mine ? .trailing : .leading, spacing: 4) {
                    Text(mine ? t("Ты") : nameOf(run[0].from)).font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                    ForEach(run) { m in bubble(m, mine: mine, thread: current) }
                }
                .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
            }
        }
        composer
    }

    private func bubble(_ m: DMMessage, mine: Bool, thread: DMThread?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let reply = m.replyTo {
                Text(DMCore.replyPreview(messages.first { $0.id == reply }, max: 60) ?? t("Сообщение удалено"))
                    .font(.system(size: 12)).foregroundStyle(Theme.textTertiary).lineLimit(1)
                    .padding(.leading, 8)
                    .overlay(alignment: .leading) { Rectangle().fill(Theme.line).frame(width: 2) }
            }
            if m.deleted {
                Text(t("Сообщение удалено")).italic().foregroundStyle(Theme.textTertiary)
            } else {
                if !m.text.isEmpty {
                    Text(m.text).font(.system(size: 15)).foregroundStyle(Theme.text).textSelection(.enabled)
                }
                ForEach(Array(m.attachments.enumerated()), id: \.offset) { _, a in attachment(a) }
            }
            HStack(spacing: 4) {
                Text(m.sentAt.formattedTime + (m.editedAt != nil ? " · \(t("изменено"))" : ""))
                if let thread, DMCore.seenByPeer(thread, m, me: me.username) { SonarIcon(.check, size: 11) }
            }
            .font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(mine ? Theme.accentSoft : Theme.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contextMenu {
            if !m.deleted {
                Button(t("Ответить")) { replyTo = m.id }
                if DMCore.canDelete(m, me: me.username) {
                    Button(t("Удалить"), role: .destructive) {
                        if let next = DMCore.delete(m, me: me.username) { replace(next) }
                    }
                }
            }
        }
    }

    @ViewBuilder private func attachment(_ a: DMAttachment) -> some View {
        switch a {
        case let .track(ref, title, artist, cover):
            HStack(spacing: 10) {
                CoverImage(url: cover, cornerRadius: 8).frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.text).lineLimit(1)
                    Text(artist).font(.system(size: 12)).foregroundStyle(Theme.textTertiary).lineLimit(1)
                }
                Spacer(minLength: 8)
                CircleButton(icon: .play, size: 34, iconSize: 14, label: t("Играть")) { play(ref) }
                CircleButton(icon: .queue, size: 34, iconSize: 14, label: t("В очередь")) { enqueue(ref) }
            }
            .padding(6)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        case let .room(_, _, title):
            HStack(spacing: 10) {
                SonarIcon(.userHeart, size: 20).foregroundStyle(Theme.textSecondary).frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.text).lineLimit(1)
                    Text(t("Приглашение в комнату")).font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                }
                Spacer(minLength: 8)
                Button(t("Войти")) { tab = .room }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.accentInk)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(Theme.accent, in: Capsule())
                    .buttonStyle(PressableStyle(scale: 0.95))
            }
            .padding(6)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        case let .playlist(_, title, _, cover):
            HStack(spacing: 10) {
                CoverImage(url: cover, cornerRadius: 8).frame(width: 44, height: 44)
                Text(title).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.text)
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let replyTo {
                HStack(spacing: 6) {
                    SonarIcon(.share, size: 12)
                    Text(DMCore.replyPreview(messages.first { $0.id == replyTo }) ?? "").lineLimit(1)
                    Spacer()
                    Button { self.replyTo = nil } label: { SonarIcon(.close, size: 12) }
                        .accessibilityLabel(t("Отмена"))
                }
                .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            }
            HStack(spacing: 8) {
                CircleButton(icon: .music, size: 40, iconSize: 18, label: t("Прикрепить, что играет")) { send(attachCurrent: true) }
                    .disabled(engine.current == nil)
                    .opacity(engine.current == nil ? 0.4 : 1)
                TextField(t("Сообщение…"), text: $draft, axis: .vertical)
                    .lineLimit(1 ... 4)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Theme.raised, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .onSubmit { send() }
                CircleButton(icon: .arrowUp, size: 40, iconSize: 18, filled: true, label: t("Отправить")) { send() }
            }
            Text(t("Сообщения не шифруются сквозным шифрованием: их увидит сервер Sonar."))
                .font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
        }
    }

    // MARK: — действия

    private func build() {
        if built && room != nil && room?.closed == false { return }
        built = true
        let now = Self.ms(.now)
        room = tracks.isEmpty ? nil : SocialDemo.room(members: members, tracks: tracks, now: now)
        let lines = SocialDemo.Lines(hey: t("Слушай, что скажешь про этот?"), fire: t("Огонь, кинул в Любимые"),
                                     join: t("Залетай, включил свои любимые"), room: t("Я тут, слышу всё синхронно"))
        let chat = SocialDemo.chat(me: me.username, tracks: tracks, roomTitle: roomTitle, lines: lines, now: now)
        threads = chat.threads
        messages = chat.messages
        viewer = me.username
    }

    private func act(_ op: RoomOp) {
        guard let room else { return }
        switch RoomCore.apply(room, by: viewer, op, serverNow: Self.ms(.now)) {
        case let .success(next):
            withAnimation(Motion.spring) { self.room = next }
            Haptics.select()
        case let .failure(error):
            if let key = error.message { flash(t(key)) }
            else if case .suggest = op { flash(t("Предложение увидят лидер и диджеи, когда у Sonar появится сервер")) }
        }
    }

    private func send(attachCurrent: Bool = false) {
        var attachments: [DMAttachment] = []
        if attachCurrent, let current = engine.current { attachments.append(SocialDemo.track(current)) }
        for link in DMCore.parseLinks(draft) where link.kind == .track {
            if let track = byRef[link.value] { attachments.append(SocialDemo.track(track)) }
        }
        switch DMCore.checkDraft(draft, attachments: attachments) {
        case let .success(text):
            let now = Self.ms(.now)
            messages.append(DMMessage(id: "local_\(now)", threadID: thread, from: me.username, text: text,
                                      attachments: attachments, replyTo: replyTo, sentAt: now))
            draft = ""
            replyTo = nil
        case .failure(.tooLong): flash(t("Слишком длинное сообщение"))
        case .failure(.tooMany): flash(t("Не больше четырёх вложений"))
        case .failure(.empty): break
        }
    }

    private func replace(_ msg: DMMessage) {
        if let i = messages.firstIndex(where: { $0.id == msg.id }) { messages[i] = msg }
    }

    private func markRead(_ id: String) {
        if let i = threads.firstIndex(where: { $0.id == id }) { threads[i].myReadAt = Self.ms(.now) }
    }

    private func play(_ ref: String) {
        guard let track = byRef[ref] else { return flash(t("Этого трека нет в твоей медиатеке — с сервером найдём через резерв")) }
        engine.play([track], at: 0, context: t("Из сообщений"), tapped: true)
    }

    private func enqueue(_ ref: String) {
        guard let track = byRef[ref] else { return flash(t("Этого трека нет в твоей медиатеке — с сервером найдём через резерв")) }
        engine.enqueue(track, next: false)
        flash(t("Добавлено в очередь"))
    }

    private func flash(_ text: String) {
        notice = text
        Task {
            try? await Task.sleep(for: .seconds(2.6))
            if notice == text { notice = nil }
        }
    }

    private static func ms(_ date: Date) -> Int { Int(date.timeIntervalSince1970 * 1000) }

    private static func clock(_ ms: Int) -> String {
        let s = ms / 1000
        return "\(s / 60):\(String(format: "%02d", s % 60))"
    }
}

private extension Int {
    /// «16:05» из миллисекунд.
    var formattedTime: String {
        Date(timeIntervalSince1970: Double(self) / 1000).formatted(date: .omitted, time: .shortened)
    }
}
