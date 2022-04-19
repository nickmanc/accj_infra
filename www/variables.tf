variable "RootDomainName" {
  description = "Domain name for website (e.g. acatcalledjack.co.uk)"
  type        = string
}
variable "SubDomainName" {
  description = "Subdomain name for website (e.g. help)"
  type        = string
}

variable "region" {
  description = "This is the cloud hosting region where your webapp will be deployed."
}

variable "GithubCodestarConnectionArn" {
  description = "The ARN of the codestar connection for github account"
}

variable "GitHubRepositoryId" {
  description = "The full repository id of the github respository containing content"
}

variable "NotificationEmail" {
  description = "Email address to notify when content has changed"
}

variable "NotificationSms" {
  description = "Phone number to notify when content has changed"
}