# Runbook

Service: **expense-tracker** (ECS Fargate + RDS PostgreSQL, ap-south-1). Environments: `staging`, `production`.

## 1. One-time bootstrap

```bash
# 1. Remote state (replace ACCOUNT_ID)
aws s3api create-bucket --bucket expense-tracker-tfstate-ACCOUNT_ID --region ap-south-1 \
  --create-bucket-configuration LocationConstraint=ap-south-1
aws s3api put-bucket-versioning --bucket expense-tracker-tfstate-ACCOUNT_ID \
  --versioning-configuration Status=Enabled
aws dynamodb create-table --table-name expense-tracker-tflock --billing-mode PAY_PER_REQUEST \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH --region ap-south-1

# 2. Edit terraform/envs/*.tfvars and *.backend.hcl (account id, repo, alarm email)

# 3. Production stack FIRST (creates ECR repo, GitHub OIDC provider, CI role)
cd terraform
terraform init -backend-config=envs/production.backend.hcl
terraform apply -var-file=envs/production.tfvars

# 4. Staging stack (separate state)
terraform init -reconfigure -backend-config=envs/staging.backend.hcl
terraform apply -var-file=envs/staging.tfvars
```

Confirm the SNS subscription email for each environment.

## 2. GitHub configuration

| Where | Name | Value |
|---|---|---|
| Repo variable | `AWS_CI_ROLE_ARN` | output `github_ci_role_arn` (production stack) |
| Environment `staging` variables | `AWS_CD_ROLE_ARN_STAGING`, `STAGING_URL` | outputs `github_cd_role_arn`, `app_url` |
| Environment `production` variables | `AWS_CD_ROLE_ARN_PROD`, `PROD_URL` | same |
| Environment `production` protection | **Required reviewers** | at least one approver (this is the manual gate) |

No AWS access keys and no database passwords are stored in GitHub.

## 3. Normal release

1. Merge PR to `main` -> CI -> image in ECR.
2. CD deploys to staging automatically; check the smoke test is green.
3. Approver reviews staging, approves `production`.
4. Canary + bake + full shift (~10 min). Watch CloudWatch dashboard (`dashboard_url` output).

Target: commit to production in under 15 min of pipeline time, excluding the human approval wait.

## 4. Rebuild everything from code

```bash
cd terraform
terraform init -backend-config=envs/<env>.backend.hcl
terraform apply -var-file=envs/<env>.tfvars     # infrastructure (new empty DB)
```
Then re-run the CD workflow with the desired SHA to put the real image on it. Restore data from an RDS snapshot if needed (set `snapshot_identifier` on the DB resource, or restore via console then `terraform import`).

## 5. Incident playbooks

**Deployment failed / rolled back**
1. Read the CD job log; it prints CodeDeploy status and error info.
2. `aws deploy get-deployment --deployment-id <id>`; check `rollbackInfo`.
3. Confirm production still serves the old SHA: `curl $PROD_URL/healthz`.
4. Fix forward in a new commit. Do not re-run the same SHA unless the cause was transient.

**5xx alarm**
1. CloudWatch dashboard -> 5xx vs request rate. Check `/ecs/expense-tracker-production` logs.
2. If it began at a deploy time and no automatic rollback happened, run a manual rollback (docs/rollback-strategy.md).
3. If `/readyz` returns 503, check RDS (connections, CPU, storage, security group).

**High latency**
1. Dashboard: is CPU/memory saturated? Autoscaling reacts at 60% CPU; raise `task_cpu` if needed.
2. RDS CPU / connections: each worker opens one connection per request; consider a pool if connections approach the limit.

**Database full / slow**
- Storage autoscaling goes to 100 GB. Alarm fires below 2 GiB free.
- Point-in-time restore: RDS console -> Restore to point in time, then switch the secret `host` and force a new deployment.

**Rotate DB password**
1. `terraform taint random_password.db` (or `-replace=random_password.db`), then `terraform apply`.
2. Force new deployment so tasks fetch the new secret: re-run CD for the current SHA.

## 6. Local development

```bash
docker compose up --build          # app :8080, Prometheus :9090, Grafana :3000 (admin / admin-local)
curl -XPOST localhost:8080/expenses -H 'content-type: application/json' \
     -d '{"category":"food","amount":250}'
curl -XPUT localhost:8080/budgets/food -H 'content-type: application/json' -d '{"monthly_limit":1000}'
curl localhost:8080/summary
```

## 7. Alarm reference

| Alarm | Meaning | Rolls back a deployment |
|---|---|---|
| `*-5xx-errors` | >= 5 target 5xx per minute for 2 min | Yes |
| `*-latency-p95` | p95 > 1 s for 3 min | Yes |
| `*-unhealthy-hosts` | targets failing `/readyz` | Yes |
| `*-cpu-high` / `*-memory-high` | >80% / >85% for 5 min | No |
| `*-rds-cpu-high` / `*-rds-free-storage-low` | DB pressure | No |
