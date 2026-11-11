#!/usr/bin/env bash
# Usage: smoke-test.sh <base-url> <expected-version-sha>
set -euo pipefail
URL="${1:?base url}"; WANT="${2:?sha}"
for i in $(seq 1 10); do
  BODY=$(curl -fsS --max-time 5 "$URL/healthz" || true)
  if echo "$BODY" | grep -q "$WANT"; then
    curl -fsS --max-time 5 "$URL/readyz" >/dev/null
    echo "OK: $URL is serving $WANT"; exit 0
  fi
  echo "attempt $i: not serving $WANT yet ($BODY)"; sleep 5
done
echo "smoke test failed" >&2; exit 1
