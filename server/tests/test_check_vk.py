"""server/tools/check_vk.py без сети: коды ошибок VK, ключ не попадает в вывод."""

import importlib.util
import io
import json
from pathlib import Path

import pytest

SPEC = importlib.util.spec_from_file_location(
    "check_vk", Path(__file__).resolve().parents[1] / "tools" / "check_vk.py"
)
check_vk = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(check_vk)

TOKEN = "vk1.a.SECRET-test-token"


class Reply(io.BytesIO):
    def __init__(self, payload, content_type="application/json"):
        super().__init__(payload if isinstance(payload, bytes) else json.dumps(payload).encode())
        self.headers = {"Content-Type": content_type}

    def __enter__(self):
        return self

    def __exit__(self, *_):
        return False


def fake_vk(monkeypatch, replies, seen):
    """Подменяет urlopen: ответы по имени метода, запросы складывает в seen."""

    def urlopen(req, timeout):
        seen.append(req)
        name = req.full_url.rsplit("/", 1)[-1]
        return Reply(*replies[name]) if isinstance(replies[name], tuple) else Reply(replies[name])

    monkeypatch.setattr(check_vk.urllib.request, "urlopen", urlopen)
    monkeypatch.setattr(check_vk, "PAUSE", 0)


@pytest.mark.parametrize("code", [5, 15, 25, 201, 1117])
def test_auth_codes_ask_to_relogin(code):
    assert "войди заново" in check_vk.explain(code)


def test_other_codes():
    assert "реже" in check_vk.explain(6)
    assert "капча" in check_vk.explain(14)
    assert check_vk.explain(100) == "VK ответил ошибкой"


def test_scrub_hides_token():
    assert TOKEN not in check_vk.scrub(f"bad {TOKEN} here", TOKEN)
    assert check_vk.scrub("plain", "") == "plain"


def test_token_goes_in_body_with_kate_agent(monkeypatch):
    seen = []
    fake_vk(monkeypatch, {"users.get": {"response": [{"id": 1}]}}, seen)
    check_vk.call("users.get", {}, TOKEN)
    req = seen[0]
    assert TOKEN not in req.full_url
    assert f"access_token={TOKEN}".encode() in req.data
    assert req.get_header("User-agent") == check_vk.UA
    assert b"v=5.131" in req.data


def test_full_run_ok_without_printing_token(monkeypatch, capsys):
    seen = []
    track = {"artist": "Земфира", "title": "Хочешь?", "url": "https://cs1.vkuseraudio.net/s/v1/ac/x/index.m3u8?siren=1"}
    fake_vk(monkeypatch, {
        "utils.getServerTime": {"response": 1_700_000_000},
        "users.get": {"response": [{"id": 1, "first_name": "Иван", "last_name": "Петров"}]},
        "audio.search": {"response": {"count": 1, "items": [track]}},
        "index.m3u8?siren=1": (b"#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI=\"key.pub\"\n", "application/vnd.apple.mpegurl"),
    }, seen)
    monkeypatch.setenv("VK_TOKEN", TOKEN)
    assert check_vk.main() == 0
    out = capsys.readouterr().out
    assert "ИТОГ: OK" in out and "HLS (AES-128)" in out and "Иван Петров" in out
    assert TOKEN not in out and "siren" not in out


def test_expired_token_fails_clearly(monkeypatch, capsys):
    seen = []
    fake_vk(monkeypatch, {
        "utils.getServerTime": {"response": 1},
        "users.get": {"error": {"error_code": 5, "error_msg": f"User authorization failed: {TOKEN}"}},
    }, seen)
    monkeypatch.setenv("VK_TOKEN", TOKEN)
    assert check_vk.main() == 1
    out = capsys.readouterr().out
    assert "FAIL" in out and "код 5" in out and "войди заново" in out
    assert TOKEN not in out


def test_unavailable_stream_fails(monkeypatch, capsys):
    seen = []
    track = {"artist": "a", "title": "b", "url": "https://vk.com/mp3/audio_api_unavailable.mp3"}
    fake_vk(monkeypatch, {
        "utils.getServerTime": {"response": 1},
        "users.get": {"response": [{"id": 1}]},
        "audio.search": {"response": {"count": 1, "items": [track]}},
    }, seen)
    monkeypatch.setenv("VK_TOKEN", TOKEN)
    assert check_vk.main() == 1
    assert "не отдал ссылку" in capsys.readouterr().out
