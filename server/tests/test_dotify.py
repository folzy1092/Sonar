"""Перенос Любимых из Dotify (`sonar/dotify.py`, бот `/dotify`): разбор файла, без дублей, снятые лайки не возвращаем."""
import asyncio
import json
from types import SimpleNamespace

import pytest

from sonar import dotify
from sonar.bot import handlers as H


def track(tid, source="soundcloud", added=1795341777313, **kw):
    return {"id": tid, "title": f"Трек {tid}", "artist": "kaifik", "duration": 66,
            "cover_art": "https://i1.sndcdn.com/x-t500x500.jpg", "source": source, "liked": True, "url": "",
            "type": "audio", "added_at": added,
            "artists": [{"id": "1233630895", "name": "kaifik", "avatar": "https://a/1.jpg", "source": source}], **kw}


def file(*tracks, title="Любимые") -> bytes:
    return json.dumps({"id": "favorites", "title": title, "tracks_count": len(tracks), "tracks": list(tracks)},
                      ensure_ascii=False).encode()


def test_parse_maps_fields():
    p = dotify.parse(file(track("2442475974"), track("77", source="yandex")))
    sc, ym = p.items
    assert sc.ref == "sc:2442475974" and sc.duration_ms == 66000 and sc.added_at == 1795341777313
    assert json.loads(sc.artists_json) == [{"ref": "sca:1233630895", "name": "kaifik", "avatar_url": "https://a/1.jpg"}]
    assert sc.url is None and sc.cover_url.startswith("https://")
    assert ym.ref == "ym:77" and json.loads(ym.artists_json)[0]["ref"] == "yma:1233630895"


def test_parse_skips_unknown_and_junk():
    p = dotify.parse(file(track("1", source="spotify"), {"id": "../x", "source": "soundcloud", "title": "a"},
                          "мусор", track("2"), track("2")))
    assert [i.ref for i in p.items] == ["sc:2"] and p.unknown == 3  # дубль внутри файла не считается пропуском


@pytest.mark.parametrize("raw", [b"not json", b'{"no": "tracks"}', b"[]", b"\xff\xfe"])
def test_parse_rejects_not_dotify(raw):
    with pytest.raises(dotify.DotifyError):
        dotify.parse(raw)


def test_parse_rejects_big_file():
    with pytest.raises(dotify.DotifyError):
        dotify.parse(b" " * (dotify.FILE_MAX + 1))


def test_future_added_at_is_clamped():
    p = dotify.parse(file(track("1", added=99999999999999)))
    assert p.items[0].added_at < 99999999999999


def test_apply_no_duplicates_and_keeps_removed(acc, con):
    user = asyncio.run(acc.register("mira", "secret-pass"))
    con.execute("INSERT INTO likes (user_id, ref, kind, added_at, deleted, rev) VALUES (?, 'sc:2', 'track', 1, 1, 1)",
                (user.id,))  # снят вручную
    con.execute("INSERT INTO tracks (ref, title, artist, updated_at) VALUES ('sc:3', 'Своё название', 'x', 1)")
    p = dotify.parse(file(track("1"), track("2"), track("3")))
    assert dotify.preview(con, user.id, p) == dotify.Counts(new=2, have=0, removed=1)
    assert dotify.apply(con, user.id, p) == dotify.Counts(new=2, have=0, removed=1)
    assert dotify.apply(con, user.id, p) == dotify.Counts(new=0, have=2, removed=1)  # повтор ничего не удваивает
    rows = {r["ref"]: r for r in con.execute("SELECT * FROM likes WHERE user_id = ?", (user.id,))}
    assert rows["sc:2"]["deleted"] == 1
    assert rows["sc:1"]["added_at"] == 1795341777313 and rows["sc:1"]["kind"] == "track"
    assert rows["sc:1"]["rev"] != rows["sc:3"]["rev"]  # у каждой строки свой rev — синк их увидит
    assert con.execute("SELECT title FROM tracks WHERE ref = 'sc:3'").fetchone()[0] == "Своё название"  # не перетёрли


class FakeShower:
    def __init__(self):
        self.shown = []

    async def send(self, chat_id, screen, reply_to=None):
        self.shown.append(screen)

    async def edit(self, msg, screen):
        self.shown.append(screen)


class FakeState:
    def __init__(self):
        self.data, self.state = {}, None

    async def set_state(self, s):
        self.state = s

    async def update_data(self, **kw):
        self.data.update(kw)

    async def get_data(self):
        return dict(self.data)

    async def clear(self):
        self.data, self.state = {}, None


def test_bot_flow(acc, con, monkeypatch):
    user = asyncio.run(acc.register("mira", "secret-pass"))
    acc.link_tg(user, 777, "mira_tg")
    raw = file(track("1"), track("2"))

    async def download(file_id):
        import io
        return io.BytesIO(raw)

    ctx = SimpleNamespace(accounts=acc, shower=FakeShower(), bot=SimpleNamespace(download=download), settings=None)
    tg = SimpleNamespace(id=777, username="mira_tg")
    msg = SimpleNamespace(chat=SimpleNamespace(id=777), from_user=tg,
                          document=SimpleNamespace(file_id="F1", file_size=len(raw)))
    state = FakeState()

    async def flow():
        await H.cmd_dotify(msg, state, ctx)
        assert state.state == H.Dotify.file
        await H.dotify_file(msg, state, ctx)
        assert "Добавлю в Любимые: <b>2</b>" in ctx.shower.shown[-1].html
        assert con.execute("SELECT COUNT(*) FROM likes").fetchone()[0] == 0  # до «Добавить» ничего не пишем
        await H.dotify_button(SimpleNamespace(data="dot:ok", message=msg, from_user=tg), state, ctx, user)
        assert "добавлено: <b>2</b>" in ctx.shower.shown[-1].html

    asyncio.run(flow())
    assert con.execute("SELECT COUNT(*) FROM likes WHERE user_id = ?", (user.id,)).fetchone()[0] == 2
