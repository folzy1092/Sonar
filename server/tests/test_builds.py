"""Сборки из админки (SERVER_PROMPT этап 7): выпуск с GitHub, каналы, отзыв, раздача файлов и манифестов."""
import hashlib
import re
from asyncio import run

import pytest
from fastapi.testclient import TestClient

from sonar import builds
from sonar.admin.auth import AdminAuth
from sonar.builds import BuildError, GitHub
from sonar.config import Settings
from sonar.web import create_app

NOTES = {"ru": "Новое", "en": "New", "uk": "", "es": "", "de": "Neu", "pl": ""}
EXE = b"MZ-fake-installer" * 100
IPA = b"PK-fake-ipa" * 100


def win_release(tag, size=len(EXE)):
    v = tag.removeprefix("windows-v")
    return {"tag_name": tag, "name": f"Sonar {v}", "body": "CI notes", "assets": [
        {"name": f"Sonar_{v}_x64-setup.exe", "url": f"https://api.github.com/a/{tag}/exe", "size": size},
        {"name": f"Sonar_{v}_x64-setup.exe.sig", "url": f"https://api.github.com/a/{tag}/sig", "size": 10}]}


def ios_release(tag, version="0.2.0"):
    return {"tag_name": tag, "name": f"Sonar {version} ({tag.removeprefix('ios-build-')})", "assets": [
        {"name": "Sonar.ipa", "url": f"https://api.github.com/a/{tag}/ipa", "size": len(IPA)}]}


class FakeGitHub(GitHub):
    def __init__(self, releases):
        super().__init__(None)
        self.by_tag = {r["tag_name"]: r for r in releases}
        self.feeds = {}          # адрес → JSON, который «отдаёт GitHub» (бета-канал)
        self.feed_calls = 0

    async def json_file(self, url, limit=builds.FEED_MAX_BYTES):
        self.feed_calls += 1
        if url not in self.feeds:
            raise BuildError("github")
        return self.feeds[url]

    async def releases(self):
        return list(self.by_tag.values())

    async def release(self, tag):
        builds.platform_of(tag)
        if tag not in self.by_tag:
            raise BuildError("no_release")
        return self.by_tag[tag]

    async def download(self, url, dest, limit=builds.MAX_BYTES):
        data = b"SIGNATURE-" + url.encode() if url.endswith("/sig") else IPA if url.endswith("/ipa") else EXE
        if len(data) > limit:
            raise BuildError("too_big")
        dest.write_bytes(data)
        return len(data), hashlib.sha256(data).hexdigest()


TAGS = ["windows-v0.1.10", "windows-v0.1.11", "windows-v0.1.12", "windows-v0.1.13", "ios-build-751"]


@pytest.fixture
def gh():
    return FakeGitHub([win_release(t) for t in TAGS[:4]] + [ios_release(TAGS[4])])


@pytest.fixture
def client(con, tmp_path, gh):
    password = AdminAuth(con).ensure_factory()  # до create_app: иначе пароль уйдёт только в журнал
    app = create_app(con, Settings(data_dir=tmp_path))
    app.state.github = gh
    c = TestClient(app, base_url="http://testserver")
    c.factory_password = password
    return c


def beta_headers(con, login="folzy", token="btok", banned=0):
    """Заголовки пользователя с сессией: бета отдаётся только своим логинам (`SONAR_BETA_USERS`, по умолчанию folzy)."""
    from sonar import sessions
    from sonar.db import now_ms
    uid = f"u_{login}"
    con.execute("INSERT OR IGNORE INTO users (id, number, login, username, display_name, created_at, banned) VALUES (?,?,?,?,?,?,?)",
                (uid, abs(hash(login)) % 10**6, login, login, login, now_ms(), banned))
    con.execute("INSERT INTO sessions (id, user_id, token_hash, device_id, device_name, platform, created_at, last_seen_at)"
                " VALUES (?,?,?,?,?,?,?,?)", (f"s_{token}", uid, sessions._h(token), f"dev-{token}", "ПК", "windows", now_ms(), now_ms()))
    return {"Authorization": f"Bearer {token}", "X-Sonar-Channel": "beta"}


def pub(con, tmp_path, gh, tag, channel="release", notes=NOTES):
    return run(builds.publish(con, tmp_path, gh, tag, channel, notes, "folzy"))


def test_publish_windows_keeps_signature_and_file(con, tmp_path, gh):
    b = pub(con, tmp_path, gh, "windows-v0.1.10")
    assert (b.platform, b.channel, b.version, b.build) == ("windows", "release", "0.1.10", None)
    assert b.signature == "SIGNATURE-https://api.github.com/a/windows-v0.1.10/sig"
    assert b.notes == {"ru": "Новое", "en": "New", "de": "Neu"}
    assert builds.file_path(tmp_path, b).read_bytes() == EXE
    assert b.sha256 == hashlib.sha256(EXE).hexdigest() and b.size == len(EXE)


def test_publish_ios_takes_version_from_title(con, tmp_path, gh):
    b = pub(con, tmp_path, gh, "ios-build-751", "beta")
    assert (b.platform, b.channel, b.version, b.build, b.signature) == ("ios", "beta", "0.2.0", 751, None)


def test_publish_rejects_bad_input(con, tmp_path, gh):
    for tag, chan, notes, code in [("../../etc", "release", NOTES, "bad_tag"),
                                   ("windows-v0.1.10", "nightly", NOTES, "bad_channel"),
                                   ("windows-v0.1.10", "release", {**NOTES, "en": " "}, "no_notes"),
                                   ("windows-v0.1.10", "release", {**NOTES, "ru": "x" * 4001}, "too_long"),
                                   ("windows-v9.9.9", "release", NOTES, "no_release")]:
        with pytest.raises(BuildError) as err:
            pub(con, tmp_path, gh, tag, chan, notes)
        assert err.value.code == code
    assert builds.listing(con) == []


def test_plan_needs_assets():
    with pytest.raises(BuildError, match="no_assets"):
        builds.plan({**win_release("windows-v0.1.10"), "assets": win_release("windows-v0.1.10")["assets"][:1]})
    with pytest.raises(BuildError, match="no_version"):
        builds.plan({**ios_release("ios-build-1"), "name": "whatever"})
    with pytest.raises(BuildError, match="no_assets"):
        builds.plan({**ios_release("ios-build-1"), "assets": []})


def test_size_mismatch_is_not_published(con, tmp_path):
    gh = FakeGitHub([win_release("windows-v0.1.10", size=5)])
    with pytest.raises(BuildError, match="github"):
        pub(con, tmp_path, gh, "windows-v0.1.10")
    assert builds.listing(con) == []


def test_keeps_last_three_per_channel_and_deletes_files(con, tmp_path, gh):
    first = pub(con, tmp_path, gh, "windows-v0.1.10")
    for tag in TAGS[1:4]:
        pub(con, tmp_path, gh, tag)
    pub(con, tmp_path, gh, "windows-v0.1.10", "beta")  # другой канал не считается
    rel = [b.tag for b in builds.listing(con) if b.channel == "release"]
    assert sorted(rel) == ["windows-v0.1.11", "windows-v0.1.12", "windows-v0.1.13"]
    assert not builds.build_dir(tmp_path, "release", "windows", first.tag).exists()
    assert builds.file_path(tmp_path, builds.pinned(con, "windows", "beta", "windows-v0.1.10")).exists()


def test_republish_restores_and_updates_notes(con, tmp_path, gh):
    b = pub(con, tmp_path, gh, "windows-v0.1.10")
    builds.set_revoked(con, b.id, True)
    again = pub(con, tmp_path, gh, "windows-v0.1.10", notes={**NOTES, "en": "Fixed"})
    assert (again.id, again.revoked, again.notes["en"]) == (b.id, False, "Fixed")
    with pytest.raises(BuildError, match="no_build"):
        builds.set_revoked(con, 999, True)


def test_republish_old_build_keeps_newer_current(con, tmp_path, gh):
    pub(con, tmp_path, gh, "windows-v0.1.10")
    pub(con, tmp_path, gh, "windows-v0.1.11")
    pub(con, tmp_path, gh, "windows-v0.1.10", notes={**NOTES, "en": "Typo fixed"})
    assert builds.current(con, "windows", "release").tag == "windows-v0.1.11"


def test_beta_keeps_higher_version_after_release_hotfix(con, tmp_path, gh):
    pub(con, tmp_path, gh, "windows-v0.1.12", "beta")
    pub(con, tmp_path, gh, "windows-v0.1.11", "release")  # хотфикс релиза позже беты
    assert builds.current(con, "windows", "beta").tag == "windows-v0.1.12"
    assert builds.current(con, "windows", "release").tag == "windows-v0.1.11"


def test_failed_publish_of_new_tag_leaves_no_folder(con, tmp_path, gh):
    async def broken_sig(url, dest, limit=builds.MAX_BYTES):
        if url.endswith("/sig"):
            raise BuildError("github")
        return await FakeGitHub.download(gh, url, dest, limit)
    gh.download = broken_sig
    with pytest.raises(BuildError, match="github"):
        pub(con, tmp_path, gh, "windows-v0.1.10")
    assert not builds.build_dir(tmp_path, "release", "windows", "windows-v0.1.10").exists()


def test_beta_sees_newer_release_release_ignores_beta(con, tmp_path, gh):
    pub(con, tmp_path, gh, "windows-v0.1.10", "beta")
    assert builds.current(con, "windows", "release") is None
    assert builds.current(con, "windows", "beta").tag == "windows-v0.1.10"
    pub(con, tmp_path, gh, "windows-v0.1.11", "release")
    assert builds.current(con, "windows", "beta").tag == "windows-v0.1.11"


def test_windows_feed_tauri_format_channel_header_and_lang(client, con, tmp_path, gh):
    assert client.get("/api/updates/windows/release.json").status_code == 404, "404 — tauri идёт на GitHub"
    pub(con, tmp_path, gh, "windows-v0.1.10", "beta")
    assert client.get("/api/updates/windows/release.json").status_code == 404
    # Бета без права (нет сессии) — не 404 «нет канала», а ответ релиза; сборки админки в бете видит только свой логин.
    assert client.get("/api/updates/windows/release.json", headers={"X-Sonar-Channel": "beta"}).status_code == 404
    r = client.get("/api/updates/windows/release.json", headers={**beta_headers(con), "X-Sonar-Lang": "de-DE"})
    j = r.json()
    assert r.headers["cache-control"] == "no-cache"
    assert (j["version"], j["notes"]) == ("0.1.10", "Neu")
    assert re.fullmatch(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ", j["pub_date"])
    win = j["platforms"]["windows-x86_64"]
    assert win["url"] == "https://try-sonar.ru/downloads/beta/windows-v0.1.10/Sonar-setup.exe"
    assert win["signature"].startswith("SIGNATURE-")
    # язык без описания — английское; стабильный канал старым именем
    assert client.get("/api/updates/windows/beta.json?lang=pl", headers=beta_headers(con, token="b2")).json()["notes"] == "New"
    pub(con, tmp_path, gh, "windows-v0.1.11")
    assert client.get("/api/updates/windows/x.json", headers={"X-Sonar-Channel": "stable"}).json()["version"] == "0.1.11"
    assert client.get("/api/updates/windows/nightly.json").status_code == 404


def test_ios_feed_format(client, con, tmp_path, gh):
    pub(con, tmp_path, gh, "ios-build-751")
    j = client.get("/api/updates/ios/release.json?lang=ru").json()
    assert j == {"enabled": True, "build": 751, "version": "0.2.0", "minimum_build": 0, "title": "Sonar 0.2.0",
                 "notes": "Новое", "ipa_url": "https://try-sonar.ru/downloads/release/ios-build-751/Sonar.ipa",
                 "url": "https://try-sonar.ru/#download"}


def test_downloads_fallback_current_pinned_and_revoked(client, con, tmp_path, gh):
    r = client.get("/downloads/release/Sonar-setup.exe", follow_redirects=False)
    assert (r.status_code, r.headers["location"]) == (302, builds.FALLBACK["windows"])
    b = pub(con, tmp_path, gh, "windows-v0.1.10")
    r = client.get("/downloads/release/Sonar-setup.exe")
    assert r.content == EXE and r.headers["content-type"] == "application/octet-stream"
    assert 'filename="Sonar-setup.exe"' in r.headers["content-disposition"]
    assert client.get("/downloads/release/windows-v0.1.10/Sonar-setup.exe").content == EXE
    assert client.head("/downloads/release/windows-v0.1.10/Sonar-setup.exe").status_code == 200
    # Range и ETag — докачка и кэш
    part = client.get("/downloads/release/Sonar-setup.exe", headers={"Range": "bytes=0-1"})
    assert (part.status_code, part.content) == (206, b"MZ")
    assert r.headers["etag"] and r.headers["accept-ranges"] == "bytes"
    # чужие имена и пути
    for path in ("/downloads/release/passwd", "/downloads/release/windows-v0.1.10/Sonar.ipa",
                 "/downloads/nightly/Sonar-setup.exe", "/downloads/release/..%2F..%2Fdb/Sonar-setup.exe",
                 "/downloads/beta/windows-v0.1.10/Sonar-setup.exe"):
        assert client.get(path, follow_redirects=False).status_code == 404, path
    builds.set_revoked(con, b.id, True)
    assert client.get("/downloads/release/windows-v0.1.10/Sonar-setup.exe").status_code == 404
    assert client.get("/downloads/release/Sonar-setup.exe", follow_redirects=False).status_code == 302


def test_manifest_only_own_ipa_and_escaped(client):
    ok = client.get("/api/updates/manifest.plist", params={
        "fetchurl": "https://try-sonar.ru/downloads/release/ios-build-751/Sonar.ipa", "name": 'S<o>"nar',
        "version": "0.2.0"})
    assert ok.status_code == 200 and ok.headers["content-type"].startswith("application/xml")
    assert "S&lt;o&gt;&quot;nar" in ok.text and "<string>com.folzy.sonar</string>" in ok.text
    assert client.get("/api/updates/manifest.plist",
                      params={"fetchurl": "http://127.0.0.1:8123/Sonar.ipa"}).status_code == 200
    for url in ("https://evil.example/Sonar.ipa", "http://try-sonar.ru/downloads/x.ipa",
                "https://try-sonar.ru/api/secret", "https://try-sonar.ru/downloads/x.ipa?a=1",
                "http://127.0.0.1/Sonar.ipa", "http://localhost:80/x.ipa", ""):
        assert client.get("/api/updates/manifest.plist", params={"fetchurl": url}).status_code == 400, url
    bad = client.get("/api/updates/manifest.plist", params={
        "fetchurl": "http://127.0.0.1:8123/Sonar.ipa", "bundleid": "com.x</string>"})
    assert bad.status_code == 400


def test_hosts_and_token_only_for_github():
    assert builds.allowed("https://objects.githubusercontent.com/x")
    assert builds.allowed("https://release-assets.githubusercontent.com/x")
    for url in ("http://github.com/x", "https://github.com.evil.io/x", "https://evil.io/github.com",
                "file:///etc/passwd", "https://169.254.169.254/"):
        assert not builds.allowed(url), url
    gh = GitHub("ghp_secret")
    assert gh._headers("https://api.github.com/x")["Authorization"] == "Bearer ghp_secret"
    assert "Authorization" not in gh._headers("https://objects.githubusercontent.com/x")
    assert "Authorization" not in GitHub("  ")._headers("https://api.github.com/x")


def test_download_refuses_foreign_host_without_network(tmp_path):
    with pytest.raises(BuildError, match="bad_host"):
        run(GitHub().download("https://evil.io/x", tmp_path / "f"))
    assert list(tmp_path.iterdir()) == []


# ---- админка ----

def admin(client, con):
    from tests.test_admin import NEW_PASSWORD, csrf_of
    password = client.factory_password
    page = client.get("/admin/login")
    client.post("/admin/login", data={"login": "folzy", "password": password, "csrf": csrf_of(page.text)})
    page = client.get("/admin/password")
    client.post("/admin/password", data={"csrf": csrf_of(page.text), "old": password, "new": NEW_PASSWORD,
                                         "again": NEW_PASSWORD})
    return csrf_of(client.get("/admin/builds").text)


def test_admin_publish_revoke_restore_with_audit(client, con):
    token = admin(client, con)
    page = client.get("/admin/builds")
    assert "windows-v0.1.13" in page.text and "ios-build-751" in page.text
    form = client.get("/admin/builds?tag=windows-v0.1.13").text
    assert 'name="tag" value="windows-v0.1.13"' in form and "CI notes</textarea>" in form
    data = {"csrf": token, "tag": "windows-v0.1.13", "channel": "beta", "notes_ru": "Новое", "notes_en": "New"}
    r = client.post("/admin/builds/publish", data=data, follow_redirects=False)
    assert r.headers["location"] == "/admin/builds?m=published"
    b = builds.current(con, "windows", "beta")
    assert b.tag == "windows-v0.1.13" and b.published_by == "folzy"
    r = client.post("/admin/builds/publish", data={**data, "notes_en": ""}, follow_redirects=False)
    assert "e=no_notes" in r.headers["location"] and "tag=windows-v0.1.13" in r.headers["location"]
    assert "e=csrf" in client.post("/admin/builds/publish", data={**data, "csrf": "x"},
                                   follow_redirects=False).headers["location"]
    assert "m=revoked" in client.post(f"/admin/builds/{b.id}/revoke", data={"csrf": token},
                                      follow_redirects=False).headers["location"]
    assert builds.current(con, "windows", "beta") is None
    assert "m=restored" in client.post(f"/admin/builds/{b.id}/restore", data={"csrf": token},
                                       follow_redirects=False).headers["location"]
    actions = [r[0] for r in con.execute("SELECT action FROM admin_audit ORDER BY id")]
    assert {"publish_build", "revoke_build", "restore_build"} <= set(actions)


def test_admin_builds_needs_login(client):
    assert client.get("/admin/builds", follow_redirects=False).headers["location"] == "/admin/login"
    assert client.post("/admin/builds/publish", data={}, follow_redirects=False).status_code in (303, 307)


# ---- бета: только свои, прямо с GitHub; релиз — только с сайта ----

LATEST = {"version": "0.2.272", "notes": "CI", "pub_date": "2026-11-26T05:00:00Z",
          "platforms": {"windows-x86_64": {"signature": "sig", "url": "https://github.com/x/y/releases/download/windows-v0.2.272/Sonar.exe"}}}
IOS_FEED = {"enabled": True, "build": 761, "version": "0.2.1", "minimum_build": 0, "title": "t", "notes": "n",
            "ipa_url": "https://github.com/x/y/releases/download/ios-build-761/Sonar.ipa", "url": "https://x"}


def test_owner_gets_github_beta_and_everyone_else_gets_the_release(client, con, tmp_path, gh):
    gh.feeds[builds.BETA_FEEDS["windows"]] = LATEST
    pub(con, tmp_path, gh, "windows-v0.1.10")                                   # то, что выпущено на сайте
    mine = client.get("/api/updates/windows/release.json", headers=beta_headers(con)).json()
    assert mine == LATEST                                                       # свой логин — сборка CI как есть
    other = beta_headers(con, login="mira", token="m1")
    assert client.get("/api/updates/windows/release.json", headers=other).json()["version"] == "0.1.10"
    # без сессии и со старым клиентом, у которого включена «Бета», — тоже только релиз с сайта
    assert client.get("/api/updates/windows/beta.json").json()["version"] == "0.1.10"
    assert client.get("/api/updates/windows/release.json", headers={"X-Sonar-Channel": "beta"}).json()["version"] == "0.1.10"


def test_beta_ios_feed_from_github(client, con, gh):
    gh.feeds[builds.BETA_FEEDS["ios"]] = IOS_FEED
    assert client.get("/api/updates/ios/beta.json", headers=beta_headers(con)).json() == IOS_FEED
    assert client.get("/api/updates/ios/beta.json").status_code == 404           # чужому бета не светится: релиза нет


def test_banned_owner_session_is_not_beta(client, con, gh):
    gh.feeds[builds.BETA_FEEDS["windows"]] = LATEST
    headers = beta_headers(con, banned=1)
    r = client.get("/api/updates/windows/release.json", headers=headers)
    assert r.status_code == 404                                                  # а не бета


def test_beta_list_comes_from_env(client, con, gh, monkeypatch):
    gh.feeds[builds.BETA_FEEDS["windows"]] = LATEST
    monkeypatch.setenv("SONAR_BETA_USERS", "lev, Mira")
    assert client.get("/api/updates/windows/beta.json", headers=beta_headers(con, "mira", "t1")).json() == LATEST
    assert client.get("/api/updates/windows/beta.json", headers=beta_headers(con, "folzy", "t2")).status_code == 404


def test_beta_is_cached_and_survives_a_github_outage(client, con, gh, monkeypatch):
    gh.feeds[builds.BETA_FEEDS["windows"]] = LATEST
    h = beta_headers(con)
    assert client.get("/api/updates/windows/beta.json", headers=h).json() == LATEST
    assert client.get("/api/updates/windows/beta.json", headers=h).json() == LATEST
    assert gh.feed_calls == 1                                                    # второй раз — из кэша
    monkeypatch.setattr("sonar.api.updates.BETA_CACHE_S", 0)
    gh.feeds.clear()                                                             # GitHub лёг
    assert client.get("/api/updates/windows/beta.json", headers=h).json() == LATEST   # отдаём прежний, не «обновлений нет»


def test_beta_falls_back_to_admin_build_when_github_is_silent_or_odd(client, con, tmp_path, gh):
    h = beta_headers(con)
    pub(con, tmp_path, gh, "windows-v0.1.10", "beta")
    assert client.get("/api/updates/windows/beta.json", headers=h).json()["version"] == "0.1.10"     # GitHub молчит
    gh.feeds[builds.BETA_FEEDS["windows"]] = {"version": "9.9.9"}                # не тот формат: без платформ и подписи
    assert client.get("/api/updates/windows/beta.json", headers=h).json()["version"] == "0.1.10"


def test_github_feed_hosts_are_whitelisted():
    assert builds.allowed(builds.BETA_FEEDS["windows"]) and builds.allowed(builds.BETA_FEEDS["ios"])
    assert not builds.allowed("https://raw.githubusercontent.com.evil.example/x.json")
    assert not builds.allowed("http://raw.githubusercontent.com/x.json")
