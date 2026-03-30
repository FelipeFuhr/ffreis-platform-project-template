variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]{1}$", var.aws_region))
    error_message = "Must be a valid AWS region code."
  }
}

variable "aws_profile" {
  description = "AWS profile to use (or empty to use environment/assumed role)"
  type        = string
  default     = ""
}

variable "project_name" {
  description = "Project name for resource naming and tagging (alphanumeric, hyphens only)"
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name)) && length(var.project_name) <= 32
    error_message = "Must be lowercase alphanumeric and hyphens, max 32 characters."
  }
}

variable "environment" {
  description = "Environment name (prod, staging, dev)"
  type        = string
  validation {
    condition     = contains(["prod", "staging", "dev"], var.environment)
    error_message = "Environment must be prod, staging, or dev."
  }
}

# ========== Tagging & Governance ==========

variable "tags" {
  description = "Additional tags applied to all resources"
  type        = map(string)
  default     = {}
}

variable "cost_center" {
  description = "Cost center for billing allocation"
  type        = string
  default     = "engineering"
  validation {
    condition     = length(var.cost_center) > 0 && length(var.cost_center) <= 32
    error_message = "Cost center must be 1-32 characters."
  }
}

variable "compliance_framework" {
  description = "Compliance framework (SOC2, HIPAA, GDPR, PCI-DSS, None)"
  type        = string
  default     = "None"
  validation {
    condition     = contains(["SOC2", "HIPAA", "GDPR", "PCI-DSS", "None"], var.compliance_framework)
    error_message = "Must be one of: SOC2, HIPAA, GDPR, PCI-DSS, None."
  }
}

variable "data_classification" {
  description = "Data classification level (Public, Internal, Confidential, Secret)"
  type        = string
  default     = "Internal"
  validation {
    condition     = contains(["Public", "Internal", "Confidential", "Secret"], var.data_classification)
    error_message = "Must be one of: Public, Internal, Confidential, Secret."
  }
}

variable "backup_policy" {
  description = "Backup retention policy (daily, weekly, monthly)"
  type        = string
  default     = "daily"
  validation {
    condition     = contains(["daily", "weekly", "monthly"], var.backup_policy)
    error_message = "Must be one of: daily, weekly, monthly."
  }
}

# ========== Budget & Cost Controls ==========

variable "enable_budgets" {
  description = "Enable AWS Budgets for cost monitoring"
  type        = bool
  default     = true
}

variable "monthly_budget_limit" {
  description = "Monthly spend limit in USD (0 = disabled)"
  type        = number
  default     = 0
  validation {
    condition     = var.monthly_budget_limit >= 0
    error_message = "Budget limit must be >= 0."
  }
}

variable "budget_alert_thresholds" {
  description = "Percentage thresholds for budget alerts (50, 75, 90, 100)"
  type        = set(number)
  default     = [50, 75, 90, 100]
  validation {
    condition     = alltrue([for t in var.budget_alert_thresholds : t > 0 && t <= 100])
    error_message = "All thresholds must be between 1 and 100."
  }
}

variable "budget_alert_emails" {
  description = "Email addresses for budget alerts"
  type        = set(string)
  default     = []
  validation {
    condition     = alltrue([for email in var.budget_alert_emails : can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))])
    error_message = "All values must be valid email addresses."
  }
}

# ========== Logging & Monitoring ==========

variable "enable_logging" {
  description = "Enable CloudWatch logging for all resources"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days (0 = infinite)"
  type        = number
  default     = 30
  validation {
    condition     = var.log_retention_days >= 0 && (var.log_retention_days == 0 || var.log_retention_days >= 7)
    error_message = "Log retention must be 0 (infinite) or >= 7 days."
  }
}

variable "enable_log_encryption" {
  description = "Enable KMS encryption for CloudWatch logs"
  type        = bool
  default     = true
}

variable "log_group_prefix" {
  description = "Common prefix for all CloudWatch log groups"
  type        = string
  default     = "/aws/platform"
}

variable "enable_xray_tracing" {
  description = "Enable AWS X-Ray tracing for distributed tracing"
  type        = bool
  default     = false
}

variable "monitoring_enabled" {
  description = "Enable CloudWatch alarms and dashboards"
  type        = bool
  default     = true
}

# ========== IAM & Security ==========

variable "enforce_mfa" {
  description = "Require MFA for sensitive operations"
  type        = bool
  default     = true
}

variable "allowed_principal_arns" {
  description = "Principal ARNs allowed to assume deployment roles (least privilege)"
  type        = set(string)
  default     = []
}

variable "denied_actions" {
  description = "Actions explicitly denied for security"
  type        = set(string)
  default = [
    "iam:*",
    "organizations:*",
    "account:*",
    "servicecatalog:*",
    "ec2:TerminateInstances",
    "rds:DeleteDBInstance",
    "s3:*Delete*",
  ]
}

variable "enable_resource_policy_validation" {
  description = "Validate resource policies for public access"
  type        = bool
  default     = true
}

variable "enable_encryption_validation" {
  description = "Require encryption for data at rest and in transit"
  type        = bool
  default     = true
}

variable "kms_key_rotation_enabled" {
  description = "Enable automatic KMS key rotation"
  type        = bool
  default     = true
}

variable "require_https_only" {
  description = "Enforce HTTPS for all API calls"
  type        = bool
  default     = true
}

variable "allowed_ip_ranges" {
  description = "IP ranges allowed for administrative access (CIDR notation)"
  type        = set(string)
  default     = []
}
