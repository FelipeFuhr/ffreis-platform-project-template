# Platform Project - Example Resources

This file demonstrates best practices for adding resources to your platform project.
**This is for reference only and should be deleted or adapted to your needs.**

## Example 1: S3 Bucket with Security Best Practices

```hcl
resource "aws_s3_bucket" "application_data" {
  bucket = "${var.project_name}-data-${var.environment}"

  tags = {
    Name = "${var.project_name}-data"
  }
}

# Enable versioning for disaster recovery
resource "aws_s3_bucket_versioning" "application_data" {
  bucket = aws_s3_bucket.application_data.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Enable encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "application_data" {
  bucket = aws_s3_bucket.application_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block public access
resource "aws_s3_bucket_public_access_block" "application_data" {
  bucket = aws_s3_bucket.application_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
```

## Example 2: Lambda Function Module

```hcl
module "event_processor" {
  source = "../modules/lambda-function"

  function_name = "${var.project_name}-event-processor"
  runtime       = "python3.11"
  handler       = "index.handler"
  source_code_path = "../src/lambda/event_processor"

  environment_variables = {
    QUEUE_URL = aws_sqs_queue.events.url
    TABLE_NAME = aws_dynamodb_table.events.name
  }

  environment = var.environment

  tags = {
    Application = "event-processing"
  }
}
```

## Example 3: DynamoDB Table with Monitoring

```hcl
resource "aws_dynamodb_table" "application_state" {
  name           = "${var.project_name}-state-${var.environment}"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "id"
  range_key      = "timestamp"

  attribute {
    name = "id"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "N"
  }

  # Enable automatic backups
  point_in_time_recovery_specification {
    point_in_time_recovery_enabled = true
  }

  # Enable encryption at rest
  server_side_encryption_specification {
    enabled = true
  }

  # Enable TTL for automatic cleanup
  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  # Monitor in CloudWatch
  stream_specification {
    stream_view_type = "NEW_AND_OLD_IMAGES"
  }

  tags = {
    Name = "${var.project_name}-state"
  }
}
```

## Example 4: Output Values for External Use

```hcl
output "s3_bucket_name" {
  description = "Name of the application data S3 bucket"
  value       = aws_s3_bucket.application_data.id
}

output "dynamodb_table_name" {
  description = "Name of the application state DynamoDB table"
  value       = aws_dynamodb_table.application_state.name
}

output "lambda_function_arn" {
  description = "ARN of the event processor Lambda function"
  value       = module.event_processor.function_arn
}
```

## Integration with Environments

Use terraform vars to customize per environment:

**envs/prod/terraform.tfvars:**
```hcl
enable_encryption = true
backup_retention_days = 30
```

**envs/staging/terraform.tfvars:**
```hcl
enable_encryption = true
backup_retention_days = 7
```

Then reference in your configuration:

```hcl
variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 7
}

resource "aws_dynamodb_table" "application_state" {
  # ... other config ...
  
  # Only enable TTL in prod for cost savings
  ttl {
    attribute_name = "expires_at"
    enabled        = var.enable_encryption
  }
}
```

## Testing Locally

1. **Validate syntax**
   ```bash
   make validate
   ```

2. **Plan in staging**
   ```bash
   make plan ENV=staging
   ```

3. **Review plan output** for expected changes

4. **Apply to staging** when confident
   ```bash
   make apply ENV=staging
   ```

5. **Test the resources** manually

6. **Plan in production**
   ```bash
   make plan ENV=prod
   ```

7. **Get team approval** and apply

## Common Patterns

### Conditional Resources

```hcl
variable "create_backup_vault" {
  type    = bool
  default = false
}

resource "aws_backup_vault" "data" {
  count       = var.create_backup_vault ? 1 : 0
  name        = "${var.project_name}-vault"
  kms_key_arn = aws_kms_key.backup.arn
}
```

### Per-Environment Configuration

```hcl
locals {
  config = {
    prod = {
      instance_count = 3
      instance_type  = "t3.large"
      backup_enabled = true
    }
    staging = {
      instance_count = 1
      instance_type  = "t3.micro"
      backup_enabled = false
    }
  }
}

resource "aws_instance" "app_server" {
  count         = local.config[var.environment].instance_count
  instance_type = local.config[var.environment].instance_type
  # ... rest of config
}
```

### Cross-Resource References

```hcl
# In the same stack, reference resources directly
resource "aws_iam_role_policy" "lambda_access" {
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "dynamodb:*"
        Resource = aws_dynamodb_table.application_state.arn
      }
    ]
  })
}
```

---

**Remove this file before deploying to production.**
