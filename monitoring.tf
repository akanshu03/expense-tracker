# ---------------- Alerting ----------------
resource "aws_sns_topic" "alerts" {
  name = "${local.name}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

locals {
  alb_dim   = { LoadBalancer = aws_lb.main.arn_suffix }
  ecs_dim   = { ClusterName = aws_ecs_cluster.main.name, ServiceName = aws_ecs_service.app.name }
  alarm_actions = [aws_sns_topic.alerts.arn]
}

# --- Errors ---
resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${local.name}-5xx-errors"
  alarm_description   = "Target 5xx responses. Also triggers automatic deployment rollback."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  dimensions          = local.alb_dim
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 5
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

# --- Latency ---
resource "aws_cloudwatch_metric_alarm" "latency_p95" {
  alarm_name          = "${local.name}-latency-p95"
  alarm_description   = "p95 target response time above 1s. Also triggers automatic deployment rollback."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "TargetResponseTime"
  dimensions          = local.alb_dim
  extended_statistic  = "p95"
  period              = 60
  evaluation_periods  = 3
  threshold           = 1
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

# --- Health ---
resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  alarm_name          = "${local.name}-unhealthy-hosts"
  alarm_description   = "Targets failing /readyz health check."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  dimensions          = { LoadBalancer = aws_lb.main.arn_suffix, TargetGroup = aws_lb_target_group.blue.arn_suffix }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

# --- Resource usage ---
resource "aws_cloudwatch_metric_alarm" "ecs_cpu" {
  alarm_name          = "${local.name}-cpu-high"
  namespace           = "AWS/ECS"
  metric_name         = "CPUUtilization"
  dimensions          = local.ecs_dim
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 5
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "ecs_memory" {
  alarm_name          = "${local.name}-memory-high"
  namespace           = "AWS/ECS"
  metric_name         = "MemoryUtilization"
  dimensions          = local.ecs_dim
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 5
  threshold           = 85
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name          = "${local.name}-rds-cpu-high"
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  dimensions          = { DBInstanceIdentifier = aws_db_instance.main.identifier }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "rds_storage" {
  alarm_name          = "${local.name}-rds-free-storage-low"
  namespace           = "AWS/RDS"
  metric_name         = "FreeStorageSpace"
  dimensions          = { DBInstanceIdentifier = aws_db_instance.main.identifier }
  statistic           = "Minimum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 2147483648 # 2 GiB
  comparison_operator = "LessThanThreshold"
  alarm_actions       = local.alarm_actions
}

# ---------------- Dashboard ----------------
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = local.name
  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6
        properties = {
          title  = "Request rate & 5xx"
          region = var.region
          stat   = "Sum"
          period = 60
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", aws_lb.main.arn_suffix],
            [".", "HTTPCode_Target_5XX_Count", ".", "."],
            [".", "HTTPCode_Target_4XX_Count", ".", "."],
          ]
        }
      },
      {
        type = "metric", x = 12, y = 0, width = 12, height = 6
        properties = {
          title  = "Latency (p50 / p95 / p99)"
          region = var.region
          period = 60
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", aws_lb.main.arn_suffix, { stat = "p50" }],
            ["...", { stat = "p95" }],
            ["...", { stat = "p99" }],
          ]
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 12, height = 6
        properties = {
          title  = "ECS CPU & memory"
          region = var.region
          stat   = "Average"
          period = 60
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ClusterName", aws_ecs_cluster.main.name, "ServiceName", aws_ecs_service.app.name],
            [".", "MemoryUtilization", ".", ".", ".", "."],
          ]
        }
      },
      {
        type = "metric", x = 12, y = 6, width = 12, height = 6
        properties = {
          title  = "RDS CPU & connections"
          region = var.region
          stat   = "Average"
          period = 300
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", aws_db_instance.main.identifier],
            [".", "DatabaseConnections", ".", "."],
          ]
        }
      },
      {
        type = "alarm", x = 0, y = 12, width = 24, height = 4
        properties = {
          title = "Alarm status"
          alarms = [
            aws_cloudwatch_metric_alarm.alb_5xx.arn,
            aws_cloudwatch_metric_alarm.latency_p95.arn,
            aws_cloudwatch_metric_alarm.unhealthy_hosts.arn,
            aws_cloudwatch_metric_alarm.ecs_cpu.arn,
            aws_cloudwatch_metric_alarm.ecs_memory.arn,
            aws_cloudwatch_metric_alarm.rds_cpu.arn,
            aws_cloudwatch_metric_alarm.rds_storage.arn,
          ]
        }
      },
    ]
  })
}
