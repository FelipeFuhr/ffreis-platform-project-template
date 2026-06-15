# Website Project Template

<!-- ffreis-badges:start -->
[![CI](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/FelipeFuhr/ffreis-badges/main/badges/ffreis-platform-project-template/ci.json)](https://github.com/FelipeFuhr/ffreis-platform-project-template/actions) [![License](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/FelipeFuhr/ffreis-badges/main/badges/ffreis-platform-project-template/license.json)](https://github.com/FelipeFuhr/ffreis-platform-project-template/blob/main/LICENSE)
<!-- ffreis-badges:end -->

This repository is being repositioned into a public-safe website project template.

The target shape is intentionally close to the Flemming website delivery model:

- a website source tree under `src/`
- contract-based site data under `src/data/`
- static build and validation checks driven by a website compiler
- self-contained GitHub workflows for CI, hygiene, and deployment
- optional private infrastructure adapters kept outside the public template

## Template Boundary

This template is for the public website repository only.

Included in the public template:

- `src/` website source layout
- `src/data/site.yaml` and `src/data/site.contract.yaml`
- quality checks for formatting, JavaScript syntax, contract validation, and asset validation
- deploy examples using standard GitHub Actions, OIDC, S3, and CloudFront inputs
- public-safe repository hygiene such as `lefthook`, `renovate`, and `sonar-project.properties`

Excluded from the public template baseline:

- private bootstrap or shared-infra tooling
- org-specific reusable workflow repositories
- private bucket names, account IDs, or role names
- shared access-log buckets or shared Lambda artifact contracts
- domain-specific backend or Lambda implementations

Private infrastructure should be layered on top through a separate repo or internal adapter docs.

## Current Migration Status

The visible entry points in this repo are now website-oriented. Some legacy infrastructure scaffolding still exists in the repository while the migration is in progress, but it is not part of the intended public template surface.

## Project Structure

```text
.
├── src/
│   ├── assets/               # CSS, JS, images, fonts, static assets
│   ├── data/
│   │   ├── site.yaml         # Stable global site settings
│   │   ├── site.contract.yaml# Required and allowed data keys
│   │   └── site.d/           # Layered site-data overlays
│   └── templates/
│       ├── layout/           # Base layouts
│       ├── partials/         # Shared page fragments
│       └── pages/            # Route-level pages
├── sanity/                   # Optional sanity-check inputs or fixtures
├── dist/                     # Generated output (ignored)
├── .github/workflows/        # Public-safe CI and deploy workflows
├── Makefile                  # Local build and validation targets
├── lefthook.yml              # Single entrypoint for CI checks
├── sitemap.yaml              # Optional route metadata for builds/deploys
└── README.md
```

## Expected Tooling

This template assumes a compatible website compiler exists, but does not hardcode a private repository.

The compiler path is configured through:

- `WEBSITE_COMPILER`
- `WEBSITE_COMPILER_CLI`
- `WEBSITE_COMPILER_REPO` in GitHub repository variables for CI

That keeps the template generic while preserving the Flemming-style contract/build flow.

## Local Usage

Run the standard checks:

```bash
make format-check
make js-syntax
make site-data-check
make asset-usage-check
make template-compile-check
make build-static-check
make build-inline-check
```

Or run the full local quality bundle:

```bash
make check
```

## GitHub Configuration

Repository variables:

- `WEBSITE_COMPILER_REPO` — compiler repository to checkout in CI
- `AWS_REGION` — deploy region, defaults to `us-east-1` if omitted

Repository secrets:

- `AWS_DEPLOY_ROLE_ARN` — OIDC deploy role
- `S3_WEBSITE_BUCKET` — destination website bucket
- `CF_DISTRIBUTION_ID` — CloudFront distribution to invalidate
- `CI_REPO_READ_TOKEN` — optional token if the compiler repo is private

## Private Infra Integration

If you pair this public template with a private infrastructure repo, keep that integration outside the template code.

Recommended contract:

1. the private infra repo creates the deployment role, website bucket, and CDN distribution
2. those outputs are copied into repository variables and secrets
3. the public website repo remains generic and reusable

## Related Repos

- Flemming website repo shape is the reference for this template
- The ffreis website should later converge on the same public-safe structure

## Next Migration Steps

- remove the remaining legacy infra scaffold from this repo or move it to an internal template
- publish a companion private integration guide for teams using shared infrastructure
- align the ffreis website repo to the same public-safe website shape

Create reusable components:

```bash
mkdir -p modules/my-module
cd modules/my-module

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

Update `stack/main.tf`:

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
