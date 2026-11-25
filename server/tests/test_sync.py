"""deploy/sync.py — запуск на хостинге: .env, распаковка server/ из архива GitHub, замена кода."""
from __future__ import annotations

import importlib.util
import io
import tarfile
from pathlib import Path

import pytest

SYNC = Path(__file__).resolve().parents[1] / "deploy" / "sync.py"


@pytest.fixture()
def sync(tmp_path, monkeypatch):
    spec = importlib.util.spec_from_file_location("sonar_sync", SYNC)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    monkeypatch.setattr(mod, "HOME", tmp_path)
    monkeypatch.setattr(mod, "APP", tmp_path / "app")
    monkeypatch.setattr(mod, "SITE", tmp_path / "site")
    return mod


def archive(files: dict[str, bytes], links: dict[str, str] | None = None) -> bytes:
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz") as tar:
        for name, data in files.items():
            info = tarfile.TarInfo(name)
            info.size = len(data)
            tar.addfile(info, io.BytesIO(data))
        for name, target in (links or {}).items():
            info = tarfile.TarInfo(name)
            info.type = tarfile.SYMTYPE
            info.linkname = target
            tar.addfile(info)
    return buf.getvalue()


def test_load_env_keeps_panel_values(sync, tmp_path, monkeypatch):
    (tmp_path / ".env").write_text('# comment\nA=1\nexport B="two words"\nC=\'x\'\nPANEL=from-file\nbroken\n',
                                   encoding="utf-8")
    for k in ("A", "B", "C"):
        monkeypatch.delenv(k, raising=False)
    monkeypatch.setenv("PANEL", "from-panel")
    sync.load_env(tmp_path / ".env")
    import os
    assert (os.environ["A"], os.environ["B"], os.environ["C"]) == ("1", "two words", "x")
    assert os.environ["PANEL"] == "from-panel"


def test_extract_takes_only_server(sync, tmp_path):
    data = archive({
        "Sonar-abc/server/sonar/__main__.py": b"main",
        "Sonar-abc/server/requirements-run.txt": b"aiogram",
        "Sonar-abc/windows/app.ts": b"no",
        "Sonar-abc/server/data/sonar.db": b"no",
        "Sonar-abc/server/.env": b"SECRET=no",
        "Sonar-abc/server/../escape.txt": b"no",
    }, links={"Sonar-abc/server/link": "/etc/passwd"})
    dest = tmp_path / "out"
    dest.mkdir()
    assert sync.extract_server(data, dest) == 2
    assert (dest / "sonar" / "__main__.py").read_bytes() == b"main"
    assert not (dest / "data").exists() and not (dest / ".env").exists() and not (dest / "link").exists()
    assert not (tmp_path / "escape.txt").exists()


def test_install_app_swaps_and_keeps_data(sync, tmp_path):
    (tmp_path / "data").mkdir()
    (tmp_path / "data" / "sonar.db").write_bytes(b"db")
    sync.install_app("a" * 40, archive({"R/server/sonar/__main__.py": b"v1", "R/server/old.py": b"x"}))
    sync.install_app("b" * 40, archive({"R/server/sonar/__main__.py": b"v2"}))
    assert (tmp_path / "app" / "sonar" / "__main__.py").read_bytes() == b"v2"
    assert not (tmp_path / "app" / "old.py").exists()
    assert sync.local_sha() == "b" * 40
    assert (tmp_path / "data" / "sonar.db").read_bytes() == b"db"
    assert not (tmp_path / "app.new").exists() and not (tmp_path / "app.old").exists()


def test_broken_archive_keeps_current_app(sync, tmp_path):
    sync.install_app("a" * 40, archive({"R/server/sonar/__main__.py": b"v1"}))
    with pytest.raises(RuntimeError):
        sync.install_app("b" * 40, archive({"R/windows/x.ts": b"no"}))
    assert sync.local_sha() == "a" * 40
    assert (tmp_path / "app" / "sonar" / "__main__.py").read_bytes() == b"v1"


def test_offline_start_uses_current_version(sync, tmp_path, monkeypatch):
    sync.install_app("a" * 40, archive({"R/server/sonar/__main__.py": b"v1"}))

    def boom(*a, **k):
        raise OSError("нет сети")
    monkeypatch.setattr(sync, "http_get", boom)
    sync.update_code()
    assert sync.local_sha() == "a" * 40


def test_same_sha_skips_download(sync, tmp_path, monkeypatch):
    sync.install_app("a" * 40, archive({"R/server/sonar/__main__.py": b"v1"}))
    calls = []
    monkeypatch.setattr(sync, "remote_sha", lambda: "a" * 40)
    monkeypatch.setattr(sync, "http_get", lambda *a, **k: calls.append(a))
    sync.update_code()
    assert calls == []


def test_deploy_copy_matches_requirements():
    req = (SYNC.parents[1] / "requirements-run.txt").read_text(encoding="utf-8")
    assert "pytest" not in req and "aiogram" in req


def test_token_goes_only_to_github_api(sync, monkeypatch):
    sent = []

    class Resp:
        def __enter__(self):
            return self

        def __exit__(self, *a):
            return False

        def read(self):
            return b"ok"

    monkeypatch.setattr(sync.urllib.request, "urlopen", lambda req, timeout: sent.append(req) or Resp())
    monkeypatch.setenv("GITHUB_TOKEN", "secret")
    sync.http_get("https://api.github.com/repos/x/y/commits/main")
    sync.http_get("https://example.com/other")
    assert sent[0].get_header("Authorization") == "Bearer secret"
    assert sent[1].get_header("Authorization") is None


def site_release(digest: str, url: str = "https://github.com/x/y/releases/download/site-latest/site.tar.gz") -> bytes:
    import json
    return json.dumps({"assets": [{"name": "site.tar.gz", "digest": digest, "browser_download_url": url}]}).encode()


def test_site_installs_and_skips_same_version(sync, tmp_path, monkeypatch):
    got = []
    monkeypatch.setattr(sync, "http_get", lambda *a, **k: site_release("sha256:1"))
    monkeypatch.setattr(sync, "download", lambda url: got.append(url) or archive(
        {"./index.html": b"home", "./_astro/a.js": b"js", "../escape.html": b"no", "/abs.html": b"no"}))
    sync.update_site()
    assert (tmp_path / "site" / "index.html").read_bytes() == b"home"
    assert (tmp_path / "site" / "_astro" / "a.js").read_bytes() == b"js"
    assert not (tmp_path / "escape.html").exists() and not (tmp_path / "abs.html").exists()
    sync.update_site()
    assert len(got) == 1, "та же версия — не качаем"


def test_broken_site_keeps_current(sync, tmp_path, monkeypatch):
    monkeypatch.setattr(sync, "http_get", lambda *a, **k: site_release("sha256:1"))
    monkeypatch.setattr(sync, "download", lambda url: archive({"./index.html": b"v1"}))
    sync.update_site()
    monkeypatch.setattr(sync, "http_get", lambda *a, **k: site_release("sha256:2"))
    monkeypatch.setattr(sync, "download", lambda url: archive({"./other.html": b"no"}))
    sync.update_site()  # без index.html — отказ, без исключения
    assert (tmp_path / "site" / "index.html").read_bytes() == b"v1"


def test_site_download_only_from_github(sync):
    assert sync.trusted_download("https://github.com/x/y/releases/download/t/site.tar.gz")
    assert sync.trusted_download("https://release-assets.githubusercontent.com/abc")
    assert not sync.trusted_download("http://github.com/x")
    assert not sync.trusted_download("https://github.com.evil.example/x")
    assert not sync.trusted_download("https://evil.example/githubusercontent.com")
    with pytest.raises(RuntimeError):
        sync.download("https://evil.example/site.tar.gz")
