"""Personal expense & budget tracker (Flask + PostgreSQL)."""
import os
import time

import psycopg2
import psycopg2.extras
from flask import Flask, Response, g, jsonify, request
from prometheus_client import (
    CONTENT_TYPE_LATEST,
    Counter,
    Histogram,
    generate_latest,
)

app = Flask(__name__)

REQUESTS = Counter(
    "http_requests_total", "HTTP requests", ["method", "endpoint", "status"]
)
LATENCY = Histogram(
    "http_request_duration_seconds",
    "Request latency in seconds",
    ["endpoint"],
    buckets=(0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5),
)

SCHEMA = """
CREATE TABLE IF NOT EXISTS expenses (
    id SERIAL PRIMARY KEY,
    category TEXT NOT NULL,
    amount NUMERIC(12,2) NOT NULL CHECK (amount > 0),
    note TEXT DEFAULT '',
    spent_on DATE NOT NULL DEFAULT CURRENT_DATE
);
CREATE TABLE IF NOT EXISTS budgets (
    category TEXT PRIMARY KEY,
    monthly_limit NUMERIC(12,2) NOT NULL CHECK (monthly_limit > 0)
);
"""


def database_url() -> str:
    """DATABASE_URL is injected at runtime (Secrets Manager in AWS)."""
    return os.environ["DATABASE_URL"]


def get_db():
    if "db" not in g:
        g.db = psycopg2.connect(database_url(), connect_timeout=3)
    return g.db


@app.teardown_appcontext
def close_db(_exc):
    db = g.pop("db", None)
    if db is not None:
        db.close()


@app.before_request
def start_timer():
    g.start = time.perf_counter()


@app.after_request
def record_metrics(resp):
    endpoint = request.url_rule.rule if request.url_rule else "unmatched"
    if endpoint != "/metrics":
        LATENCY.labels(endpoint).observe(time.perf_counter() - g.start)
        REQUESTS.labels(request.method, endpoint, resp.status_code).inc()
    return resp


def init_db():
    with psycopg2.connect(database_url(), connect_timeout=5) as conn:
        with conn.cursor() as cur:
            cur.execute(SCHEMA)


@app.get("/healthz")
def healthz():
    """Liveness: process is up. Does not touch the DB."""
    return jsonify(status="ok", version=os.environ.get("APP_VERSION", "dev"))


@app.get("/readyz")
def readyz():
    """Readiness: DB reachable. Used by ALB / CodeDeploy health checks."""
    try:
        with get_db().cursor() as cur:
            cur.execute("SELECT 1")
        return jsonify(status="ready")
    except Exception:  # noqa: BLE001
        return jsonify(status="db_unavailable"), 503


@app.get("/metrics")
def metrics():
    return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)


@app.post("/expenses")
def add_expense():
    data = request.get_json(silent=True) or {}
    try:
        category = str(data["category"]).strip().lower()
        amount = float(data["amount"])
        if not category or amount <= 0:
            raise ValueError
    except (KeyError, ValueError, TypeError):
        return jsonify(error="category and positive amount required"), 400
    db = get_db()
    with db.cursor() as cur:
        cur.execute(
            "INSERT INTO expenses (category, amount, note) VALUES (%s,%s,%s) RETURNING id",
            (category, amount, data.get("note", "")),
        )
        new_id = cur.fetchone()[0]
    db.commit()
    return jsonify(id=new_id), 201


@app.get("/expenses")
def list_expenses():
    with get_db().cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute(
            "SELECT id, category, amount::float, note, spent_on::text "
            "FROM expenses ORDER BY id DESC LIMIT 100"
        )
        return jsonify(cur.fetchall())


@app.put("/budgets/<category>")
def set_budget(category):
    data = request.get_json(silent=True) or {}
    try:
        limit = float(data["monthly_limit"])
        if limit <= 0:
            raise ValueError
    except (KeyError, ValueError, TypeError):
        return jsonify(error="positive monthly_limit required"), 400
    db = get_db()
    with db.cursor() as cur:
        cur.execute(
            "INSERT INTO budgets (category, monthly_limit) VALUES (%s,%s) "
            "ON CONFLICT (category) DO UPDATE SET monthly_limit = EXCLUDED.monthly_limit",
            (category.lower(), limit),
        )
    db.commit()
    return jsonify(category=category.lower(), monthly_limit=limit)


@app.get("/summary")
def summary():
    """Current-month spend vs budget per category."""
    sql = """
        SELECT COALESCE(e.category, b.category) AS category,
               COALESCE(e.spent, 0)::float AS spent,
               b.monthly_limit::float AS monthly_limit
        FROM (SELECT category, SUM(amount) AS spent FROM expenses
              WHERE date_trunc('month', spent_on) = date_trunc('month', CURRENT_DATE)
              GROUP BY category) e
        FULL JOIN budgets b ON b.category = e.category
        ORDER BY 1
    """
    with get_db().cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute(sql)
        rows = cur.fetchall()
    for r in rows:
        r["over_budget"] = r["monthly_limit"] is not None and r["spent"] > r["monthly_limit"]
    return jsonify(rows)


if __name__ == "__main__":
    init_db()
    app.run(host="0.0.0.0", port=8080)
