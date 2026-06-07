#!/usr/bin/env bash
# Pre-commit hook for terraform formatting validation

set -e

# Find all terraform files
tf_files=$(find . -name "*.tf" -not -path "./.terraform/*" -type f)

if [[ -z "$tf_files" ]]; then
  echo "No terraform files found"
  exit 0
fi

echo "Checking terraform formatting..."

# Check if terraform is available
if ! command -v terraform &> /dev/null; then
  echo "⚠ terraform not found, skipping format check"
  exit 0
fi

# Run format check
if ! terraform fmt -check -recursive . > /dev/null 2>&1; then
  echo "❌ Terraform formatting issues found!"
  echo "Run 'terraform fmt -recursive .' to fix"
  exit 1
fi

echo "✓ Terraform formatting OK"
exit 0
