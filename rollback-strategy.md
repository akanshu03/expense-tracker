# Rollback strategy (be ready to explain this)

## The short version

> Every production release is a **blue/green canary** managed by AWS CodeDeploy. The old version keeps running untouched until the new version has proven itself. If the new version fails a health check or trips a CloudWatch alarm, **CodeDeploy shifts traffic back to the old version automatically** - there is nothing to redeploy, because the old tasks are still running.

## Timeline of a production release

| Step | What happens | Rollback trigger |
|---|---|---|
| 1 | New task definition registered (image = commit SHA) | n/a |
| 2 | Green tasks start in a second target group | Tasks fail to start or fail `/readyz` -> **deployment fails, traffic never moved** |
| 3 | Green is reachable on test listener `:8443` (optional pre-checks) | Lifecycle hook failure -> rollback |
| 4 | **10% of traffic** shifts to green | Alarm: 5xx count, p95 latency, unhealthy hosts -> **automatic rollback** |
| 5 | 5-minute bake time at 10% | Same alarms |
| 6 | Remaining 90% shifts | Same alarms |
| 7 | Blue kept 1 more minute, then terminated | Within this minute a stop/rollback is instant |

During steps 4-6 a bad release affects at most 10% of requests for a few minutes.

## What triggers a rollback (configured in `terraform/codedeploy.tf`)

- `DEPLOYMENT_FAILURE`: green never became healthy, or the deployment errored.
- `DEPLOYMENT_STOP_ON_ALARM`: any of these alarms enters ALARM state during the deployment:
  - `...-5xx-errors` (>= 5 target 5xx in 1 minute for 2 minutes)
  - `...-latency-p95` (p95 > 1 s for 3 minutes)
  - `...-unhealthy-hosts`
- The CD job then exits non-zero (see `scripts/deploy.sh`), the pipeline turns red, and SNS emails the team.

## Manual rollback (after blue has been terminated)

Once blue is gone, "rollback" means deploying the previous known-good image through the same safe path:

1. GitHub -> Actions -> **CD** -> *Run workflow* -> enter the **previous good commit SHA** (its image is still in ECR, tags are immutable).
2. Approve the `production` environment.
3. Same canary + alarm protection applies, so rollbacks are also zero-downtime.

Emergency stop of a running deployment:

```bash
aws deploy stop-deployment --deployment-id <id> --auto-rollback-enabled
```

## What rollback does NOT cover

- **Database migrations.** Blue and green share one database. Migrations must be backward compatible (add columns/tables first; remove old ones in a later release). A destructive migration cannot be undone by traffic shifting. For data corruption, restore from RDS point-in-time recovery.
- **Secrets changes.** A rotated secret is picked up on task start, so rotate with both old and new credentials valid.

## Why this approach (trade-offs)

| Option | Downtime | Rollback speed | Cost | Why not chosen |
|---|---|---|---|---|
| Rolling update | None, if tuned | Slow (redeploy old image) | Low | Bad version serves traffic as it rolls; weaker rollback |
| **Blue/green + canary (chosen)** | None | Seconds (flip listener) | Brief 2x compute | Best safety for a small cost |
| Recreate / copy files (today) | Yes | Manual | Lowest | The current problem |
