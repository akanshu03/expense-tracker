#!/usr/bin/env bash
# Generate sample traffic so dashboards have data. Usage: scripts/load.sh [base-url] [seconds]
set -euo pipefail
URL="${1:-http://localhost:8080}"; SECS="${2:-120}"
curl -fsS -XPUT "$URL/budgets/food" -H 'content-type: application/json' -d '{"monthly_limit":5000}' >/dev/null
END=$((SECONDS+SECS))
while [ $SECONDS -lt $END ]; do
  curl -fsS -XPOST "$URL/expenses" -H 'content-type: application/json' \
       -d "{\"category\":\"food\",\"amount\":$((RANDOM%500+10))}" >/dev/null
  curl -fsS "$URL/expenses" >/dev/null
  curl -fsS "$URL/summary" >/dev/null
  curl -s -o /dev/null "$URL/expenses" -XPOST -H 'content-type: application/json' -d '{}'  # 400s
  sleep 0.2
done
echo "done"
