"""Диагностика доступности (docs/SERVER_DIAG_PROMPT.md): монитор event loop, счётчик запросов, тело проверки,
`/api/diag`, `/api/diag/payload`, страница `/diag` и строка access-лога."""
import logging

import pytest
from fastapi.testclient import TestClient

from sonar import diag
from sonar.api import diag as api_diag
from sonar.config import Settings
from sonar.web import DIAG_PAGE, QUIET, create_app


class Clock:
    def __init__(self, now: float = 1000.0):
        self.now = now

    def __call__(self) -> float:
        return self.now


class FakeUpdater:
    def current(self) -> dict:
        return {"sha": "0123456789abcdef"}


@pytest.fixture
def client(con, tmp_path, monkeypatch):
    monkeypatch.setattr(api_diag, "_version", None)
    api_diag.payload_limit.hits.clear()
    app = create_app(con, Settings(data_dir=tmp_path), updater=FakeUpdater())
    return TestClient(app, base_url="http://testserver")


def test_p95_uses_nearest_rank():
    assert diag.p95([]) == 0.0
    assert diag.p95([5.0]) == 5.0
    assert diag.p95([float(n) for n in range(1, 101)]) == 95.0


def test_loop_monitor_keeps_window_and_warns_on_long_lag(caplog):
    clock = Clock()
    monitor = diag.LoopMonitor(window_s=10, clock=clock)
    monitor.record(5)
    clock.now += 20                               # первая запись выпала из окна
    with caplog.at_level(logging.WARNING, logger="sonar.diag"):
        monitor.record(30)
        monitor.record(450)
    assert monitor.stats() == {"max_ms": 450, "p95_ms": 450, "samples": 2}
    warnings = [r.getMessage() for r in caplog.records if r.name == "sonar.diag"]
    assert len(warnings) == 1 and "450 мс" in warnings[0]


def test_loop_monitor_measures_real_delay():
    import asyncio
    import time

    async def scenario() -> dict:
        monitor = diag.LoopMonitor(tick_s=0.01)
        loop = asyncio.get_running_loop()
        monitor.start(loop)
        monitor.start(loop)                       # повтор на том же loop — второго таймера нет
        await asyncio.sleep(0.015)
        time.sleep(0.12)                          # «синхронный DNS» держит loop
        await asyncio.sleep(0.03)
        return monitor.stats()

    stats = asyncio.run(scenario())
    assert stats["max_ms"] >= 80
    assert stats["samples"] < 10


def test_request_rate_counts_last_minute_only():
    clock = Clock()
    rate = diag.RequestRate(clock)
    for _ in range(3):
        rate.hit()
    clock.now += 30
    rate.hit()
    assert rate.per_minute() == 4
    clock.now += 31                               # первые три — старше минуты
    assert rate.per_minute() == 1


def test_payload_is_exact_size_deterministic_and_hard_to_compress():
    import zlib

    body = diag.payload(17)
    assert len(body) == 17 * 1024 and body == diag.payload(17)
    assert diag.payload(0) == b"" and len(diag.payload(diag.PAYLOAD_MAX_KB)) == diag.PAYLOAD_MAX_KB * 1024
    assert len(zlib.compress(diag.payload(64))) > 40 * 1024     # gzip прокси не превратит проверку в пустяк
    for bad in (-1, diag.PAYLOAD_MAX_KB + 1):
        with pytest.raises(ValueError):
            diag.payload(bad)


def test_payload_endpoint_returns_exact_bytes_without_cache(client):
    r = client.get("/api/diag/payload", params={"kb": 17})
    assert r.status_code == 200
    assert len(r.content) == 17408 and r.headers["content-length"] == "17408"
    assert r.headers["cache-control"] == "no-store"
    assert r.content == diag.payload(17)


def test_payload_endpoint_rejects_wrong_size(client):
    for kb in ("2049", "-1", "много"):
        r = client.get("/api/diag/payload", params={"kb": kb})
        assert r.status_code == 400 and r.json()["error"]["code"] == "bad_request"


def test_payload_endpoint_has_its_own_ip_limit(client, monkeypatch):
    monkeypatch.setattr(api_diag.payload_limit, "limit", 2)
    assert [client.get("/api/diag/payload").status_code for _ in range(3)] == [200, 200, 429]
    r = client.get("/api/diag/payload")
    assert r.json()["error"]["code"] == "too_many" and r.headers["retry-after"] == str(api_diag.WINDOW_S)


def test_diag_reports_server_state_without_addresses(client):
    client.get("/api/health")
    r = client.get("/api/diag")
    data = r.json()
    assert r.headers["cache-control"] == "no-store"
    assert set(data) == {"version", "uptime_s", "loop_lag", "rss_mb", "requests_per_min"}
    assert data["version"] == "01234567"
    assert set(data["loop_lag"]) == {"max_ms", "p95_ms", "samples"}
    assert data["requests_per_min"] >= 2
    assert "testclient" not in r.text and "127.0.0.1" not in r.text


def test_diag_page_is_self_contained(client):
    r = client.get("/diag")
    assert r.status_code == 200 and r.headers["content-type"].startswith("text/html")
    assert r.headers["cache-control"] == "no-store"
    csp = r.headers["content-security-policy"]
    assert "default-src 'none'" in csp and "connect-src 'self'" in csp
    assert "/api/diag/payload" in r.text
    assert "http://" not in r.text and "https://" not in r.text     # ни шрифтов, ни скриптов со стороны


def test_payload_is_quiet_but_diag_page_is_logged_with_bytes_and_ua(client, caplog):
    assert "/api/diag/payload" in QUIET
    with caplog.at_level(logging.INFO, logger="sonar.web"):
        client.get("/api/diag/payload", params={"kb": 1})
        client.get("/diag", headers={"user-agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) Safari"})
    lines = [r.getMessage() for r in caplog.records if r.name == "sonar.web"]
    assert not any("/api/diag/payload" in line for line in lines)
    page = [line for line in lines if "/diag -> 200" in line]
    assert len(page) == 1
    assert f" {len(DIAG_PAGE.encode())} Б" in page[0]
    assert "ua=Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 " in page[0] and "Safari" not in page[0]
    assert "ОБОРВАН" not in page[0]


def test_access_log_sees_site_pages_as_200(con, tmp_path, caplog):
    """Раньше лог стоял внутри мидлвары сайта и писал «-> 404» на каждую его страницу."""
    site = tmp_path / "site"
    (site / "faq").mkdir(parents=True)
    (site / "index.html").write_text("<h1>Sonar</h1>")
    (site / "faq" / "index.html").write_text("<h1>FAQ</h1>")
    app = create_app(con, Settings(data_dir=tmp_path / "data"), site=site, updater=FakeUpdater())
    with caplog.at_level(logging.INFO, logger="sonar.web"):
        TestClient(app).get("/faq/")
    lines = [r.getMessage() for r in caplog.records if r.name == "sonar.web"]
    assert any("/faq/ -> 200" in line for line in lines)
    assert not any("/faq/ -> 404" in line for line in lines)
