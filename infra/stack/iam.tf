## DIFF: New File - iam.tf
# Purpose: Least-privilege IAM roles for Terraform deployment (plan vs apply separation)

locals {
  # Policy condition for MFA requirement
  mfa_condition = var.enforce_mfa ? {
    Bool = {
      "aws:MultiFactorAuthPresent" = "true"
    }
  } : null
}

# ===== Terraform Plan Role (read-only) =====
resource "aws_iam_role" "terraform_plan" {
  name = "${var.project_name}-${var.environment}-terraform-plan"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = length(var.allowed_principal_arns) > 0 ? concat(
            var.allowed_principal_arns,
            ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
          ) : ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
        }
        Action = "sts:AssumeRole"
        Condition = merge(
          local.mfa_condition != null ? { MfaPresent : local.mfa_condition } : {},
          {
            StringEquals = {
              "sts:ExternalId" = "${var.project_name}-${var.environment}-plan"
            }
          }
        )
      }
    ]
  })

  tags = merge(
    local.common_tags,
    {
      Name = "${var.project_name}-terraform-plan"
    }
  )
}

# Plan role: read-only access to infrastructure
resource "aws_iam_role_policy" "terraform_plan_readonly" {
  name   = "${var.project_name}-${var.environment}-terraform-plan-readonly"
  role   = aws_iam_role.terraform_plan.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadOnlyAccess"
        Effect = "Allow"
        Action = [
          "ec2:Describe*",
          "rds:Describe*",
          "s3:Get*",
          "s3:List*",
          "iam:Get*",
          "iam:List*",
          "cloudwatch:Describe*",
          "logs:Describe*",
          "kms:Describe*",
          "kms:Get*",
          "kms:List*"
        ]
        Resource = "*"
      },
      {
        Sid    = "ReadTerraformState"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::*terraform-state*",
          "arn:aws:s3:::*terraform-state*/*"
        ]
      },
      {
        Sid    = "ReadDynamoDBLocks"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:DescribeTable",
          "dynamodb:Query"
        ]
        Resource = "arn:aws:dynamodb:*:${data.aws_caller_identity.current.account_id}:table/*lock*"
      }
    ]
  })
}

# ===== Terraform Apply Role (write with restrictions) =====
resource "aws_iam_role" "terraform_apply" {
  name = "${var.project_name}-${var.environment}-terraform-apply"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = length(var.allowed_principal_arns) > 0 ? concat(
            var.allowed_principal_arns,
            ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
          ) : ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
        }
        Action = "sts:AssumeRole"
        Condition = merge(
          local.mfa_condition != null ? { MfaPresent : local.mfa_condition } : {},
          {
            StringEquals = {
              "sts:ExternalId" = "${var.project_name}-${var.environment}-apply"
            }
          }
        )
      }
    ]
  })

  tags = merge(
    local.common_tags,
    {
      Name = "${var.project_name}-terraform-apply"
    }
  )
}

# Apply role: full write access with explicit denials
resource "aws_iam_role_policy" "terraform_apply_write" {
  name   = "${var.project_name}-${var.environment}-terraform-apply-write"
  role   = aws_iam_role.terraform_apply.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "TerraformManageResources"
        Effect = "Allow"
        Action = [
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
          "backup:*"
        ]
        Resource = "*"
      },
      {
        Sid    = "ManageTerraformState"
        Effect = "Allow"
        Action = [
          "s3:*"
        ]
        Resource = [
          "arn:aws:s3:::*terraform-state*",
          "arn:aws:s3:::*terraform-state*/*"
        ]
      },
      {
        Sid    = "ManageDynamoDBLocks"
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:DeleteItem",
          "dynamodb:UpdateItem",
          "dynamodb:DescribeTable"
        ]
        Resource = "arn:aws:dynamodb:*:${data.aws_caller_identity.current.account_id}:table/*lock*"
      },
      {
        Sid    = "CloudTrailLogging"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/cloudtrail/*"
      },
      {
        Sid    = "PassRoleForResources"
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = [
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.project_name}-*",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/*"
        ]
      }
    ]
  })
}

# Explicit deny for sensitive operations (defense in depth)
resource "aws_iam_role_policy" "terraform_apply_deny_sensitive" {
  name   = "${var.project_name}-${var.environment}-terraform-apply-deny"
  role   = aws_iam_role.terraform_apply.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ExplicitDenySensitiveActions"
        Effect = "Deny"
        Action = concat(
          var.denied_actions,
          [
            "s3:DeleteBucket",
            "s3:PutBucketPolicy",
            "rds:DeleteDBInstance",
            "rds:DeleteDBCluster",
            "ec2:TerminateInstances",
            "iam:DeleteRole",
            "iam:PutRolePolicy",
            "organizations:LeaveOrganization"
          ]
        )
        Resource = "*"
      },
      {
        Sid    = "DenyUnencryptedDataTransfer"
        Effect = "Deny"
        Action = [
          "s3:PutObject"
        ]
        Resource = "*"
        Condition = {
          StringNotEquals = {
            "s3:x-amz-server-side-encryption" = "aws:kms"
          }
        }
      }
    ]
  })
}

# ===== Terraform Destroy Role (explicit write for destroy operations) =====
resource "aws_iam_role" "terraform_destroy" {
  count = var.environment == "dev" ? 1 : 0  # Only allow in dev

  name = "${var.project_name}-${var.environment}-terraform-destroy"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "sts:ExternalId" = "${var.project_name}-${var.environment}-destroy"
          }
        }
      }
    ]
  })

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
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "TerraformDestroyResources"
        Effect = "Allow"
        Action = [
          "ec2:Describe*",
          "ec2:Delete*",
          "s3:Delete*",
          "s3:Get*",
          "s3:List*",
          "rds:Delete*",
          "logs:Delete*",
          "kms:Describe*",
          "kms:Get*",
          "dynamodb:*"
        ]
        Resource = "*"
      }
    ]
  })
}

# Policy for IP-based access control (if configured)
resource "aws_iam_role_policy" "ip_restriction" {
  count = length(var.allowed_ip_ranges) > 0 ? 1 : 0

  name   = "${var.project_name}-${var.environment}-ip-restriction"
  role   = aws_iam_role.terraform_apply.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RestrictToAllowedIPs"
        Effect = "Deny"
        Action = "*"
        Resource = "*"
        Condition = {
          NotIpAddress = {
            "aws:SourceIp" = var.allowed_ip_ranges
          }
        }
      }
    ]
  })
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
