environment            = "staging"
alarm_email            = "devops@example.com"
github_repository      = "YOUR_ORG/expense-tracker"
desired_count          = 1
db_multi_az            = false
single_nat_gateway     = true
deployment_config_name = "CodeDeployDefault.ECSAllAtOnce"
vpc_cidr               = "10.10.0.0/16"
