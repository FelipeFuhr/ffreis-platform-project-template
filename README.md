# Platform Project Template

A comprehensive, production-ready Terraform project template with multi-environment support, OIDC-based GitHub Actions CI/CD, Atlantis integration, and DynamoDB lock management.

## Features

✨ **Core Infrastructure**
- Multi-environment support (prod, staging, dev)
- Remote S3 state management with DynamoDB locks
- OIDC-based GitHub Actions (no static credentials)
- Comprehensive Terraform workflows

🔐 **Security & Governance**
- GitHub Actions OIDC integration with AWS STS
- Temporary session credentials (no long-lived keys)
- Infrastructure linting (TFLint, tfsec, Checkov)
- SARIF security scanning results

🚀 **Deployment & Operations**
- Atlantis-ready configuration for PR-based planning/applying
- Manual apply workflow for controlled deployments
- Destroy workflow with confirmation gates
- Lock management utilities via `dynamoctl`

## Quick Start

### 1. Clone and Customize

```bash
# Clone this template
cp -r platform-project-template my-project
cd my-project

# Run setup script
bash scripts/setup.sh my-project ffreis us-east-1
```

### 2. Prerequisites

Ensure you have these tools installed:

```bash
# Terraform
brew install terraform  # or download from terraform.io

# AWS CLI (for deployment workflows)
brew install awscli

# Optional but recommended
brew install tflint
brew install terraform-docs
```

### 3. AWS Backend Setup

The template requires pre-existing S3 and DynamoDB resources:

```bash
# These must be created once per AWS account
# Use platform-bootstrap or your standard provisioning process:

# S3 bucket for terraform state
aws s3api create-bucket \
  --bucket ffreis-tf-state \
  --region us-east-1

# DynamoDB table for state locks (per environment)
aws dynamodb create-table \
  --table-name ffreis-tf-locks-prod \
  --attribute-definitions AttributeName=ID,AttributeType=S \
  --key-schema AttributeName=ID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

### 4. GitHub Configuration

#### Create IAM Roles for OIDC

Assuming you've set up GitHub OIDC trust principal via `platform-github-oidc`:

```bash
# Create terraform-specific roles with appropriate permissions
# These roles should have trust policy allowing:
# - principal: arn:aws:iam::<account>:oidc-provider/token.actions.githubusercontent.com
# - subjects: repo:owner/repo:*
```

#### Add GitHub Secrets

In your GitHub repository, add these secrets:

```
TERRAFORM_PLAN_ROLE_ARN
  - Role ARN for plan-only operations (read-only or reduced permissions)

TERRAFORM_APPLY_ROLE_ARN
  - Role ARN for apply operations (full terraform permissions)
  
AWS_ACCOUNT_ID
  - Your AWS account ID (used in workflows)
```

## Project Structure

```
.
├── infra/
│   ├── stack/               # Main terraform configuration
│   │   ├── main.tf         # Provider configuration
│   │   ├── backend.tf      # Remote state configuration
│   │   ├── variables.tf    # Input variables
│   │   └── outputs.tf      # Output values
│   └── modules/            # Reusable terraform modules
├── envs/
│   ├── prod/               # Production environment config
│   │   ├── backend.hcl     # S3 key and DynamoDB table per env
│   │   └── terraform.tfvars
│   └── staging/            # Staging environment config
├── .github/workflows/      # GitHub Actions pipelines
│   ├── terraform-plan.yml
│   ├── terraform-apply.yml
│   ├── terraform-destroy.yml
│   └── lint-security.yml
├── scripts/                # Utility scripts
│   ├── setup.sh
│   └── manage-locks.sh
├── atlantis.yaml          # Atlantis PR automation config
├── Makefile               # Local development targets
└── README.md

## 📚 Documentation

- **[SETUP.md](./SETUP.md)** – Pre-deployment setup guide (S3 bucket, backend, OIDC, GitHub secrets)
- **[VALIDATION.md](./VALIDATION.md)** – Post-deployment validation checklist and verification results
- **[CONTRIBUTING.md](./CONTRIBUTING.md)** – Development standards, PR guidelines, and contribution workflow
- **[EXAMPLES.md](./EXAMPLES.md)** – Resource patterns, best practices, and code examples
 
## Additional Information
For more details, refer to the respective documentation files.
```

## Usage

### Local Development

Format and validate:

```bash
make fmt           # Format all terraform files
make fmt-check     # Verify formatting
make validate      # Validate terraform syntax
make check         # Run all checks
```

Plan changes for staging:

```bash
make init ENV=staging
make plan ENV=staging
```

### State & Lock Management

View locks in DynamoDB:

```bash
make lock-list ENV=prod      # List all locks
make lock-info ENV=prod      # Show table stats
make lock-cleanup ENV=prod   # Remove stale locks (manual confirmation)
```

Or use the utility script:

```bash
bash scripts/manage-locks.sh list prod
bash scripts/manage-locks.sh info prod
bash scripts/manage-locks.sh cleanup prod
```

### GitHub Actions Workflows

**terraform-plan.yml** (on pull requests)
- Runs on PR creation/update
- Tests formatting, validation, and planning
- Posts plan diff to PR for review

**terraform-apply.yml** (on main branch)
- Detects which environments changed
- Applies staging before prod (sequential via concurrency)
- Creates deployment records in GitHub

**terraform-destroy.yml** (manual)
- Triggered manually via GitHub UI
- Requires explicit confirmation (`DESTROY` text)
- Suitable for cleanup in dev/staging environments

**lint-security.yml** (on pull requests)
- TFLint: Best practices and style
- tfsec: Security issue detection
- Checkov: Policy compliance scanning

### Atlantis Integration

Atlantis enables PR-based infrastructure changes:

1. **Install Atlantis** on your infrastructure
2. **Configure VCS webhook** to your Atlantis instance
3. **Comment on PRs** to trigger plans/applies:
   ```
   atlantis plan -d infra/stack -w staging
   atlantis apply -d infra/stack -w staging
   ```

The workflow in `atlantis.yaml` automatically:
- Fetches dynamic config from `platform-bootstrap`
- Initializes terraform with environment-specific backend
- Plans and applies changes

## Environment-Specific Configuration

Each environment has its own configuration:

### Backend Configuration (`envs/<env>/backend.hcl`)

```hcl
# Specifies where state is stored
key = "platform-project-template/prod/terraform.tfstate"
```

Customize for your organization and state bucket.

### Terraform Variables (`envs/<env>/terraform.tfvars`)

```hcl
project_name = "platform-project"
environment  = "prod"
aws_region   = "us-east-1"

# Add your environment-specific variables
# Example:
# vpc_cidr = "10.0.0.0/16"
```

## Adding Resources

1. **Add terraform code** to `infra/stack/*.tf` or appropriate module
2. **Format and validate**:
   ```bash
   make fmt-check
   make validate
   ```
3. **Test locally**:
   ```bash
   make plan ENV=staging
   ```
4. **Create PR and let GitHub Actions test**
5. **Merge and apply via GitHub Actions or Atlantis**

## Adding Modules

Create reusable components:

```bash
mkdir -p infra/modules/my-module
cd infra/modules/my-module

# Create module files
cat > main.tf << 'EOF'
resource "aws_example" "this" {
  # resource configuration
}
EOF

cat > variables.tf << 'EOF'
variable "name" {
  description = "Resource name"
  type        = string
}
EOF

cat > outputs.tf << 'EOF'
output "arn" {
  value = aws_example.this.arn
}
EOF
```

Use in stack:

```hcl
module "my_module" {
  source = "../modules/my-module"
  name   = var.project_name
}
```

## Security Considerations

### GitHub Actions OIDC

This template uses **OIDC for temporary credentials** instead of static AWS access keys:

- GitHub Actions generates a time-limited JWT token
- AWS STS exchanges the JWT for temporary credentials
- Credentials are session-scoped and auto-expire
- No static credentials stored in GitHub Secrets

Benefits:
- ✅ No long-lived credentials to compromise
- ✅ Automatic audit trail via CloudTrail
- ✅ Granular permissions via trust policy
- ✅ Works across AWS accounts

### DynamoDB Lock Management

Terraform locks prevent concurrent applies:

- **Automatic**: `terraform` command handles locking
- **Manual cleanup**: `make lock-cleanup` removes stale locks
- **Monitoring**: `make lock-info` shows table status

### Least Privilege Roles

Create separate roles for different workflows:

```json
{
  "TERRAFORM_PLAN_ROLE": {
    "permissions": [
      "s3:GetObject",
      "dynamodb:PutItem",
      "terraform:*"
    ],
    "denied": [
      "iam:*",
      "organizations:*",
      "ec2:TerminateInstances"
    ]
  },
  "TERRAFORM_APPLY_ROLE": {
    "permissions": [
      "All admin access (limited to non-sensitive services)"
    ]
  }
}
```

## Troubleshooting

### "Backend not initialized"

```bash
make init ENV=prod
```

### "State lock timeout"

```bash
# View locks
make lock-list ENV=prod

# Remove stale lock (if certain it's safe)
make lock-cleanup ENV=prod
```

### "No such file or directory: backend.hcl"

Ensure environment exists:

```bash
ls -la envs/
# Should show prod/, staging/
```

### "OIDC credentials not valid"

1. Verify GitHub Actions role exists in AWS
2. Check trust policy includes your GitHub org/repo
3. Verify AWS_ACCOUNT_ID secret is set
4. Review CloudTrail for detailed error

## Best Practices

📋 **Before Applying**
- Review plan output carefully
- Get approval from team members
- Test in staging environment first
- Ensure no concurrent changes in progress

🔄 **Ongoing Operations**
- Monitor terraform lock table for stale locks
- Keep terraform and providers updated
- Document all resource design decisions
- Use descriptive commit messages

🛡️ **Security**
- Review IAM policies regularly
- Rotate GitHub OIDC thumbprints yearly
- Monitor CloudTrail for unauthorized access
- Use separate roles for plan vs. apply

## Integration with platform-bootstrap

This template integrates with `platform-bootstrap` for:

- **Configuration Discovery**: Fetch org/account metadata
- **Dynamic Variables**: Auto-generate environment-specific values
- **Consistency**: Ensure cross-project alignment

Example Atlantis workflow step:

```bash
platform-bootstrap fetch --org ffreis --output ../envs/prod/fetched.auto.tfvars.json
```

## Integration with dynamoctl

For lock management and secrets storage:

```bash
# List available locks
dynamoctl list --table ffreis-tf-locks-prod

# View lock details
dynamoctl get --table ffreis-tf-locks-prod --key <lock-id>

# Store encrypted secrets
dynamoctl set --table secrets --key api_key --value "secret123" --encryption-key "..."
```

## Customization Guide

### For Different AWS Regions

Update `envs/<env>/terraform.tfvars`:

```hcl
aws_region = "eu-west-1"  # Change region
```

### For Custom Tags

Update `infra/stack/main.tf`:

```hcl
default_tags {
  tags = merge(
    var.tags,
    {
      CostCenter = "engineering"
      Owner = "platform-team"
    }
  )
}
```

### For Multiple AWS Accounts

Add account management module:

```hcl
module "cross_account" {
  source = "../modules/cross-account-iam"
  
  principal_account_id = var.principal_account_id
  role_name = "infrastructure-deployer"
}
```

## Support & Documentation

- [Terraform Docs](https://www.terraform.io/docs)
- [AWS Terraform Provider](https://registry.terraform.io/providers/hashicorp/aws/latest)
- [Atlantis Documentation](https://www.runatlantis.io/)
- [GitHub Actions OIDC](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect)

## License

This template is provided as part of the ffreis platform-* projects.

---

**Last Updated**: March 2026  
**Template Version**: 1.0  
**Terraform Version**: >= 1.9
