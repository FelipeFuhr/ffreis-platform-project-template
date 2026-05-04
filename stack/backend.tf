terraform {
  backend "s3" {
    # Bucket and DynamoDB table configured per-environment via backend.hcl
    # Initialize with:
    #   terraform init -backend-config=../../envs/<env>/backend.hcl
    region  = "us-east-1"
    encrypt = true
  }
}
