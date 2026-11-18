"""server/tools/export_lastfm.py без сети: разбор страниц, продолжение после обрыва, повторы, ключ не светится."""

import importlib.util
import json
from pathlib import Path

import pytest

SPEC = importlib.util.spec_from_file_location(
    "export_lastfm", Path(__file__).resolve().parents[1] / "tools" / "export_lastfm.py"
)
export_lastfm = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(export_lastfm)

KEY = "0123456789abcdef0123456789abcdef"
USER = "folzy"


def track(ts, title, artist="Artist", album="Album", mbid=""):
    return {
        "name": title,
        "mbid": mbid,
        "artist": {"#text": artist, "mbid": ""},
        "album": {"#text": album, "mbid": ""},
        "date": {"uts": str(ts), "#text": "01 Nov 2026, 10:00"},
    }


def page(tracks, number, pages, total):
    return {
        "recenttracks": {
            "track": tracks,
            "@attr": {"page": str(number), "totalPages": str(pages), "total": str(total), "perPage": "200"},
        }
    }


PAGES = {
    1: page([track(300, "c"), track(299, "b")], 1, 3, 5),
    2: page([track(200, "a2"), track(199, "a1")], 2, 3, 5),
    3: page(track(100, "first"), 3, 3, 5),  # одна запись Last.fm отдаёт объектом, не списком
}


def lines(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines()]


@pytest.fixture
def paths(tmp_path):
    return tmp_path / "out.jsonl", tmp_path / "state.json"


@pytest.fixture(autouse=True)
def no_sleep(monkeypatch):
    monkeypatch.setattr(export_lastfm, "PAUSE", 0)
    monkeypatch.setattr(export_lastfm, "BACKOFF", 0)


def test_parse_page_skips_now_playing_and_keeps_fields():
    playing = {**track(0, "now"), "@attr": {"nowplaying": "true"}}
    playing.pop("date")
    records, pages, total = export_lastfm.parse_page(
        page([playing, track(123, "Song", "Band", "LP", "mb-1")], 1, 1, 1)
    )
    assert records == [{"ts": 123, "artist": "Band", "title": "Song", "album": "LP", "mbid": "mb-1"}]
    assert (pages, total) == (1, 1)


def test_parse_page_empty_history():
    assert export_lastfm.parse_page(page([], 1, 0, 0)) == ([], 0, 0)


def test_export_writes_every_page_in_order(paths):
    out, state = paths
    count = export_lastfm.export(KEY, USER, out, state, fetch=lambda k, u, p, to: PAGES[p], log=lambda *_: None)
    assert count == 5
    assert [r["title"] for r in lines(out)] == ["c", "b", "a2", "a1", "first"]
    assert json.loads(state.read_text())["done"] is True


def test_export_resumes_after_break_without_duplicates(paths):
    out, state = paths
    calls = []

    def broken(k, u, p, to):
        calls.append((p, to))
        if p == 2:
            raise KeyboardInterrupt
        return PAGES[p]

    with pytest.raises(KeyboardInterrupt):
        export_lastfm.export(KEY, USER, out, state, fetch=broken, log=lambda *_: None)
    # обрыв посреди записи: в файле лишняя строка, которой нет в состоянии
    with out.open("a", encoding="utf-8") as f:
        f.write('{"ts": 1, "artist": "half')

    calls.clear()
    count = export_lastfm.export(
        KEY, USER, out, state, fetch=lambda k, u, p, to: calls.append((p, to)) or PAGES[p], log=lambda *_: None
    )
    assert count == 5
    assert [p for p, _ in calls] == [2, 3]
    assert len({to for _, to in calls}) == 1  # та же верхняя граница — страницы не съезжают
    assert [r["title"] for r in lines(out)] == ["c", "b", "a2", "a1", "first"]


def test_finished_export_is_not_repeated(paths):
    out, state = paths
    export_lastfm.export(KEY, USER, out, state, fetch=lambda k, u, p, to: PAGES[p], log=lambda *_: None)

    def must_not_fetch(*_):
        raise AssertionError("уже выгружено — сеть не нужна")

    assert export_lastfm.export(KEY, USER, out, state, fetch=must_not_fetch, log=lambda *_: None) == 5


def test_other_user_state_is_refused(paths):
    out, state = paths
    export_lastfm.export(KEY, USER, out, state, fetch=lambda k, u, p, to: PAGES[p], log=lambda *_: None)
    with pytest.raises(SystemExit):
        export_lastfm.export(KEY, "someone", out, state, fetch=lambda *_: PAGES[1], log=lambda *_: None)


def test_state_keeps_no_plain_username_or_key(paths):
    out, state = paths
    export_lastfm.export(KEY, USER, out, state, fetch=lambda k, u, p, to: PAGES[p], log=lambda *_: None)
    raw = state.read_text()
    assert KEY not in raw and USER not in raw


def test_temporary_errors_are_retried(monkeypatch):
    replies = [export_lastfm.LastfmError(29, "Rate limit"), export_lastfm.LastfmError(8, "Backend"), PAGES[1]]

    def fetch_page(*_):
        reply = replies.pop(0)
        if isinstance(reply, Exception):
            raise reply
        return reply

    monkeypatch.setattr(export_lastfm, "fetch_page", fetch_page)
    assert export_lastfm.fetch_with_retry(KEY, USER, 1, 999) == PAGES[1]


def test_fatal_errors_are_not_retried(monkeypatch):
    calls = []

    def fetch_page(*_):
        calls.append(1)
        raise export_lastfm.LastfmError(10, "Invalid API key")

    monkeypatch.setattr(export_lastfm, "fetch_page", fetch_page)
    with pytest.raises(export_lastfm.LastfmError):
        export_lastfm.fetch_with_retry(KEY, USER, 1, 999)
    assert calls == [1]


def test_log_never_shows_key(paths):
    out, state = paths
    said = []
    export_lastfm.export(KEY, USER, out, state, fetch=lambda k, u, p, to: PAGES[p], log=lambda *a: said.append(" ".join(map(str, a))))
    assert said and all(KEY not in s for s in said)
