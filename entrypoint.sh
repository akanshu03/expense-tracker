#!/bin/sh
set -e
# Build DATABASE_URL from parts if not given directly (ECS injects DB_* from Secrets Manager).
if [ -z "$DATABASE_URL" ] && [ -n "$DB_HOST" ]; then
  export DATABASE_URL="postgresql://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT:-5432}/${DB_NAME}"
fi
python -c "import app; app.init_db()"
exec gunicorn --bind 0.0.0.0:8080 --workers 2 --timeout 30 --access-logfile - app:app
