"""python -m sonar.admin passwd [логин] — задать пароль админа из консоли (забыл пароль, сессии закрываются).

Пароль спрашивается скрыто (getpass): не попадает ни в историю команд, ни в код. Приём из TG Store.
"""
from __future__ import annotations

import getpass
import sys

from .. import config
from ..db import connect
from .auth import FACTORY_LOGIN, PASSWORD_MIN, AdminAuth, AuthError


def main(argv: list[str]) -> int:
    if not argv or argv[0] != "passwd":
        print(__doc__.strip())
        return 1
    login = argv[1] if len(argv) > 1 else FACTORY_LOGIN
    auth = AdminAuth(connect(config.load().db_path))
    auth.ensure_factory()
    new = getpass.getpass("Новый пароль: ")
    if len(new) < PASSWORD_MIN:
        print(f"Слишком короткий — от {PASSWORD_MIN} символов.")
        return 1
    if new != getpass.getpass("Ещё раз: "):
        print("Пароли не совпадают.")
        return 1
    try:
        auth.set_password(login, new)
    except AuthError:
        print(f"Админа «{login}» нет.")
        return 1
    print(f"Пароль «{login}» обновлён, все сессии админки закрыты.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
