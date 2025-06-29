# Configure Terraform and AWS provider
terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Remote state configuration
  backend "s3" {
    bucket  = "cletus-photo-sharing-tfstate-bucket-2753" # Update this
    key     = "photo-sharing-app/terraform.tfstate"
    region  = "eu-west-1"
    encrypt = true
    # dynamodb_table = "terraform-locks"
  }
}

# Configure the AWS Provider
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# Local values for resource naming
locals {
  resource_prefix = "${var.project_name}-${var.environment}"
  bucket_suffix   = random_string.suffix.result
}