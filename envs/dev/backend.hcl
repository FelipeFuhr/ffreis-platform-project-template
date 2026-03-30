 # S3 bucket for Terraform state — injected at terraform init.
 # The bucket is shared across environments; the key below provides isolation.
 # Set via: terraform init -backend-config=../envs/dev/backend.hcl
 bucket = "platform-project-template-tfstate-{ACCOUNT_ID}"  # REQUIRED: Replace {ACCOUNT_ID}

 # DynamoDB table for state locking
 dynamodb_table = "terraform-locks"

 # State file key — dev is fully isolated from staging and prod.
 key = "platform-project-template/dev/terraform.tfstate"

 # AWS region
 region = "us-east-1"

 # Enable server-side encryption for state
 encrypt = true
