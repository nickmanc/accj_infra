terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.2.0"
    }
  }
  required_version = ">= 0.14.9"
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      CreatedBy = "Terraform"
      Owner     = "Nick"
    }
  }
}

module "website" {
  source     = "../modules/website"
  fqdn       = "${var.SubDomainName}.${var.RootDomainName}"
  bucketName = "${var.SubDomainName}.${var.RootDomainName}"
  region     = var.region
  hostedZone = var.RootDomainName
}

module "pipeline" {
  source                      = "../modules/pipeline"
  fqdn                        = "${var.SubDomainName}.${var.RootDomainName}"
  ContentBucket               = module.website.SiteContentBucket
  GithubCodestarConnectionArn = var.GithubCodestarConnectionArn
  GitHubRepositoryId          = var.GitHubRepositoryId
  region                      = var.region
}