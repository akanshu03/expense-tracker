output "app_url" {
  value = "http://${aws_lb.main.dns_name}"
}

output "ecr_repository_url" {
  value = var.create_ecr ? aws_ecr_repository.app[0].repository_url : null
}

output "github_cd_role_arn" {
  description = "Set as GitHub environment variable AWS_CD_ROLE_ARN_<ENV>"
  value       = aws_iam_role.github_cd.arn
}

output "github_ci_role_arn" {
  description = "Set as GitHub repo variable AWS_CI_ROLE_ARN"
  value       = var.create_ecr ? aws_iam_role.github_ci[0].arn : null
}

output "db_secret_arn" {
  value = aws_secretsmanager_secret.db.arn
}

output "dashboard_url" {
  value = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}"
}
