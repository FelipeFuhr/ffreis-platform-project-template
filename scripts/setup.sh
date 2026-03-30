#!/usr/bin/env bash
# Setup script for initializing a new platform project from template

set -euo pipefail

PROJECT_NAME="${1:?Project name required, e.g. my-infra}"
ORG="${2:-ffreis}"
AWS_REGION="${3:-us-east-1}"

echo "═══════════════════════════════════════════════════════"
echo "Platform Project Template Setup"
echo "═══════════════════════════════════════════════════════"
echo "Project:     $PROJECT_NAME"
echo "Org:         $ORG"
echo "Region:      $AWS_REGION"
echo ""

# Validate inputs
if ! command -v terraform &> /dev/null; then
  echo "✗ terraform not found. Please install terraform."
  exit 1
fi

if ! command -v git &> /dev/null; then
  echo "✗ git not found. Please install git."
  exit 1
fi

echo "Step 1: Update configuration files..."

# Update Makefile
sed -i.bak "s/ORG           ?= ffreis/ORG           ?= $ORG/g" Makefile
rm -f Makefile.bak

# Update terraform.tfvars
sed -i.bak "s/project_name = .*/project_name = \"$PROJECT_NAME\"/g" envs/prod/terraform.tfvars
sed -i.bak "s/project_name = .*/project_name = \"$PROJECT_NAME\"/g" envs/staging/terraform.tfvars
rm -f envs/prod/terraform.tfvars.bak envs/staging/terraform.tfvars.bak

# Update backend.hcl paths
sed -i.bak "s|platform-project-template|$PROJECT_NAME|g" envs/prod/backend.hcl
sed -i.bak "s|platform-project-template|$PROJECT_NAME|g" envs/staging/backend.hcl
rm -f envs/prod/backend.hcl.bak envs/staging/backend.hcl.bak

# Update stack naming
sed -i.bak "s|platform-project-template|$PROJECT_NAME|g" infra/stack/main.tf
rm -f infra/stack/main.tf.bak

echo "✓ Configuration updated"

echo ""
echo "Step 2: Verify state backend..."
echo "  Backend S3 bucket: ${ORG}-tf-state"
echo "  DynamoDB lock table: ${ORG}-tf-locks-<env>"
echo "  Please ensure these exist and are accessible."

echo ""
echo "Step 3: Next steps:"
echo "  1. Create GitHub secrets (see README):"
echo "     - TERRAFORM_PLAN_ROLE_ARN"
echo "     - TERRAFORM_APPLY_ROLE_ARN"
echo ""
echo "  2. Test local terraform workflow:"
echo "     make init ENV=staging"
echo "     make plan ENV=staging"
echo ""
echo "  3. Configure Atlantis:"
echo "     - Update terraform registry for this project"
echo "     - Configure VCS repository webhooks"
echo ""
echo "  4. Deploy infrastructure:"
echo "     make validate"
echo "     make plan ENV=prod"
echo ""
echo "✓ Setup complete! Review configuration and commit changes."
