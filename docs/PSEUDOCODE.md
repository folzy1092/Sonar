# Sonar — псевдокод ключевых частей

Не настоящий код, а скелет логики: что в каком порядке и где края.

## 1. Регистрация и вход (сервер)

```python
def register(login, password, device, ip):
    ratelimit("register", ip, 5, per=HOUR)
    login = login.strip().lower()
    require re.fullmatch(r"[a-z0-9_.]{3,32}", login)      else 400 bad_login
    require len(password) >= 8                             else 400 weak_password
    require not users.exists(login=login or username=login) else 409 login_taken
    user = users.create(login, username=login, display_name=login,
                        number=next_number(), password_hash=argon2(password))
    return new_session(user, device)

def login(login, password, device, ip):
    ratelimit("login", (ip, login), 5, per=15*MIN)
    user = users.get(login=login.lower())
    if not user or not user.password_hash or not argon2_verify(user.password_hash, password):
        argon2_dummy_verify()           # одинаковое время ответа
        raise 401 bad_credentials
    if user.banned: raise 403 banned
    return new_session(user, device)

def new_session(user, device):
    token = token_urlsafe(32)
    sessions.create(user, sha256(token), device)
    return {"session": token, "user": user.public()}
```

## 2. Быстрый вход через Telegram

```python
# сервер
def tg_start(purpose, device, current_user=None):
    if purpose == "link": require current_user
    secret = token_urlsafe(16)
    req = tg_requests.create(purpose, sha256(secret), device,
                             user_id=current_user?.id, expires=now+10*MIN)
    return {"request_id": req.id,
            "link": f"https://t.me/{BOT}?start={purpose}_{secret}",
            "expires_at": req.expires_at}

def tg_poll(request_id):
    req = tg_requests.get(request_id) or 404
    if req.expires_at < now and req.status == "pending": req.status = "expired"
    if req.status == "approved" and req.session_plain:
        session, req.session_plain = req.session_plain, None   # отдаём один раз
        return {"status": "approved", "session": session, "user": ...}
    return {"status": req.status}

# бот
on /start payload:
    purpose, secret = payload.split("_", 1)
    req = tg_requests.find(sha256(secret), status="pending", not expired)
    if not req: reply("Ссылка устарела. Запроси новую в приложении."); return
    tg = message.from_user
    if purpose == "link":
        require users.get(tg_id=tg.id) is None else reply("Этот Telegram уже привязан к другому аккаунту")
        users.update(req.user_id, tg_id=tg.id, tg_username=tg.username)
        req.status = "approved"; reply("Telegram привязан ✅"); return
    user = users.get(tg_id=tg.id)
    if user:
        ask(f"Войти в Sonar как @{user.username} на «{req.device.name}»?\n"
            "Если ссылку прислал кто-то другой — не нажимай.",
            buttons=[("Войти", approve(req, user)), ("Это не я", reject(req))])
    else:
        login = free_login(tg.username or f"tg{tg.id}")
        ask(f"Аккаунта ещё нет. Создать @{login}?",
            buttons=[("Создать", create_and_approve(req, tg, login)), ("Отмена", reject(req))])

def approve(req, user):
    req.user_id = user.id
    req.session_plain = new_session(user, req.device)["session"]
    req.status = "approved"

# приложение
func quickLogin():
    r = await api.tgStart(purpose: .login, device: .current)
    show LinkSheet(link: r.link, onCopy: copy, onOpen: openURL, onBack: cancel)
    while sheet.visible && now < r.expiresAt:
        s = await api.tgPoll(r.requestId)
        switch s.status:
          case .approved: keychain.session = s.session; appState.signIn(s.user); return
          case .rejected, .expired: sheet.showError(...); return
          default: sleep 2s
```

## 3. Поток трека (сервер)

```python
def stream(user, ref, quality):
    src, id = ref.split(":", 1)
    provider = registry.for_user(user, src)        # 400 service_not_connected, если нет токена
    key = (user.id, ref, quality)
    if cached := stream_cache.get(key) and cached.expires_at - now > 60*SEC:
        return cached
    info = provider.stream(id, quality)            # 502/503 с понятным текстом при ошибке
    stream_cache[key] = info
    return info

# soundcloud.stream
def stream(id, quality):
    t = get(f"/tracks/{id}", client_id, auth=f"OAuth {token}")
    if t.policy == "BLOCK": raise unavailable
    options = t.media.transcodings                 # hls aac 160, hls opus 64, progressive mp3 128 ...
    pick = best(options, want=QUALITY_KBPS[quality], prefer=["hls/aac", "progressive/mp3", "hls/opus"])
    url = get(pick.url, client_id, auth).url       # ссылка на CDN, живёт ~5–10 мин
    return StreamInfo(url, protocol=pick.protocol, codec, bitrate, expires_at=parse_expiry(url))

# yandex.stream
def stream(id, quality):
    infos = client.tracks_download_info(id, get_direct_links=True)
    pick = best(infos, want=QUALITY_KBPS[quality], prefer=["flac", "aac", "mp3"])
    return StreamInfo(pick.direct_link, "progressive", pick.codec, pick.bitrate,
                      expires_at=now+60*MIN, gain_db=-14 - track.r128.i if track.r128 else None)
```

## 4. Очередь и воспроизведение (iOS)

```swift
@Observable final class QueueManager {
    var items: [QueueItem]; var index: Int; var shuffle, repeat
    var context: PlayContext

    func play(tracks, startAt i, context) {
        items = settings.queue.addFollowing ? tracks[i...] : [tracks[i]]
        index = 0; self.context = context
        engine.load(current, next: peekNext())
        reporter.trackStarted(current, context)
    }
    func playNext(_ t) { items.insert(t, at: index + 1); engine.prefetch(peekNext()) }
    func enqueue(_ t)  { items.append(t) }
    func advance() {
        if repeat == .one { engine.seek(0); return }
        if index + 1 < items.count { index += 1 }
        else if repeat == .all { index = 0 }
        else if settings.general.similarAutoplay { items += await api.related(current.ref).prefix(10); index += 1 }
        else { engine.stop(); return }
        engine.load(current, next: peekNext())
    }
}

final class PlaybackEngine {
    let player = AVQueuePlayer()
    func load(_ cur, next) async {
        player.removeAllItems()
        player.insert(await makeItem(cur))
        player.play()
        schedulePrefetch(next, at: cur.duration - 15s)   // бесшовность: следующий уже в очереди
    }
    func makeItem(_ t) async -> AVPlayerItem {
        if let file = audioCache.localFile(t.ref) { return AVPlayerItem(url: file) }
        let s = try await api.stream(t.ref, quality: settings.audio.quality)
        let item = AVPlayerItem(url: s.url)
        if settings.audio.normalize, let g = s.gainDb { item.audioMix = volumeMix(pow(10, g/20)) }
        if settings.storage.cacheTracks { audioCache.captureWhilePlaying(item, t) }
        return item
    }
    on itemFailed(err): if err is 403/410 && !retried { reload with fresh stream } else { toast; queue.advance() }
    on itemDidPlayToEnd: queue.advance()
}
```

## 5. Учёт прослушиваний и «сейчас играет» (iOS)

```swift
final class PlayReporter {
    var listened = 0, counted = false
    on tick(1s) while playing:
        listened += 1s
        if !counted && listened >= min(30s, duration/2) {
            counted = true
            pending.append(Play(ref, playedAt: startTime, listenedMs, context))
            flushSoon()                      // пачкой, офлайн — копим в SwiftData
        }
    on trackStarted / pause / play / seek / queueChanged: sendState()
    every 30s while playing: sendState()     // heartbeat для /oauth/now
    func sendState() { api.putPlayerState(ref, isPlaying, position, queue, clientTs: now) }
}
```

## 6. `/oauth/now` (сервер)

```python
def now(api_key):
    user = api_keys.user_by_hash(sha256(api_key)) or 401
    st = player_state.get(user.id)
    if not st or not st.ref: return {"is_playing": False, "position_ms": 0, "state": "stopped",
                                     "track": None, "updated_at": now_ms()}
    stale = now_ms() - st.updated_at > 90_000
    playing = st.is_playing and not stale
    pos = st.position_ms + (now_ms() - st.updated_at if playing else 0)
    t = tracks.get(st.ref)
    pos = min(pos, t.duration_ms)
    state = "playing" if playing else "paused"
    src, id = st.ref.split(":", 1)
    track = {"artist": t.artist, "context": st.context, "cover_art": t.cover_url,
             "duration": t.duration_ms // 1000, "duration_ms": t.duration_ms,
             "id": id, "track_id": id, "is_playing": playing, "position_ms": pos,
             "source": {"sc": "soundcloud", "ym": "yandex"}[src],
             "title": t.title, "updated_at": st.updated_at}
    return {"is_playing": playing, "position_ms": pos, "state": state,
            "track": track, "updated_at": st.updated_at}
```

## 7. Синхронизация (iOS + сервер)

```swift
// клиент
final class SyncEngine {
    func record(_ op: Op) { local.apply(op); ops.append(op); pushSoon() }   // оптимистично
    func push() async {
        let batch = ops.prefix(200)
        let r = try await api.syncPush(batch)
        ops.remove(r.applied); lastRev = max(lastRev, r.rev)
    }
    func pull() async {                     // при запуске, при возврате в приложение, раз в 60 с
        let r = try await api.syncPull(since: lastRev)
        for c in r.changes where !ops.contains(key: c.key) { local.apply(c) }   // свои неотправленные важнее
        lastRev = r.rev
    }
}
```
```python
# сервер
def push(user, ops):
    applied = []
    with transaction():
        for op in ops:
            cur = store.get(user, op.type, op.key)
            if cur and cur.client_ts > op.client_ts: applied.append(op.op_id); continue   # старее — игнор
            store.put(user, op.type, op.key, op.value, client_ts=op.client_ts, rev=next_rev())
            applied.append(op.op_id)
    return {"rev": current_rev(), "applied": applied}

def pull(user, since):
    return {"rev": current_rev(), "changes": store.changed_after(user, since)}  # с tombstones
```

## 8. Цвет из обложки (iOS)

```swift
func accent(from image: UIImage) -> Color {
    let px = image.resized(64, 64).rgbPixels()
    let clusters = kmeans(px, k: 5, iterations: 8)
    let candidates = clusters.filter { $0.hsl.l in 0.15...0.85 && $0.hsl.s > 0.2 }
    let best = candidates.max { score($0) < score($1) } ?? clusters.max(by: share)!
    var c = best.color
    if contrast(c, .black) < 4.5 && contrast(c, .white) < 4.5 { c = c.adjustLightness(to: 0.6) }
    return c
}
func score(_ k) = k.hsl.s * sqrt(k.share)
// ThemeStore: на смену трека → accent(from:) в фоне → withAnimation(.easeInOut(0.4)) { accent = c }
// кэш: ref → цвет (чтобы не считать снова)
```

## 9. Жесты (iOS)

```swift
struct SwipeActionRow<Content>: View {
    let context: GestureContext     // .library / .queue / .mini / .player
    // порог 30% ширины → хаптик → действие из settings.gestures[context][direction]
    func perform(_ a: GestureAction, on t: Track) {
        switch a {
        case .off: break
        case .like: library.toggleLike(t)
        case .enqueue: queue.enqueue(t)
        case .playNext: queue.playNext(t)
        case .next: queue.advance()
        case .previous: queue.back()           // >3 с от начала → в начало трека
        case .delete: context.remove(t); showUndo(4s)
        }
    }
}
// Обложка: TapGesture(count: 3) имеет приоритет над count: 2 (exclusively(before:)), иначе тройной не сработает
```

## 10. Автообновление (iOS, порт Shadow)

```swift
func checkUpdate() async {
    let u = try await get("https://raw.githubusercontent.com/folzy1092/Sonar/main/updates/update.json")
    guard u.enabled, u.build > Bundle.build else { return }
    banner.show(u)                                      // «Доступно обновление 1.2.0»
}
func install(_ u) async {
    guard let cert = signingStore.load() else { offerDownloadIPA(u.url); return }   // p12 + пароль + профиль
    let ipa = try await download(u.url, progress: ui.progress)
    let app = try BundlePreparer.unpack(ipa)
    try Zsign.sign(app, p12: cert.p12, password: cert.password, profile: cert.profile)
    let signed = try zip(app)
    let server = try InstallServer.start(serving: signed)        // 127.0.0.1:port
    let manifest = "\(api.baseURL)/updates/manifest.plist?ipa=\(server.ipaURL)&build=\(u.build)"
    beginBackgroundTask()                                         // iOS забирает IPA, пока мы живы
    present(SFSafariViewController(url: server.installPage(manifest)))   // itms-services://...
}
```

## 11. «Моя волна» (сервер)

```python
def wave_start(user, source="auto"):
    src = source if source != "auto" else (
        "ym" if user.has("yandex") and setting(user, "general.platform") == "yandex" else
        "sc" if user.has("soundcloud") else "ym")
    if src == "ym" and ROTOR_MODE != "off":           # ROTOR_MODE = session | station | off — по итогам check_rotor.py
        y = yandex(user)
        if ROTOR_MODE == "session":
            r = y.post("/rotor/session/new", {"seeds": ["user:onyourwave"], "includeTracksInResponse": True})
            ext_id, tracks = r.radioSessionId, r.sequence.tracks
        else:
            y.post("/rotor/station/user:onyourwave/feedback", {"type": "radioStarted"})
            r = y.get("/rotor/station/user:onyourwave/tracks"); ext_id, tracks = r.batchId, r.sequence.tracks
    else:
        src, ext_id = "own", None
        tracks = own_wave_portion(user, sess=None)
    session = waves.create(user, src, ext_id, queue=tracks, played=[], artist_skips={})
    return {"session_id": session.id, "tracks": tracks}

def wave_feedback(session, event, ref, played_ms):
    if session.src == "ym": send_rotor_feedback(session, event, ref, played_ms)
    if event == "dislike": blacklist(session.user, ref)
    if event == "skip" and played_ms < 30_000:
        a = artist(ref); session.artist_skips[a] += 1
        if session.artist_skips[a] >= 2: session.paused_artists.add(a)   # артист на паузу до конца сессии
    session.played.append(ref)
    if session.remaining() <= 2:
        more = (rotor_next(session) if session.src == "ym" else own_wave_portion(session.user, session))
        return {"tracks": more}
    return {"tracks": []}

def own_wave_portion(user, sess, n=10):
    seeds = last_likes(user, 15) + last_finished(user, 10)            # «вкус сейчас»
    explore = sample(old_likes(user), 2)                             # 10–20 % разведки
    cands = flatten(related(s) for s in sample(seeds, 5) + explore)
    cands = [t for t in dedupe(cands)
             if not played_recently(user, t, days=7) and not blacklisted(user, t)
             and (not sess or artist(t) not in sess.paused_artists)]
    score = lambda t: (2 * liked_artist(user, t) + finished_rate(user, artist(t))
                       - skip_rate(user, artist(t)) + random(0, 0.5))  # немного случайности
    out = []
    for t in sorted(cands, key=score, reverse=True):
        if out and artist(out[-1]) == artist(t): continue           # не два подряд
        if count(artist(t), out) >= 2: continue                     # не больше 2 на порцию
        out.append(t)
        if len(out) == n: break
    return out
```
