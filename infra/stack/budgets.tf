## DIFF: New File - budgets.tf
# Purpose: AWS Budgets + SNS alerts for cost governance

# Budget notification SNS topic
resource "aws_sns_topic" "budget_alerts" {
  name              = "${var.project_name}-${var.environment}-budget-alerts"
  kms_master_key_id = "alias/aws/sns"

  tags = merge(
    local.common_tags,
    {
      Name = "${var.project_name}-budget-alerts"
    }
  )
}

data "aws_iam_policy_document" "budget_alerts_sns" {
  statement {
    effect    = "Allow"
    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.budget_alerts.arn]

    principals {
      type        = "Service"
      identifiers = ["budgets.amazonaws.com"]
    }
  }
}

resource "aws_sns_topic_policy" "budget_alerts" {
  arn    = aws_sns_topic.budget_alerts.arn
  policy = data.aws_iam_policy_document.budget_alerts_sns.json
}

# Email subscriptions
resource "aws_sns_topic_subscription" "budget_alerts_email" {
  for_each = var.budget_alert_emails

  topic_arn = aws_sns_topic.budget_alerts.arn
  protocol  = "email"
  endpoint  = each.value
}

# Monthly spend budget with alerts at multiple thresholds
resource "aws_budgets_budget" "monthly" {
  count = var.enable_budgets && var.monthly_budget_limit > 0 ? 1 : 0

  name              = "${var.project_name}-${var.environment}-monthly"
  budget_type       = "MONTHLY"
  limit_type        = "FORECASTED"
  limit_unit        = "USD"
  limited_amount    = var.monthly_budget_limit
  time_period_start = "2024-01-01_00:00"
  time_period_end   = "2087-12-31_23:59"

  tags = merge(
    local.common_tags,
    {
      Name = "${var.project_name}-monthly-budget"
    }
  )

  depends_on = [aws_sns_topic_policy.budget_alerts]
}

# Budget notifications for each threshold
resource "aws_budgets_budget_action" "threshold_alerts" {
  for_each = var.enable_budgets && var.monthly_budget_limit > 0 ? var.budget_alert_thresholds : toset([])

  budget_name = try(aws_budgets_budget.monthly[0].name, "")

  action_id              = "${var.project_name}-alert-${each.value}"
  action_type            = "APPLY_IAM_POLICY"
  approval_model         = "AUTOMATIC"
  execution_role_arn     = try(aws_iam_role.budget_action[0].arn, "")
  notification_type      = "FORECASTED"
  threshold_type         = "PERCENTAGE"
  threshold_value        = each.value
  action_threshold_value = each.value
  action_threshold_type  = "PERCENTAGE"

  notification_with_subscribers {
    account_id = data.aws_caller_identity.current.account_id
    type       = "FORECASTED"
    addresses  = [aws_sns_topic.budget_alerts.arn]
  }

  lifecycle {
    ignore_changes = [budget_arn]
  }

  depends_on = [
    aws_budgets_budget.monthly,
    aws_iam_role.budget_action
  ]
}

data "aws_iam_policy_document" "budget_action_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["budgets.amazonaws.com"]
    }
  }
}

# IAM role for budget actions
resource "aws_iam_role" "budget_action" {
  count = var.enable_budgets && var.monthly_budget_limit > 0 ? 1 : 0

  name = "${var.project_name}-${var.environment}-budget-action"

  assume_role_policy = data.aws_iam_policy_document.budget_action_assume.json

  tags = merge(
    local.common_tags,
    {
      Name = "${var.project_name}-budget-action-role"
    }
  )
}

# Data source for current AWS account
data "aws_caller_identity" "current" {}
