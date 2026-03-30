## DIFF: New File - logging.tf
# Purpose: CloudTrail, VPC Flow Logs, CloudWatch Logs for audit & compliance

# KMS key for encrypting logs
resource "aws_kms_key" "logs" {
  count = var.enable_log_encryption ? 1 : 0

  description             = "KMS key for CloudWatch Logs encryption - ${var.project_name}-${var.environment}"
  deletion_window_in_days = 10
  enable_key_rotation     = var.kms_key_rotation_enabled

  tags = merge(
    local.common_tags,
    {
      Name = "${var.project_name}-logs-key"
    }
  )
}

resource "aws_kms_alias" "logs" {
  count         = var.enable_log_encryption ? 1 : 0
  name          = "alias/${var.project_name}-${var.environment}-logs"
  target_key_id = aws_kms_key.logs[0].key_id
}

# KMS key policy to allow CloudWatch Logs
resource "aws_kms_key_policy" "logs" {
  count   = var.enable_log_encryption ? 1 : 0
  key_id  = aws_kms_key.logs[0].id
  policy  = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow CloudWatch Logs"
        Effect = "Allow"
        Principal = {
          Service = "logs.${var.aws_region}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:CreateGrant",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
          }
        }
      }
    ]
  })
}

# S3 bucket for CloudTrail logs (versioning + lifecycle)
resource "aws_s3_bucket" "cloudtrail_logs" {
  count  = var.enable_logging ? 1 : 0
  bucket = "${var.project_name}-${var.environment}-cloudtrail-${data.aws_caller_identity.current.account_id}"

  tags = merge(
    local.common_tags,
    {
      Name = "${var.project_name}-cloudtrail-bucket"
    }
  )
}

resource "aws_s3_bucket_versioning" "cloudtrail_logs" {
  count  = var.enable_logging ? 1 : 0
  bucket = aws_s3_bucket.cloudtrail_logs[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail_logs" {
  count  = var.enable_logging && var.enable_log_encryption ? 1 : 0
  bucket = aws_s3_bucket.cloudtrail_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.logs[0].arn
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail_logs" {
  count  = var.enable_logging ? 1 : 0
  bucket = aws_s3_bucket.cloudtrail_logs[0].id

  rule {
    id     = "archive-old-logs"
    status = "Enabled"

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "GLACIER"
    }

    noncurrent_version_expiration {
      noncurrent_days = 365
    }
  }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail_logs" {
  count  = var.enable_logging ? 1 : 0
  bucket = aws_s3_bucket.cloudtrail_logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Bucket policy for CloudTrail
resource "aws_s3_bucket_policy" "cloudtrail_logs" {
  count  = var.enable_logging ? 1 : 0
  bucket = aws_s3_bucket.cloudtrail_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail_logs[0].arn
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail_logs[0].arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      },
      {
        Sid    = "DenyUnencryptedObjectUploads"
        Effect = "Deny"
        Principal = "*"
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail_logs[0].arn}/*"
        Condition = {
          StringNotEquals = {
            "s3:x-amz-server-side-encryption" = "aws:kms"
          }
        }
      }
    ]
  })
}

# CloudTrail for API audit
resource "aws_cloudtrail" "main" {
  count = var.enable_logging ? 1 : 0

  name                          = "${var.project_name}-${var.environment}-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail_logs[0].id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true
  kms_key_id                    = var.enable_log_encryption ? aws_kms_key.logs[0].arn : null
  depends_on                    = [aws_s3_bucket_policy.cloudtrail_logs[0]]

  event_selector {
    read_write_type           = "All"
    include_management_events = true

    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:aws:s3:::*"]
    }

    data_resource {
      type   = "AWS::Lambda::Function"
      values = ["arn:aws:lambda:*:*:function/*"]
    }
  }

  event_selector {
    read_write_type           = "WriteOnly"
    include_management_events = false

    data_resource {
      type   = "AWS::RDS::DBCluster"
      values = ["arn:aws:rds:*:*:cluster/*"]
    }
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.project_name}-cloudtrail"
    }
  )
}

# CloudWatch Log Group for structured logs
resource "aws_cloudwatch_log_group" "platform" {
  count = var.enable_logging ? 1 : 0

  name              = "${var.log_group_prefix}/${var.project_name}/${var.environment}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.enable_log_encryption ? aws_kms_key.logs[0].arn : null

  tags = merge(
    local.common_tags,
    {
      Name = "${var.project_name}-logs"
    }
  )
}

# CloudWatch Log Group for Terraform operations
resource "aws_cloudwatch_log_group" "terraform" {
  count = var.enable_logging ? 1 : 0

  name              = "${var.log_group_prefix}/terraform/${var.project_name}/${var.environment}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.enable_log_encryption ? aws_kms_key.logs[0].arn : null

  tags = merge(
    local.common_tags,
    {
      Name = "${var.project_name}-terraform-logs"
    }
  )
}

# VPC Flow Logs (requires VPC to be defined elsewhere)
resource "aws_flow_log_permission" "cloudwatch" {
  count = var.enable_logging ? 1 : 0

  principal       = "vpc-flow-logs.amazonaws.com"
  action          = "logs:PutSubscriptionFilter"
  statement_id    = "${var.project_name}-vpc-flow-logs"
  log_group_name  = aws_cloudwatch_log_group.platform[0].name
}

# CloudWatch Alarm for unusual log volume (anomaly detection)
resource "aws_cloudwatch_metric_alarm" "high_log_volume" {
  count = var.enable_logging && var.monitoring_enabled ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-high-log-volume"
  alarm_description   = "Alert when CloudWatch log ingestion is abnormally high"
  comparison_operator = "LessThanLowerOrGreaterThanUpperThreshold"
  evaluation_periods  = 2
  threshold_metric_id = "e1"
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "e1"
    expression  = "ANOMALY_DETECTION_BAND(m1, 2)"
    label       = "LogIngestion (Expected)"
    return_data = true
  }

  metric_query {
    id          = "m1"
    return_data = true
    metric {
      metric_name = "IncomingLogEvents"
      namespace   = "AWS/Logs"
      period      = 300
      stat        = "Sum"
      dimensions = {
        LogGroupName = aws_cloudwatch_log_group.platform[0].name
      }
    }
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.project_name}-log-volume-alarm"
    }
  )
}
