# Contributing to Platform Projects

## Development Workflow

1. **Create a feature branch**
   ```bash
   git checkout -b feature/add-rds-database
   ```

2. **Make changes and validate**
   ```bash
   make fmt-check    # Check formatting
   make validate     # Validate syntax
   make check        # Run all checks
   ```

3. **Test locally in staging**
   ```bash
   make plan ENV=staging
   # Review output carefully
   ```

4. **Push and create PR**
   ```bash
   git push origin feature/add-rds-database
   ```

5. **Review GitHub Actions output**
   - terraform-plan.yml will comment with plan
   - lint-security.yml will check for issues
   - Review all feedback

6. **Merge and apply**
   - Staging applies automatically on main
   - Production requires manual approval

## Code Standards

### Formatting

All terraform files must be formatted per HCL conventions:

```bash
# Automatic formatting
make fmt

# Check without modifying
make fmt-check
```

### Naming Conventions

- **Resources**: Use descriptive snake_case
  ```hcl
  resource "aws_s3_bucket" "application_logs" { ... }
  ```

- **Variables**: Use snake_case (not pascalcase)
  ```hcl
  variable "enable_encryption" { ... }
  ```

- **Outputs**: Use snake_case with descriptive names
  ```hcl
  output "database_endpoint" { ... }
  ```

- **Modules**: Use kebab-case directories
  ```
  infra/modules/rds-cluster/
  ```

### Documentation

- All variables should have descriptions
- All outputs should be documented
- Complex resources should have inline comments

Example:

```hcl
variable "enable_encryption" {
  description = "Enable server-side encryption for storage services"
  type        = bool
  default     = true
}

output "s3_bucket_arn" {
  description = "ARN of the created S3 bucket"
  value       = aws_s3_bucket.data.arn
}
```

## Security Review Checklist

Before merging, ensure:

- ✅ No hardcoded secrets or credentials
- ✅ All sensitive data encrypted in transit
- ✅ IAM policies follow least-privilege principle
- ✅ Network resources have appropriate security groups
- ✅ DynamoDB tables have encryption enabled
- ✅ S3 buckets have versioning and bucket policies
- ✅ No public access to private resources
- ✅ Logging is enabled for compliance

## Environment-Specific Changes

### Staging (Lower Risk)

- Can be deployed immediately after approval
- Test destructive operations here first
- Safe for experimental changes

### Production (Higher Risk)

- Requires explicit approval/confirmation
- Should be tested in staging first
- Keep changes small and focused

## Rollback Procedures

### Quick Rollback

1. Revert the commit
2. Push to main
3. GitHub Actions will apply the reverted state

### Manual Rollback

```bash
# Find previous state version
make lock-info ENV=prod

# Get previous state from S3
aws s3 cp s3://ffreis-tf-state/platform-project/prod/terraform.tfstate.backup .

# Load and apply
terraform state pull < terraform.tfstate.backup
make apply ENV=prod
```

## Team Communication

When making significant changes:

1. **Announce** in #infrastructure or team channel
2. **Allow review time** (at least 24 hours for prod)
3. **Monitor** during and after deployment
4. **Document** any issues or workarounds

## Module Development

When creating new modules:

1. **Keep focused**: One concern per module
2. **Make configurable**: Use variables, not hardcoded values
3. **Export outputs**: Provide values for composition
4. **Test locally**: Create a test environment
5. **Document**: Include examples and usage notes

Example module structure:

```
infra/modules/rds-cluster/
├── main.tf
├── variables.tf
├── outputs.tf
├── terraform.tfvars.example
└── README.md
```

## Debugging Tips

### Check State

```bash
# Export specific resource
terraform state show 'aws_s3_bucket.my_bucket'

# List all resources
terraform state list
```

### Verbose Logging

```bash
# Enable debug logging
TF_LOG=DEBUG terraform plan ENV=prod
```

### Validate AWS Access

```bash
# Check assumed role
aws sts get-caller-identity

# Check permissions for specific resource
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::account:role/terraform-apply \
  --action-names s3:*
```
