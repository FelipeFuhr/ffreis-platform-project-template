terraform {
  required_version = ">= 1.9, < 2.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40, < 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5, < 4.0"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  default_tags {
    tags = merge(
      var.tags,
      {
        Project            = var.project_name
        Environment        = var.environment
        ManagedBy          = "terraform"
        Stack              = "platform-project-template"
        TerraformVersion   = "1.9.8"
        CreatedAt          = timestamp()
        CostCenter         = var.cost_center
        Compliance         = var.compliance_framework
        DataClassification = var.data_classification
        BackupPolicy       = var.backup_policy
      }
    )
  }
}

# Common tags reference for resources that need consistent tagging
locals {
  common_tags = merge(
    var.tags,
    {
      Project            = var.project_name
      Environment        = var.environment
      ManagedBy          = "terraform"
      Stack              = "platform-project-template"
      TerraformVersion   = "1.9.8"
      CostCenter         = var.cost_center
      Compliance         = var.compliance_framework
      DataClassification = var.data_classification
      BackupPolicy       = var.backup_policy
    }
  )
}
