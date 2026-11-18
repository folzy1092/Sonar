"""server/tools/export_listenbrainz.py без сети: разбор прослушиваний, шаг по времени, стык страниц, продолжение."""

import importlib.util
import io
import json
import urllib.error
from pathlib import Path

import pytest

TOOLS = Path(__file__).resolve().parents[1] / "tools"
SPEC = importlib.util.spec_from_file_location("export_listenbrainz", TOOLS / "export_listenbrainz.py")
export_lb = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(export_lb)

USER = "folzy"
QUIET = lambda *_: None  # noqa: E731


def listen(ts, title, artist="Artist", album="Album", mbid=""):
    return {
        "listened_at": ts,
        "track_metadata": {
            "artist_name": artist,
            "track_name": title,
            "release_name": album,
            "additional_info": {"recording_mbid": mbid} if mbid else {},
        },
    }


def server(history, per_page):
    """Как ListenBrainz: до per_page прослушиваний строго раньше max_ts, от новых к старым."""
    ordered = sorted(history, key=lambda r: -r["ts"])
    calls = []

    def fetch(user, max_ts):
        calls.append(max_ts)
        return [r for r in ordered if r["ts"] < max_ts][:per_page]

    return fetch, calls


def rec(ts, title):
    return {"ts": ts, "artist": "Artist", "title": title, "album": "Album", "mbid": ""}


HISTORY = [rec(500, "e"), rec(400, "d"), rec(300, "c"), rec(200, "b"), rec(100, "a")]


def lines(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines()]


@pytest.fixture
def paths(tmp_path):
    return tmp_path / "out.jsonl", tmp_path / "state.json"


@pytest.fixture(autouse=True)
def fast(monkeypatch):
    monkeypatch.setattr(export_lb, "PAUSE", 0)
    monkeypatch.setattr(export_lb, "BACKOFF", 0)


def run(paths, fetch, per_page=2, user=USER):
    out, state = paths
    return export_lb.export(user, out, state, fetch=fetch, per_page=per_page, log=QUIET, now=lambda: 1000)


def test_to_record_takes_fields_and_mbid_fallback():
    plain = listen(123, "Song", "Band", "LP", "mb-1")
    mapped = listen(124, "Other", album=None)
    mapped["track_metadata"]["mbid_mapping"] = {"recording_mbid": "mb-2"}

    assert export_lb.to_record(plain) == {"ts": 123, "artist": "Band", "title": "Song", "album": "LP", "mbid": "mb-1"}
    assert export_lb.to_record(mapped) == {"ts": 124, "artist": "Artist", "title": "Other", "album": "", "mbid": "mb-2"}


def test_export_walks_back_in_time_until_empty(paths):
    fetch, _ = server(HISTORY, per_page=2)

    count = run(paths, fetch)

    out, state = paths
    assert count == 5
    assert [r["title"] for r in lines(out)] == ["e", "d", "c", "b", "a"]
    assert json.loads(state.read_text())["done"] is True


def test_listens_sharing_a_second_across_pages_are_kept_once(paths):
    history = [rec(300, "x"), rec(200, "p"), rec(200, "q"), rec(200, "r"), rec(100, "z")]
    fetch, _ = server(history, per_page=3)

    count = run(paths, fetch, per_page=3)

    out, _ = paths
    assert count == 5
    assert sorted(r["title"] for r in lines(out)) == ["p", "q", "r", "x", "z"]


def test_more_listens_in_one_second_than_a_page_does_not_loop(paths):
    history = [rec(200, t) for t in "abc"] + [rec(100, "old")]
    fetch, calls = server(history, per_page=2)

    run(paths, fetch)

    out, _ = paths
    assert "old" in [r["title"] for r in lines(out)]
    assert len(calls) < 10


def test_export_resumes_after_break_without_duplicates(paths):
    out, state = paths
    fetch, _ = server(HISTORY, per_page=2)
    seen = []

    def broken(user, max_ts):
        seen.append(max_ts)
        if len(seen) == 2:
            raise KeyboardInterrupt
        return fetch(user, max_ts)

    with pytest.raises(KeyboardInterrupt):
        run(paths, broken)
    with out.open("a", encoding="utf-8") as f:
        f.write('{"ts": 1, "artist": "half')

    count = run(paths, fetch)

    assert count == 5
    assert [r["title"] for r in lines(out)] == ["e", "d", "c", "b", "a"]


def test_finished_export_is_not_repeated(paths):
    fetch, _ = server(HISTORY, per_page=2)
    run(paths, fetch)

    def must_not_fetch(*_):
        raise AssertionError("уже выгружено — сеть не нужна")

    assert run(paths, must_not_fetch) == 5


def test_other_user_state_is_refused(paths):
    fetch, _ = server(HISTORY, per_page=2)
    run(paths, fetch)

    with pytest.raises(SystemExit):
        run(paths, fetch, user="someone")


def test_state_keeps_no_plain_username(paths):
    fetch, _ = server(HISTORY, per_page=2)
    run(paths, fetch)

    _, state = paths
    assert USER not in state.read_text()


class Reply(io.BytesIO):
    def __init__(self, payload):
        super().__init__(json.dumps(payload).encode())

    def __enter__(self):
        return self

    def __exit__(self, *_):
        return False


def http_error(code, headers=None):
    return urllib.error.HTTPError("https://api.listenbrainz.org/x", code, "err", headers or {}, io.BytesIO(b"{}"))


def _next(replies):
    reply = replies.pop(0)
    if isinstance(reply, Exception):
        raise reply
    return reply


def test_fetch_listens_asks_for_page_before_max_ts(monkeypatch):
    asked = []

    def urlopen(request, timeout):
        asked.append(request.full_url)
        return Reply({"payload": {"count": 1, "listens": [listen(99, "Song")]}})

    monkeypatch.setattr(export_lb.urllib.request, "urlopen", urlopen)

    records = export_lb.fetch_listens("a b/c", 100, per_page=1000)

    assert records == [{"ts": 99, "artist": "Artist", "title": "Song", "album": "Album", "mbid": ""}]
    assert asked == ["https://api.listenbrainz.org/1/user/a%20b%2Fc/listens?count=1000&max_ts=100"]


def test_rate_limit_waits_for_reset_and_retries(monkeypatch):
    replies = [http_error(429, {"X-RateLimit-Reset-In": "3"}), Reply({"payload": {"listens": []}})]
    waited = []
    monkeypatch.setattr(export_lb.urllib.request, "urlopen", lambda *_a, **_k: _next(replies))
    monkeypatch.setattr(export_lb.time, "sleep", waited.append)

    assert export_lb.fetch_with_retry(USER, 100, per_page=10, log=QUIET) == []
    assert waited == [4]


def test_unknown_user_is_not_retried(monkeypatch):
    calls = []

    def urlopen(*_a, **_k):
        calls.append(1)
        raise http_error(404)

    monkeypatch.setattr(export_lb.urllib.request, "urlopen", urlopen)

    with pytest.raises(export_lb.ListenbrainzError) as caught:
        export_lb.fetch_with_retry(USER, 100, per_page=10, log=QUIET)
    assert caught.value.code == 404
    assert calls == [1]
