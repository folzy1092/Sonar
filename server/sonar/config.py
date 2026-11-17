"""Настройки из окружения (server/.env, пример — server/env.example)."""
from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path

from dotenv import load_dotenv

SERVER_DIR = Path(__file__).resolve().parent.parent
REPO_DIR = SERVER_DIR.parent
# Тема «Data» лог-группы владельца (t.me/c/2276939424/32139) — общая для бэкапов всех его ботов.
DATA_THREAD_ID = 32139
# Группа-форум поддержки (BOT.md §2.10) — не секрет, поэтому значение по умолчанию.
SUPPORT_GROUP_ID = -1003910646265
LOG_CHAT_ID = -1002276939424


def _int(name: str) -> int | None:
    v = os.getenv(name, "").strip()
    return int(v) if v else None


@dataclass
class Settings:
    bot_token: str = ""
    owner_tg_id: int | None = None
    fernet_key: str = ""
    public_url: str = ""
    site_url: str = "https://sonar.folzy.ru"
    download_url: str = "https://github.com/folzy1092/Sonar/releases/latest"
    # iPhone — постоянный релиз ios-latest (CI перезаливает, Latest не трогает — он у Windows)
    download_url_ios: str = "https://github.com/folzy1092/Sonar/releases/download/ios-latest/Sonar.ipa"
    support_group_id: int | None = None
    log_chat_id: int | None = None
    data_thread_id: int | None = None   # тема «Data» лог-группы (бэкапы), создана другим ботом
    lastfm_api_key: str = ""
    port: int = 8080
    data_dir: Path = field(default_factory=lambda: SERVER_DIR / "data")

    @property
    def db_path(self) -> Path:
        return self.data_dir / "sonar.db"


def load(env_file: Path | None = None) -> Settings:
    load_dotenv(env_file or SERVER_DIR / ".env")
    s = Settings(
        bot_token=os.getenv("SONAR_BOT_TOKEN", "").strip(),
        owner_tg_id=_int("SONAR_OWNER_TG_ID"),
        fernet_key=os.getenv("SONAR_FERNET_KEY", "").strip(),
        public_url=os.getenv("SONAR_PUBLIC_URL", "").strip().rstrip("/"),
        support_group_id=_int("SUPPORT_GROUP_ID") or SUPPORT_GROUP_ID,
        log_chat_id=_int("SONAR_LOG_CHAT_ID") or LOG_CHAT_ID,
        data_thread_id=_int("SONAR_DATA_THREAD_ID") or DATA_THREAD_ID,
        lastfm_api_key=os.getenv("LASTFM_API_KEY", "").strip(),
        port=_int("PORT") or 8080,
    )
    if os.getenv("SONAR_DATA_DIR"):
        s.data_dir = Path(os.environ["SONAR_DATA_DIR"])
    if os.getenv("SONAR_SITE_URL"):
        s.site_url = os.environ["SONAR_SITE_URL"].rstrip("/")
    s.data_dir.mkdir(parents=True, exist_ok=True)
    if not s.fernet_key:
        # Локальный запуск без ключа: создаём свой и храним рядом с базой (на сервере — только env).
        key_file = s.data_dir / "fernet.key"
        if not key_file.exists():
            from cryptography.fernet import Fernet
            key_file.write_text(Fernet.generate_key().decode())
        s.fernet_key = key_file.read_text().strip()
    return s
