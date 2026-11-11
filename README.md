# Expense Tracker - containerised app with an automated delivery pipeline

Personal expense and budget tracker (Flask + PostgreSQL) with a zero-downtime CI/CD pipeline on AWS.

```
app/            Flask app, tests, multi-stage Dockerfile
docker-compose.yml   app + Postgres + Prometheus + Grafana for local use
.github/workflows/   ci.yml (lint, test, scan, build, push)  cd.yml (staging -> approval -> prod)
scripts/        deploy.sh (CodeDeploy blue/green), smoke-test.sh, load.sh
terraform/      VPC, ALB, ECS Fargate, CodeDeploy, RDS, Secrets Manager, CloudWatch, OIDC roles
monitoring/     Prometheus rules, Grafana dashboard (local); CloudWatch lives in terraform/
docs/           architecture, runbook, rollback strategy, cost estimate, screenshots guide
```

## Run locally

```bash
docker compose up --build
curl localhost:8080/healthz
```

## Requirements map

| Requirement | Where |
|---|---|
| Docker, Compose, multi-stage | `app/Dockerfile`, `docker-compose.yml` |
| CI: lint, tests, vuln scan, build, push | `.github/workflows/ci.yml` (ruff, pytest, pip-audit, Trivy, ECR) |
| Terraform: network, container service, managed DB | `terraform/network.tf`, `ecs.tf`, `database.tf` |
| CD: blue/green + automatic rollback | `terraform/codedeploy.tf`, `scripts/deploy.sh`, `.github/workflows/cd.yml` |
| Secrets manager, none in code | `terraform/database.tf` (Secrets Manager), ECS `secrets`, GitHub OIDC |
| Monitoring and alerting | `terraform/monitoring.tf` (CloudWatch), `monitoring/` (Prometheus/Grafana) |
| Stretch: staging + approval + cost | `terraform/envs/`, GitHub `production` environment, `docs/cost-estimate.md` |
| Diagram, runbook, rollback | `docs/architecture.md`, `docs/runbook.md`, `docs/rollback-strategy.md` |

Start with `docs/runbook.md` section 1 to deploy.
