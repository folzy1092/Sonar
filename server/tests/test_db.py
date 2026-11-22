"""tx(): явная транзакция поверх isolation_level=None — всё или ничего, вложенный вызов входит во внешний."""
import pytest

from sonar.db import kv_get, kv_set, tx


def test_tx_commits(con):
    with tx(con):
        kv_set(con, "a", "1")
    assert not con.in_transaction
    assert kv_get(con, "a") == "1"


def test_tx_rolls_back_every_step_on_error(con):
    with pytest.raises(RuntimeError), tx(con):
        kv_set(con, "a", "1")
        kv_set(con, "b", "2")
        raise RuntimeError("сбой посередине")
    assert not con.in_transaction
    assert kv_get(con, "a") is None and kv_get(con, "b") is None


def test_nested_tx_joins_outer(con):
    with pytest.raises(RuntimeError), tx(con):
        with tx(con):
            kv_set(con, "inner", "1")
        assert con.in_transaction  # внутренний не закоммитил раньше времени
        raise RuntimeError
    assert kv_get(con, "inner") is None
