"""Проверка связи с сервером с компьютера: python server/tools/diag_probe.py [https://try-sonar.ru] [--json].

То же, что страница /diag в браузере (docs/SERVER_DIAG.md): тела 1…1024 КБ по три раза, потом шесть параллельных по
32 КБ; для каждого — итог (ok / обрыв на N Б / таймаут / ошибка), первый байт и всё время. До и после — /api/diag.
Только стандартная библиотека, ничего ставить не надо. Адресов и токенов не печатает и не шлёт.
"""
from __future__ import annotations

import argparse
import json
import math
import socket
import sys
import time
import urllib.error
import urllib.request
from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor

SIZES = (1, 8, 16, 17, 32, 64, 256, 1024)
RUNS = 3
PARALLEL = 6
PARALLEL_KB = 32
TIMEOUT_S = 15.0
CHUNK = 16 * 1024
USER_AGENT = "SonarDiagProbe/1"

Opener = Callable[..., object]


def p95(values: list[float]) -> float:
    """95-й перцентиль методом ближайшего ранга, как в sonar/diag.py."""
    if not values:
        return 0.0
    ordered = sorted(values)
    return ordered[max(0, math.ceil(0.95 * len(ordered)) - 1)]


def _request(url: str) -> urllib.request.Request:
    return urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Cache-Control": "no-store"})


def probe(base: str, kb: int, tag: str, urlopen: Opener = urllib.request.urlopen,
          timeout: float = TIMEOUT_S, clock: Callable[[], float] = time.monotonic) -> dict:
    """Один запрос тела `kb` КБ. Никогда не бросает: любой сбой — строка в `outcome`."""
    started = clock()
    got, ttfb = 0, None

    def result(outcome: str) -> dict:
        ms = lambda at: None if at is None else round((at - started) * 1000)   # noqa: E731
        return {"kb": kb, "tag": tag, "outcome": outcome, "bytes": got, "ttfb_ms": ms(ttfb), "ms": ms(clock())}

    url = f"{base}/api/diag/payload?kb={kb}&r={time.time_ns()}"
    try:
        with urlopen(_request(url), timeout=timeout) as resp:
            ttfb = clock()
            while chunk := resp.read(CHUNK):
                got += len(chunk)
    except urllib.error.HTTPError as err:
        return result(f"HTTP {err.code}")
    except (TimeoutError, socket.timeout):
        return result(f"таймаут на {got} Б" if got else "таймаут")
    except (OSError, urllib.error.URLError, ValueError):
        return result(f"обрыв на {got} Б" if got else "ошибка сети")
    return result("ok" if got == kb * 1024 else f"обрыв на {got} Б")


def server_info(base: str, urlopen: Opener = urllib.request.urlopen, timeout: float = TIMEOUT_S) -> dict:
    try:
        with urlopen(_request(f"{base}/api/diag?r={time.time_ns()}"), timeout=timeout) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as err:
        return {"error": f"HTTP {err.code}"}
    except (OSError, urllib.error.URLError, ValueError):
        return {"error": "ошибка сети"}


def run(base: str, urlopen: Opener = urllib.request.urlopen, timeout: float = TIMEOUT_S) -> dict:
    base = base.rstrip("/")
    before = server_info(base, urlopen, timeout)
    results = [probe(base, kb, f"#{i}", urlopen, timeout) for kb in SIZES for i in range(1, RUNS + 1)]
    with ThreadPoolExecutor(PARALLEL) as pool:
        results += pool.map(lambda i: probe(base, PARALLEL_KB, f"парал. {i}", urlopen, timeout), range(1, PARALLEL + 1))
    return {"results": results, "summary": summarize(results),
            "server_before": before, "server_after": server_info(base, urlopen, timeout)}


def summarize(results: list[dict]) -> dict:
    bad = [r for r in results if r["outcome"] != "ok"]
    per_size: dict[int, list[float]] = {}
    for r in results:
        if r["outcome"] == "ok":
            per_size.setdefault(r["kb"], []).append(r["ms"])
    first = f"{bad[0]['kb']} КБ {bad[0]['tag']}: {bad[0]['outcome']}" if bad else None
    return {"total": len(results), "failed": len(bad), "first_failure": first,
            "p95_ms_by_kb": {kb: round(p95(v)) for kb, v in sorted(per_size.items())}}


def table(report: dict) -> str:
    fmt = lambda v: "—" if v is None else f"{v} мс"   # noqa: E731
    lines = [f"{'Размер':<16}{'Итог':<22}{'Первый байт':>12}{'Всего':>10}"]
    lines += [f"{str(r['kb']) + ' КБ ' + r['tag']:<16}{r['outcome']:<22}{fmt(r['ttfb_ms']):>12}{fmt(r['ms']):>10}"
              for r in report["results"]]
    s = report["summary"]
    lines.append("")
    lines.append(f"Сбоев {s['failed']} из {s['total']}. Первый — {s['first_failure']}." if s["failed"]
                 else f"Всё дошло: {s['total']} из {s['total']}.")
    lines.append("p95 по размерам: " + ", ".join(f"{kb} КБ — {ms} мс" for kb, ms in s["p95_ms_by_kb"].items()))
    lines.append(f"Сервер до: {json.dumps(report['server_before'], ensure_ascii=False)}")
    lines.append(f"Сервер после: {json.dumps(report['server_after'], ensure_ascii=False)}")
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Проверка связи с сервером Sonar")
    parser.add_argument("base", nargs="?", default="https://try-sonar.ru")
    parser.add_argument("--json", action="store_true", help="вывести JSON вместо таблицы")
    parser.add_argument("--timeout", type=float, default=TIMEOUT_S)
    args = parser.parse_args(argv)
    if not args.base.startswith(("http://", "https://")):
        parser.error("адрес — с http:// или https://")
    report = run(args.base, timeout=args.timeout)
    print(json.dumps(report, ensure_ascii=False, indent=2) if args.json else table(report))
    return 1 if report["summary"]["failed"] else 0


if __name__ == "__main__":
    sys.exit(main())
