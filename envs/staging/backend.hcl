# Terraform remote state backend — managed by platform-org (Layer 1)
# S3 bucket and DynamoDB table are created by platform-org apply.
# Run 'make fetch ENV=staging' to generate fetched.auto.tfvars.json before plan/apply.

bucket         = "ffreis-tf-state-runtime"
key            = "platform-project-template/staging/terraform.tfstate"
region         = "us-east-1"
dynamodb_table = "ffreis-tf-locks-runtime"
encrypt        = true
