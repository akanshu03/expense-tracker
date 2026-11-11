bucket         = "expense-tracker-tfstate-REPLACE_ACCOUNT_ID"
key            = "production/terraform.tfstate"
region         = "ap-south-1"
dynamodb_table = "expense-tracker-tflock"
encrypt        = true
