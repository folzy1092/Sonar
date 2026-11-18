"""Упавшие тесты cargo (или ошибки сборки) — в аннотации GitHub.

Аннотации видно без входа в GitHub (через API check-runs), полные логи — только со входом.
Запуск: python cargo-annotate.py <лог cargo test>
"""
import re
import sys

CHUNK = 3000
LIMIT = 24000

log = open(sys.argv[1], encoding="utf-8", errors="replace").read().replace("\r", "")
parts = re.findall(r"(?ms)^failures:\n\n(.*?)^failures:", log)
if not parts:
    parts = re.findall(r"(?ms)^(error(?:\[E\d+\])?:.*?)(?=^error|\Z)", log)
text = "\n".join(parts)[:LIMIT] or log[-CHUNK:]
for i in range(0, len(text), CHUNK):
    piece = text[i : i + CHUNK].replace("%", "%25").replace("\n", "%0A")
    print("::error title=cargo test::" + piece)
