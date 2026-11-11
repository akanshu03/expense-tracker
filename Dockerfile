# syntax=docker/dockerfile:1.7

# ---- Stage 1: build wheels (compilers stay here, not in the final image) ----
FROM python:3.12-slim AS builder
WORKDIR /build
COPY requirements.txt .
RUN pip wheel --no-cache-dir --wheel-dir /wheels -r requirements.txt

# ---- Stage 2: test target (used by CI: docker build --target test) ----
FROM python:3.12-slim AS test
WORKDIR /app
COPY --from=builder /wheels /wheels
COPY requirements.txt requirements-dev.txt ./
RUN pip install --no-cache-dir --no-index --find-links=/wheels -r requirements.txt \
    && pip install --no-cache-dir -r requirements-dev.txt
COPY . .
RUN ruff check . && pytest -q

# ---- Stage 3: runtime (small, non-root) ----
FROM python:3.12-slim AS runtime
ARG APP_VERSION=dev
ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1 APP_VERSION=${APP_VERSION}
WORKDIR /app
COPY --from=builder /wheels /wheels
COPY requirements.txt .
RUN pip install --no-cache-dir --no-index --find-links=/wheels -r requirements.txt \
    && rm -rf /wheels
COPY app.py entrypoint.sh ./
RUN chmod +x entrypoint.sh && useradd -r -u 10001 appuser
USER appuser
EXPOSE 8080
HEALTHCHECK --interval=10s --timeout=3s --retries=3 \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8080/healthz', timeout=2).status==200 else 1)"
ENTRYPOINT ["./entrypoint.sh"]
