variable "RootDomainName" {
   description = "root domain name for this api"
   type = string
}

variable "region" {
  description = "aws region"
  type = string
}

variable "EmailFromName" {
  description = "name that any emails will be sent from, prepending to the root domain name"
  type = string
}