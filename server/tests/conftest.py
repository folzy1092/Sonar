import sys
from pathlib import Path

import pytest
from cryptography.fernet import Fernet

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from sonar.accounts import Accounts  # noqa: E402
from sonar.db import connect  # noqa: E402


@pytest.fixture
def con():
    return connect(":memory:")


@pytest.fixture
def acc(con):
    return Accounts(con, Fernet.generate_key().decode())
