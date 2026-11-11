# Monthly cost estimate (ap-south-1, USD)

**Approximate, on-demand list prices from memory, ~+/-25%.** Verify with the AWS Pricing Calculator before committing. Assumes low traffic (a few GB/month), 730 hours/month.

| Item | Staging | Production | Notes |
|---|---|---|---|
| NAT gateway | 41 | 82 | 1 NAT in staging, 1 per AZ in prod (~$0.056/h each) |
| Application Load Balancer | 22 | 22 | hourly + small LCU usage |
| Public IPv4 addresses | 11 | 15 | ALB (2) + NAT EIPs, ~$3.65 each |
| ECS Fargate (0.25 vCPU / 0.5 GB per task) | 10 | 19 | 1 task staging, 2 prod |
| RDS PostgreSQL db.t4g.micro | 15 | 30 | prod is Multi-AZ (2x) |
| RDS storage 20 GB gp3 | 3 | 5 | Multi-AZ doubles storage |
| CloudWatch (dashboard, alarms, logs) | 6 | 6 | dashboard $3, 8 alarms, ~1-2 GB logs |
| Secrets Manager | 0.4 | 0.4 | $0.40 per secret |
| ECR | - | 1 | shared repo, 30 images retained |
| **Total** | **~108** | **~180** | **~288 / month (about Rs 24,000)** |

## Biggest levers

1. **NAT gateways are ~40% of the bill.** Replace with VPC endpoints (ECR api/dkr, S3 gateway, Secrets Manager, CloudWatch Logs) for ~$7/endpoint/month each, or run staging tasks in public subnets.
2. **Staging out of hours.** Scale staging to 0 tasks and stop the RDS instance nights/weekends: saves roughly 50% of staging compute and DB.
3. **Production Multi-AZ** costs ~$20/month extra; keep it for a financial-data app.
4. **Savings Plans / Reserved Instances** for RDS after a few months of stable usage (up to ~30-40% off).
5. Cheaper floor for a tiny demo: staging with 1 NAT, no Multi-AZ, scaled to 0 overnight is about $70/month.
