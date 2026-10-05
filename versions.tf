terraform {
  required_version = ">= 1.16.0"
  # backend "s3" {
  #   bucket       = "szino-terraform-state"
  #   key          = "capstone/terraform.tfstate"
  #   region       = "eu-west-1"
  #   use_lockfile = true
  #   encrypt      = true
  # }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}