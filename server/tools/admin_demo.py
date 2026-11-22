"""Посмотреть админку локально на выдуманных данных: python server/tools/admin_demo.py [--port 8765].

База — server/data/demo.db (в git не идёт), настоящая sonar.db не трогается. Вход: folzy и пароль из журнала
первого запуска (случайный, печатается один раз; забыл — удали demo.db).
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from sonar.web import main  # noqa: E402

if __name__ == "__main__":
    sys.argv[1:1] = ["--demo"]
    main()
