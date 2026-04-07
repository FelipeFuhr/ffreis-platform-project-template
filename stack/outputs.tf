output "aws_region" {
  description = "AWS region used"
  value       = var.aws_region
}

output "project_name" {
  description = "Project name"
  value       = var.project_name
}

output "environment" {
  description = "Environment"
  value       = var.environment
}

# ========== IAM Roles ==========

output "terraform_plan_role_arn" {
  description = "ARN of terraform plan role (read-only)"
  value       = try(aws_iam_role.terraform_plan.arn, null)
}

output "terraform_apply_role_arn" {
  description = "ARN of terraform apply role (write)"
  value       = try(aws_iam_role.terraform_apply.arn, null)
}

output "terraform_apply_role_name" {
  description = "Name of terraform apply role"
  value       = try(aws_iam_role.terraform_apply.name, null)
}

output "terraform_destroy_role_arn" {
  description = "ARN of terraform destroy role (dev only)"
  value       = try(aws_iam_role.terraform_destroy[0].arn, null)
}

# ========== Logging & Monitoring ==========

output "cloudtrail_bucket_name" {
  description = "S3 bucket for CloudTrail logs"
  value       = try(aws_s3_bucket.cloudtrail_logs[0].id, null)
}

output "cloudwatch_log_group_name" {
  description = "CloudWatch log group for platform logs"
  value       = try(aws_cloudwatch_log_group.platform[0].name, null)
}

output "kms_log_key_id" {
  description = "KMS key ID for log encryption"
  value       = try(aws_kms_key.logs[0].id, null)
  sensitive   = true
}

output "kms_log_key_arn" {
  description = "KMS key ARN for log encryption"
  value       = try(aws_kms_key.logs[0].arn, null)
  sensitive   = true
}

# ========== Budget & Alerts ==========

output "budget_sns_topic_arn" {
  description = "SNS topic for budget alerts"
  value       = try(aws_sns_topic.budget_alerts.arn, null)
}

output "budget_monthly_limit" {
  description = "Monthly budget limit in USD"
  value       = var.enable_budgets && var.monthly_budget_limit > 0 ? var.monthly_budget_limit : null
}

output "budget_alert_addresses" {
  description = "Email addresses for budget notifications"
  value       = var.budget_alert_emails
}
