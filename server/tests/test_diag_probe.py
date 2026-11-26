"""server/tools/diag_probe.py без сети: исходы запросов, план прогона, итог и таблица."""
import importlib.util
import io
import json
import urllib.error
from pathlib import Path

SPEC = importlib.util.spec_from_file_location(
    "diag_probe", Path(__file__).resolve().parents[1] / "tools" / "diag_probe.py"
)
diag_probe = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(diag_probe)

BASE = "https://example.test"


class Body:
    """Ответ, который отдаёт `data` и после `cut_after` байт кидает `fail` (обрыв посреди тела)."""

    def __init__(self, data: bytes, cut_after: int | None = None, fail: Exception | None = None):
        self.stream, self.cut_after, self.fail, self.sent = io.BytesIO(data), cut_after, fail, 0

    def read(self, n: int = -1) -> bytes:
        if self.cut_after is not None and self.sent >= self.cut_after:
            raise self.fail
        chunk = self.stream.read(n if self.cut_after is None else min(n, self.cut_after - self.sent))
        self.sent += len(chunk)
        return chunk

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False


def opener(handler):
    calls = []

    def urlopen(request, timeout):
        calls.append((request.full_url, timeout))
        return handler(request.full_url)

    urlopen.calls = calls
    return urlopen


def kb_of(url: str) -> int:
    return int(url.split("kb=")[1].split("&")[0])


def test_full_body_is_ok():
    result = diag_probe.probe(BASE, 17, "#1", opener(lambda url: Body(b"x" * kb_of(url) * 1024)))
    assert result["outcome"] == "ok" and result["bytes"] == 17408
    assert result["ttfb_ms"] is not None and result["ms"] >= result["ttfb_ms"]


def test_short_and_cut_bodies_are_reported_with_byte_count():
    short = diag_probe.probe(BASE, 32, "#1", opener(lambda url: Body(b"x" * 16384)))
    cut = diag_probe.probe(BASE, 32, "#1", opener(lambda url: Body(b"x" * 32768, 16384, ConnectionResetError())))
    stalled = diag_probe.probe(BASE, 32, "#1", opener(lambda url: Body(b"x" * 32768, 16384, TimeoutError())))
    assert short["outcome"] == "обрыв на 16384 Б"
    assert cut["outcome"] == "обрыв на 16384 Б"
    assert stalled["outcome"] == "таймаут на 16384 Б"


def test_connection_errors_never_raise():
    def refuse(url):
        raise urllib.error.URLError("refused")

    def http_429(url):
        raise urllib.error.HTTPError(url, 429, "too many", {}, None)

    def hang(url):
        raise TimeoutError()

    assert diag_probe.probe(BASE, 1, "#1", opener(refuse))["outcome"] == "ошибка сети"
    assert diag_probe.probe(BASE, 1, "#1", opener(http_429))["outcome"] == "HTTP 429"
    hung = diag_probe.probe(BASE, 1, "#1", opener(hang))
    assert hung["outcome"] == "таймаут" and hung["ttfb_ms"] is None


def test_run_makes_the_same_plan_as_the_diag_page():
    def handler(url):
        if "/api/diag?" in url:
            return Body(json.dumps({"version": "01234567"}).encode())
        kb = kb_of(url)
        return Body(b"x" * kb * 1024, 5000 if kb == 256 else None, ConnectionResetError())

    urlopen = opener(handler)
    report = diag_probe.run(BASE + "/", urlopen, timeout=3)
    payloads = [url for url, _ in urlopen.calls if "/payload" in url]
    assert len(payloads) == len(diag_probe.SIZES) * diag_probe.RUNS + diag_probe.PARALLEL
    assert all(url.startswith(BASE + "/api/") for url, _ in urlopen.calls)
    assert all(timeout == 3 for _, timeout in urlopen.calls)
    assert report["server_before"] == {"version": "01234567"}
    summary = report["summary"]
    assert summary["failed"] == 3 and summary["first_failure"] == "256 КБ #1: обрыв на 5000 Б"
    assert 256 not in summary["p95_ms_by_kb"] and 32 in summary["p95_ms_by_kb"]
    text = diag_probe.table(report)
    assert "Сбоев 3 из 30" in text and "парал. 6" in text


def test_server_info_survives_bad_answers():
    assert diag_probe.server_info(BASE, opener(lambda url: Body(b"<html>")))["error"] == "ошибка сети"


def test_p95_matches_server_formula():
    assert diag_probe.p95([]) == 0.0
    assert diag_probe.p95([float(n) for n in range(1, 101)]) == 95.0
