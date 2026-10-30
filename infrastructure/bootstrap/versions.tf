terraform {
  required_version = "~> 1.16.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.69.0"
    }
  }
}

provider "aws" {
  region              = var.aws_region
  allowed_account_ids = [var.account_id]

  default_tags {
    tags = {
      Project     = "commerce-aws"
      Environment = "bootstrap"
      Owner       = "platform-engineering"
      ManagedBy   = "terraform"
    }
  }
}
