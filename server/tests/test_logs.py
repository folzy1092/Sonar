import asyncio
import sqlite3
import zipfile
from types import SimpleNamespace

from sonar.logs import ERROR_TOPIC, TOPIC, LogGroup


class FakeBot:
    def __init__(self):
        self.topics, self.sent, self.docs, self.next_id, self.gone = {}, [], [], 10, set()

    async def create_forum_topic(self, chat_id, name):
        self.next_id += 1
        self.topics[self.next_id] = name
        return SimpleNamespace(message_thread_id=self.next_id)

    async def get_forum_topic_icon_stickers(self):
        return [SimpleNamespace(emoji="🎵", custom_emoji_id="1"), SimpleNamespace(emoji="❗", custom_emoji_id="2")]

    async def edit_forum_topic(self, **kw):
        pass

    async def send_message(self, chat_id, message_thread_id, text, **kw):
        if message_thread_id in self.gone:
            raise RuntimeError("Bad Request: message thread not found")
        self.sent.append((message_thread_id, text))

    async def send_document(self, chat_id, message_thread_id, document, caption, **kw):
        self.docs.append((message_thread_id, document.path, caption))


def run(c):
    return asyncio.run(c)


def test_topics_created_once_and_recreated_when_gone(con):
    bot = FakeBot()
    lg = LogGroup(bot, con, -100, owner_id=1)
    run(lg.event("▶️", "Старт"))
    run(lg.event("▶️", "Ещё"))
    run(lg.error("Упало", ValueError("x")))
    assert sorted(bot.topics.values()) == [TOPIC, ERROR_TOPIC]
    first = next(k for k, v in bot.topics.items() if v == TOPIC)
    bot.gone.add(first)
    run(lg.event("▶️", "После удаления темы"))
    assert list(bot.topics.values()).count(TOPIC) == 2
    assert bot.sent[-1][0] != first


def test_owner_not_pinged(con):
    bot = FakeBot()
    lg = LogGroup(bot, con, -100, owner_id=7)
    run(lg.event("🔑", "Вход", SimpleNamespace(id=7, username="cocainemodel", full_name="F")))
    assert "DEV" in bot.sent[0][1] and "cocainemodel" not in bot.sent[0][1]


def test_no_chat_no_logs(con):
    bot = FakeBot()
    run(LogGroup(bot, con, None).event("▶️", "x"))
    assert not bot.sent and not bot.topics


def test_backup_goes_to_data_topic(tmp_path):
    db = tmp_path / "sonar.db"
    from sonar.db import connect
    con = connect(db)
    con.execute("INSERT INTO kv (key, value) VALUES ('a', 'b')")
    bot = FakeBot()
    captured = {}

    async def keep(chat_id, message_thread_id, document, caption, **kw):
        with zipfile.ZipFile(document.path) as zf:
            zf.extract("sonar.db", tmp_path / "out")
        captured["thread"] = message_thread_id

    bot.send_document = keep
    assert run(LogGroup(bot, con, -100, data_thread_id=555).backup(str(db)))
    assert captured["thread"] == 555
    restored = sqlite3.connect(tmp_path / "out" / "sonar.db")
    assert restored.execute("SELECT value FROM kv WHERE key = 'a'").fetchone()[0] == "b"


def test_backup_only_to_data(con):
    bot = FakeBot()
    assert not run(LogGroup(bot, con, -100, data_thread_id=None).backup(":memory:"))
    assert not bot.docs and not bot.topics
