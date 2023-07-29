terraform {
    backend "s3" {
        # Written in ./config.tfbackend
    }
}
provider "aws" {
    # Region
    region = var.region
    # Common Tags
    default_tags {
        tags = {
            "Project"     = var.project
            "Environment" = var.environment
        }
    }
}