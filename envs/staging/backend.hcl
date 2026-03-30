 # S3 bucket for Terraform state (create during setup)
 # Run: aws s3api create-bucket --bucket <bucket-name> --region us-east-1
 bucket = "platform-project-template-tfstate-{ACCOUNT_ID}"  # REQUIRED: Replace {ACCOUNT_ID}

 # DynamoDB table for state locking (create during setup)
 # Run: aws dynamodb create-table --table-name terraform-locks --attribute-definitions ... 
 dynamodb_table = "terraform-locks"

 # State file key path (per environment)
 key = "platform-project-template/staging/terraform.tfstate"

 # AWS region
 region = "us-east-1"

 # Enable server-side encryption for state
 encrypt = true
