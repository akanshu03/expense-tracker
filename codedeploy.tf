resource "aws_codedeploy_app" "app" {
  name             = local.name
  compute_platform = "ECS"
}

data "aws_iam_policy_document" "codedeploy_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["codedeploy.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "codedeploy" {
  name               = "${local.name}-codedeploy"
  assume_role_policy = data.aws_iam_policy_document.codedeploy_assume.json
}

resource "aws_iam_role_policy_attachment" "codedeploy" {
  role       = aws_iam_role.codedeploy.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodeDeployRoleForECS"
}

resource "aws_codedeploy_deployment_group" "app" {
  app_name               = aws_codedeploy_app.app.name
  deployment_group_name  = local.name
  service_role_arn       = aws_iam_role.codedeploy.arn
  deployment_config_name = var.deployment_config_name

  # ---- Automatic rollback ----
  # 1) DEPLOYMENT_FAILURE: green tasks never become healthy / lifecycle hook fails.
  # 2) DEPLOYMENT_STOP_ON_ALARM: a CloudWatch alarm fires while traffic is shifting.
  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM"]
  }

  alarm_configuration {
    enabled = true
    alarms = [
      aws_cloudwatch_metric_alarm.alb_5xx.alarm_name,
      aws_cloudwatch_metric_alarm.latency_p95.alarm_name,
      aws_cloudwatch_metric_alarm.unhealthy_hosts.alarm_name,
    ]
  }

  blue_green_deployment_config {
    deployment_ready_option {
      action_on_timeout = "CONTINUE_DEPLOYMENT"
    }
    terminate_blue_instances_on_deployment_success {
      action                           = "TERMINATE"
      termination_wait_time_in_minutes = 1 # keep blue for 1 min then remove; rollback within that window is instant
    }
  }

  deployment_style {
    deployment_option = "WITH_TRAFFIC_CONTROL"
    deployment_type   = "BLUE_GREEN"
  }

  ecs_service {
    cluster_name = aws_ecs_cluster.main.name
    service_name = aws_ecs_service.app.name
  }

  load_balancer_info {
    target_group_pair_info {
      prod_traffic_route {
        listener_arns = [aws_lb_listener.prod.arn]
      }
      test_traffic_route {
        listener_arns = [aws_lb_listener.test.arn]
      }
      target_group { name = aws_lb_target_group.blue.name }
      target_group { name = aws_lb_target_group.green.name }
    }
  }
}
