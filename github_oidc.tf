# GitHub Actions authenticates to AWS with short-lived OIDC tokens (no access keys in GitHub).

resource "aws_iam_openid_connect_provider" "github" {
  count           = var.create_ecr ? 1 : 0
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_ecr ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}

locals {
  oidc_arn = var.create_ecr ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
}

data "aws_iam_policy_document" "gh_assume_cd" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.oidc_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      # Only jobs that run in this GitHub *environment* can assume the role,
      # so the production role needs the production approval gate.
      values = ["repo:${var.github_repository}:environment:${var.environment}"]
    }
  }
}

resource "aws_iam_role" "github_cd" {
  name               = "${local.name}-github-cd"
  assume_role_policy = data.aws_iam_policy_document.gh_assume_cd.json
}

resource "aws_iam_role_policy" "github_cd" {
  name = "deploy"
  role = aws_iam_role.github_cd.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["ecs:DescribeServices", "ecs:DescribeTaskDefinition", "ecs:RegisterTaskDefinition"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = [aws_iam_role.execution.arn, aws_iam_role.task.arn]
      },
      {
        Effect = "Allow"
        Action = ["codedeploy:CreateDeployment", "codedeploy:GetDeployment", "codedeploy:GetDeploymentConfig", "codedeploy:GetApplicationRevision", "codedeploy:RegisterApplicationRevision"]
        Resource = [
          aws_codedeploy_app.app.arn,
          aws_codedeploy_deployment_group.app.arn,
          "arn:aws:codedeploy:${var.region}:${data.aws_caller_identity.current.account_id}:deploymentconfig:*",
        ]
      },
    ]
  })
}

# CI role (build + push) - created once, with the shared ECR repo.
data "aws_iam_policy_document" "gh_assume_ci" {
  count = var.create_ecr ? 1 : 0
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.oidc_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repository}:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "github_ci" {
  count              = var.create_ecr ? 1 : 0
  name               = "expense-tracker-github-ci"
  assume_role_policy = data.aws_iam_policy_document.gh_assume_ci[0].json
}

resource "aws_iam_role_policy" "github_ci" {
  count = var.create_ecr ? 1 : 0
  name  = "ecr-push"
  role  = aws_iam_role.github_ci[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["ecr:GetAuthorizationToken"], Resource = "*" },
      {
        Effect = "Allow"
        Action = ["ecr:BatchCheckLayerAvailability", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload", "ecr:PutImage", "ecr:BatchGetImage"]
        Resource = local.ecr_repo_arn
      },
    ]
  })
}
