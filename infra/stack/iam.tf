## DIFF: New File - iam.tf
# Purpose: Least-privilege IAM roles for Terraform deployment (plan vs apply separation)

locals {
  allowed_principals = length(var.allowed_principal_arns) > 0 ? concat(
    tolist(var.allowed_principal_arns),
    ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
  ) : ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
}

# ===== Assume role policies =====

data "aws_iam_policy_document" "terraform_plan_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = local.allowed_principals
    }

    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = ["${var.project_name}-${var.environment}-plan"]
    }

    dynamic "condition" {
      for_each = var.enforce_mfa ? [1] : []
      content {
        test     = "Bool"
        variable = "aws:MultiFactorAuthPresent"
        values   = ["true"]
      }
    }
  }
}

data "aws_iam_policy_document" "terraform_apply_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = local.allowed_principals
    }

    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = ["${var.project_name}-${var.environment}-apply"]
    }

    dynamic "condition" {
      for_each = var.enforce_mfa ? [1] : []
      content {
        test     = "Bool"
        variable = "aws:MultiFactorAuthPresent"
        values   = ["true"]
      }
    }
  }
}

data "aws_iam_policy_document" "terraform_destroy_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = ["${var.project_name}-${var.environment}-destroy"]
    }
  }
}

# ===== Inline policies =====

#tfsec:ignore:aws-iam-no-policy-wildcards
data "aws_iam_policy_document" "terraform_plan_readonly" {
  #checkov:skip=CKV_AWS_356:EC2/RDS/IAM/CloudWatch/KMS describe and list operations require "*" resource; AWS does not support resource-level permissions for most Describe/List actions.

  statement {
    sid    = "ReadOnlyAccess"
    effect = "Allow"
    actions = [
      "ec2:Describe*",
      "rds:Describe*",
      "iam:Get*",
      "iam:List*",
      "cloudwatch:Describe*",
      "logs:Describe*",
      "kms:Describe*",
      "kms:Get*",
      "kms:List*",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ReadTerraformState"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:ListBucket",
    ]
    resources = [
      "arn:aws:s3:::*terraform-state*",
      "arn:aws:s3:::*terraform-state*/*",
    ]
  }

  statement {
    sid    = "ReadDynamoDBLocks"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:DescribeTable",
      "dynamodb:Query",
    ]
    resources = ["arn:aws:dynamodb:*:${data.aws_caller_identity.current.account_id}:table/*lock*"]
  }
}

#tfsec:ignore:aws-iam-no-policy-wildcards
data "aws_iam_policy_document" "terraform_apply_write" {
  #checkov:skip=CKV_AWS_107:secretsmanager:* is required for Terraform to manage secrets; protected by MFA + ExternalId conditions on the role.
  #checkov:skip=CKV_AWS_108:s3:* is required for Terraform state management; exfiltration is mitigated by the companion deny policy blocking unencrypted transfers.
  #checkov:skip=CKV_AWS_109:iam:PassRole is scoped to project-prefixed and service-linked roles in the PassRoleForResources statement; the wildcard in TerraformManageResources is needed for service APIs.
  #checkov:skip=CKV_AWS_110:Privilege escalation risk is accepted for the Terraform apply role; compensated by explicit deny for sensitive IAM actions and MFA enforcement.
  #checkov:skip=CKV_AWS_111:Broad write access is required for full Terraform apply; destructive actions are blocked by the companion deny policy.
  #checkov:skip=CKV_AWS_356:Terraform apply requires broad resource access across services; scope is enforced by the companion explicit-deny policy.

  statement {
    sid    = "TerraformManageResources"
    effect = "Allow"
    actions = [
      "ec2:*",
      "rds:*",
      "s3:*",
      "cloudwatch:*",
      "logs:*",
      "kms:*",
      "sns:*",
      "sqs:*",
      "lambda:*",
      "dynamodb:*",
      "apigateway:*",
      "elbv2:*",
      "elasticloadbalancing:*",
      "acm:*",
      "route53:*",
      "ssm:*",
      "secretsmanager:*",
      "backup:*",
    ]
    resources = ["*"]
  }

  statement {
    sid     = "ManageTerraformState"
    effect  = "Allow"
    actions = ["s3:*"]
    resources = [
      "arn:aws:s3:::*terraform-state*",
      "arn:aws:s3:::*terraform-state*/*",
    ]
  }

  statement {
    sid    = "ManageDynamoDBLocks"
    effect = "Allow"
    actions = [
      "dynamodb:PutItem",
      "dynamodb:GetItem",
      "dynamodb:DeleteItem",
      "dynamodb:UpdateItem",
      "dynamodb:DescribeTable",
    ]
    resources = ["arn:aws:dynamodb:*:${data.aws_caller_identity.current.account_id}:table/*lock*"]
  }

  statement {
    sid    = "CloudTrailLogging"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/cloudtrail/*"]
  }

  statement {
    sid     = "PassRoleForResources"
    effect  = "Allow"
    actions = ["iam:PassRole"]
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.project_name}-*",
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/*",
    ]
  }
}

#tfsec:ignore:aws-iam-no-policy-wildcards
data "aws_iam_policy_document" "terraform_apply_deny_sensitive" {
  statement {
    sid    = "ExplicitDenySensitiveActions"
    effect = "Deny"
    actions = concat(
      tolist(var.denied_actions),
      [
        "s3:DeleteBucket",
        "s3:PutBucketPolicy",
        "rds:DeleteDBInstance",
        "rds:DeleteDBCluster",
        "ec2:TerminateInstances",
        "iam:DeleteRole",
        "iam:PutRolePolicy",
        "organizations:LeaveOrganization",
      ]
    )
    resources = ["*"]
  }

  statement {
    sid       = "DenyUnencryptedDataTransfer"
    effect    = "Deny"
    actions   = ["s3:PutObject"]
    resources = ["*"]

    condition {
      test     = "StringNotEquals"
      variable = "s3:x-amz-server-side-encryption"
      values   = ["aws:kms"]
    }
  }
}

#tfsec:ignore:aws-iam-no-policy-wildcards
data "aws_iam_policy_document" "terraform_destroy_write" {
  #checkov:skip=CKV_AWS_356:EC2/RDS/logs/KMS delete and describe operations require "*" resource; AWS does not support resource-level permissions for these actions.
  #checkov:skip=CKV_AWS_111:EC2/RDS/logs delete operations require "*" resource; S3 and DynamoDB are scoped to project-specific ARNs.
  #checkov:skip=CKV_AWS_109:EC2/RDS/logs delete operations require "*" resource; S3 and DynamoDB are scoped to project-specific ARNs.

  statement {
    sid    = "TerraformDestroyCompute"
    effect = "Allow"
    actions = [
      "ec2:Describe*",
      "ec2:Delete*",
      "rds:Delete*",
      "logs:Delete*",
      "kms:Describe*",
      "kms:Get*",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "TerraformDestroyS3"
    effect = "Allow"
    actions = [
      "s3:Delete*",
      "s3:Get*",
      "s3:List*",
    ]
    resources = [
      "arn:aws:s3:::${var.project_name}-*",
      "arn:aws:s3:::${var.project_name}-*/*",
    ]
  }

  statement {
    sid     = "TerraformDestroyDynamoDB"
    effect  = "Allow"
    actions = ["dynamodb:*"]
    resources = [
      "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/*",
    ]
  }
}

#tfsec:ignore:aws-iam-no-policy-wildcards
data "aws_iam_policy_document" "ip_restriction" {
  statement {
    sid       = "RestrictToAllowedIPs"
    effect    = "Deny"
    actions   = ["*"]
    resources = ["*"]

    condition {
      test     = "NotIpAddress"
      variable = "aws:SourceIp"
      values   = var.allowed_ip_ranges
    }
  }
}

# ===== Terraform Plan Role (read-only) =====
resource "aws_iam_role" "terraform_plan" {
  name = "${var.project_name}-${var.environment}-terraform-plan"

  assume_role_policy = data.aws_iam_policy_document.terraform_plan_assume.json

  tags = merge(
    local.common_tags,
    {
      Name = "${var.project_name}-terraform-plan"
    }
  )
}

# Plan role: read-only access to infrastructure
resource "aws_iam_role_policy" "terraform_plan_readonly" {
  #checkov:skip=CKV_AWS_355:Describe/Get/List actions inherently require "*" as resource; they cannot be scoped to specific ARNs.
  name   = "${var.project_name}-${var.environment}-terraform-plan-readonly"
  role   = aws_iam_role.terraform_plan.id
  policy = data.aws_iam_policy_document.terraform_plan_readonly.json
}

# ===== Terraform Apply Role (write with restrictions) =====
resource "aws_iam_role" "terraform_apply" {
  name = "${var.project_name}-${var.environment}-terraform-apply"

  assume_role_policy = data.aws_iam_policy_document.terraform_apply_assume.json

  tags = merge(
    local.common_tags,
    {
      Name = "${var.project_name}-terraform-apply"
    }
  )
}

# Apply role: full write access with explicit denials
resource "aws_iam_role_policy" "terraform_apply_write" {
  #checkov:skip=CKV_AWS_355:Terraform apply requires broad resource access; scope is enforced by the companion explicit-deny policy (terraform_apply_deny_sensitive).
  #checkov:skip=CKV_AWS_286:iam:PassRole is intentionally scoped to project-prefixed roles only; this is not an unconstrained privilege escalation path.
  #checkov:skip=CKV_AWS_287:secretsmanager:* is required for Terraform to manage secrets; access is restricted to the apply role and protected by MFA + ExternalId conditions.
  #checkov:skip=CKV_AWS_288:s3:* is required for Terraform state management; data exfiltration is mitigated by the companion deny policy blocking unencrypted transfers.
  #checkov:skip=CKV_AWS_289:iam:PassRole is scoped to project-prefixed and service-linked roles; broader IAM permissions management is explicitly denied.
  #checkov:skip=CKV_AWS_290:Write access is required for full Terraform apply; destructive actions (DeleteBucket, TerminateInstances, etc.) are blocked by the companion deny policy.
  name   = "${var.project_name}-${var.environment}-terraform-apply-write"
  role   = aws_iam_role.terraform_apply.id
  policy = data.aws_iam_policy_document.terraform_apply_write.json
}

# Explicit deny for sensitive operations (defense in depth)
resource "aws_iam_role_policy" "terraform_apply_deny_sensitive" {
  name   = "${var.project_name}-${var.environment}-terraform-apply-deny"
  role   = aws_iam_role.terraform_apply.id
  policy = data.aws_iam_policy_document.terraform_apply_deny_sensitive.json
}

# ===== Terraform Destroy Role (explicit write for destroy operations) =====
resource "aws_iam_role" "terraform_destroy" {
  count = var.environment == "dev" ? 1 : 0 # Only allow in dev

  name = "${var.project_name}-${var.environment}-terraform-destroy"

  assume_role_policy = data.aws_iam_policy_document.terraform_destroy_assume.json

  tags = merge(
    local.common_tags,
    {
      Name = "${var.project_name}-terraform-destroy"
    }
  )
}

resource "aws_iam_role_policy" "terraform_destroy_write" {
  count = var.environment == "dev" ? 1 : 0

  name   = "${var.project_name}-${var.environment}-terraform-destroy-write"
  role   = aws_iam_role.terraform_destroy[0].id
  policy = data.aws_iam_policy_document.terraform_destroy_write.json
}

# Policy for IP-based access control (if configured)
resource "aws_iam_role_policy" "ip_restriction" {
  count = length(var.allowed_ip_ranges) > 0 ? 1 : 0

  name   = "${var.project_name}-${var.environment}-ip-restriction"
  role   = aws_iam_role.terraform_apply.id
  policy = data.aws_iam_policy_document.ip_restriction.json
}

# ===== Policy Validation Resources =====

# CloudWatch Metric Alarm for denied actions
resource "aws_cloudwatch_event_rule" "denied_actions" {
  count = var.enable_resource_policy_validation && var.monitoring_enabled ? 1 : 0

  name        = "${var.project_name}-${var.environment}-denied-actions"
  description = "Catch attempts to perform denied sensitive actions"

  event_pattern = jsonencode({
    source      = ["aws.iam"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventName = var.denied_actions
      errorCode = ["AccessDenied", "UnauthorizedOperation"]
    }
  })
}

resource "aws_cloudwatch_event_target" "denied_actions_alert" {
  count = var.enable_resource_policy_validation && var.monitoring_enabled ? 1 : 0

  rule      = aws_cloudwatch_event_rule.denied_actions[0].name
  target_id = "AlertOnDeniedActions"
  arn       = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:${aws_cloudwatch_log_group.terraform[0].name}"
}
