variable "fqdn" {
   description = "domain name for this distribution"
   type = string
}

variable "hostedZone" {
  description = "name Route 53 Hosted Zone to use"
  type = string
}

variable "bucketName" {
  description = "Domain name for website (e.g. acatcalledjack.co.uk)"
  type        = string
}

variable "region" {
  description = "aws region"
  type = string
}