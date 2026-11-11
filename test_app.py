"""Unit tests. The DB layer is mocked so tests run without Postgres."""
from unittest.mock import MagicMock, patch

import pytest

import app as app_module


@pytest.fixture()
def client(monkeypatch):
    monkeypatch.setenv("DATABASE_URL", "postgresql://x:y@localhost/db")
    app_module.app.config["TESTING"] = True
    return app_module.app.test_client()


def fake_conn(fetchone=None, fetchall=None):
    conn = MagicMock()
    cur = conn.cursor.return_value.__enter__.return_value
    cur.fetchone.return_value = fetchone
    cur.fetchall.return_value = fetchall or []
    return conn


def test_healthz_does_not_need_db(client):
    r = client.get("/healthz")
    assert r.status_code == 200
    assert r.get_json()["status"] == "ok"


def test_readyz_ok(client):
    with patch.object(app_module.psycopg2, "connect", return_value=fake_conn()):
        r = client.get("/readyz")
    assert r.status_code == 200


def test_readyz_503_when_db_down(client):
    with patch.object(app_module.psycopg2, "connect", side_effect=Exception("down")):
        r = client.get("/readyz")
    assert r.status_code == 503


def test_add_expense_validation(client):
    assert client.post("/expenses", json={"category": "food"}).status_code == 400
    assert client.post("/expenses", json={"category": "food", "amount": -5}).status_code == 400
    assert client.post("/expenses", json={"category": "", "amount": 5}).status_code == 400


def test_add_expense_created(client):
    with patch.object(app_module.psycopg2, "connect", return_value=fake_conn(fetchone=(7,))):
        r = client.post("/expenses", json={"category": "Food", "amount": 250.5})
    assert r.status_code == 201
    assert r.get_json()["id"] == 7


def test_set_budget_validation(client):
    assert client.put("/budgets/food", json={"monthly_limit": 0}).status_code == 400


def test_summary_flags_over_budget(client):
    rows = [{"category": "food", "spent": 1200.0, "monthly_limit": 1000.0}]
    with patch.object(app_module.psycopg2, "connect", return_value=fake_conn(fetchall=rows)):
        r = client.get("/summary")
    assert r.get_json()[0]["over_budget"] is True


def test_metrics_exposed(client):
    client.get("/healthz")
    body = client.get("/metrics").get_data(as_text=True)
    assert "http_requests_total" in body
    assert "http_request_duration_seconds" in body
