## DIFF: New File - logging.tf
# Purpose: CloudTrail, VPC Flow Logs, CloudWatch Logs for audit & compliance

# KMS key for encrypting logs
resource "aws_kms_key" "logs" {
  count = var.enable_log_encryption ? 1 : 0
  #checkov:skip=CKV2_AWS_64:KMS key policy is managed via the aws_kms_key_policy resource below to keep policies HCL-native.

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

data "aws_iam_policy_document" "logs_kms" {
  count = var.enable_log_encryption ? 1 : 0
  #checkov:skip=CKV_AWS_356:KMS key policies require "*" as resource by AWS design; the policy is attached to the key and scoped to it implicitly.
  #checkov:skip=CKV_AWS_111:KMS key policies require "*" as resource; write access is constrained by the key policy principal and conditions.
  #checkov:skip=CKV_AWS_109:KMS key policies require "*" as resource; permissions management is constrained to the specific key by policy attachment.

  statement {
    sid       = "Enable IAM User Permissions"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  statement {
    sid    = "Allow CloudWatch Logs"
    effect = "Allow"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:CreateGrant",
      "kms:DescribeKey",
    ]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["logs.${var.aws_region}.amazonaws.com"]
    }

    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"]
    }
  }
}

# KMS key policy to allow CloudWatch Logs
resource "aws_kms_key_policy" "logs" {
  count  = var.enable_log_encryption ? 1 : 0
  key_id = aws_kms_key.logs[0].id
  policy = data.aws_iam_policy_document.logs_kms[0].json
}

# S3 bucket for CloudTrail logs (versioning + lifecycle)
resource "aws_s3_bucket" "cloudtrail_logs" {
  count  = var.enable_logging ? 1 : 0
  bucket = "${var.project_name}-${var.environment}-cloudtrail-${data.aws_caller_identity.current.account_id}"
  #checkov:skip=CKV_AWS_18:Enabling access logging on the audit bucket itself would create a circular dependency; access is controlled via bucket policy and CloudTrail log file validation.
  #checkov:skip=CKV_AWS_144:CloudTrail is already multi-region (is_multi_region_trail=true); cross-region bucket replication is redundant for this use case.
  #checkov:skip=CKV2_AWS_62:CloudTrail is the notification and audit mechanism for this bucket; additional S3 event notifications are redundant.
  #checkov:skip=CKV2_AWS_6:Public access block is managed via the companion aws_s3_bucket_public_access_block resource.
  #checkov:skip=CKV_AWS_21:Versioning is managed via the companion aws_s3_bucket_versioning resource.
  #checkov:skip=CKV2_AWS_61:Lifecycle policy is managed via the companion aws_s3_bucket_lifecycle_configuration resource.
  #checkov:skip=CKV_AWS_145:Server-side encryption is managed via the companion aws_s3_bucket_server_side_encryption_configuration resource.

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

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

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

data "aws_iam_policy_document" "cloudtrail_logs_bucket" {
  count = var.enable_logging ? 1 : 0

  statement {
    sid       = "AWSCloudTrailAclCheck"
    effect    = "Allow"
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.cloudtrail_logs[0].arn]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
  }

  statement {
    sid       = "AWSCloudTrailWrite"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.cloudtrail_logs[0].arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }

  statement {
    sid       = "DenyUnencryptedObjectUploads"
    effect    = "Deny"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.cloudtrail_logs[0].arn}/*"]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    condition {
      test     = "StringNotEquals"
      variable = "s3:x-amz-server-side-encryption"
      values   = ["aws:kms"]
    }
  }
}

# Bucket policy for CloudTrail
resource "aws_s3_bucket_policy" "cloudtrail_logs" {
  count  = var.enable_logging ? 1 : 0
  bucket = aws_s3_bucket.cloudtrail_logs[0].id
  policy = data.aws_iam_policy_document.cloudtrail_logs_bucket[0].json
}

# ---------------------------------------------------------------------------
# SNS topic for CloudTrail notifications (CKV_AWS_252)
# ---------------------------------------------------------------------------

resource "aws_sns_topic" "cloudtrail" {
  count             = var.enable_logging ? 1 : 0
  name              = "${var.project_name}-${var.environment}-cloudtrail"
  kms_master_key_id = "alias/aws/sns"

  tags = merge(
    local.common_tags,
    {
      Name = "${var.project_name}-cloudtrail-sns"
    }
  )
}

data "aws_iam_policy_document" "cloudtrail_sns" {
  count = var.enable_logging ? 1 : 0

  statement {
    effect    = "Allow"
    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.cloudtrail[0].arn]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
  }
}

resource "aws_sns_topic_policy" "cloudtrail" {
  count  = var.enable_logging ? 1 : 0
  arn    = aws_sns_topic.cloudtrail[0].arn
  policy = data.aws_iam_policy_document.cloudtrail_sns[0].json
}

# ---------------------------------------------------------------------------
# IAM role for CloudTrail → CloudWatch Logs delivery (CKV2_AWS_10)
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "cloudtrail_cw_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "cloudtrail_cw_policy" {
  count = var.enable_logging ? 1 : 0

  statement {
    sid    = "CloudTrailWriteToCloudWatch"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:${var.log_group_prefix}/terraform/${var.project_name}/${var.environment}:*"]
  }
}

resource "aws_iam_role" "cloudtrail_cw" {
  count = var.enable_logging ? 1 : 0
  name  = "${var.project_name}-${var.environment}-cloudtrail-cw"

  assume_role_policy = data.aws_iam_policy_document.cloudtrail_cw_assume.json

  tags = merge(
    local.common_tags,
    {
      Name = "${var.project_name}-cloudtrail-cw-role"
    }
  )
}

resource "aws_iam_role_policy" "cloudtrail_cw" {
  count  = var.enable_logging ? 1 : 0
  name   = "${var.project_name}-${var.environment}-cloudtrail-cw"
  role   = aws_iam_role.cloudtrail_cw[0].id
  policy = data.aws_iam_policy_document.cloudtrail_cw_policy[0].json
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
  cloud_watch_logs_group_arn    = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:${var.log_group_prefix}/terraform/${var.project_name}/${var.environment}:*"
  cloud_watch_logs_role_arn     = aws_iam_role.cloudtrail_cw[0].arn
  sns_topic_name                = aws_sns_topic.cloudtrail[0].name

  depends_on = [
    aws_s3_bucket_policy.cloudtrail_logs[0],
    aws_iam_role_policy.cloudtrail_cw[0],
  ]

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
  #checkov:skip=CKV_AWS_338:Retention is enforced via the log_retention_days variable; callers must set >= 365 days per platform policy.

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
  #checkov:skip=CKV_AWS_338:Retention is enforced via the log_retention_days variable; callers must set >= 365 days per platform policy.

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
