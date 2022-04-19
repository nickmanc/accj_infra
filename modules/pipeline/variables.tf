variable "fqdn" {
  description = "domain name for this distribution"
  type        = string
}

variable "ContentBucket" {
  description = "Bucket containing content, to be updated by the pipeline"
}

variable "GithubCodestarConnectionArn" {
  description = "The ARN of the codestar connection for github account"
  type        = string
}

variable "GitHubRepositoryId" {
  description = "The full repository id of the github respository containing content"
  type        = string
}

variable "region" {
  description = "aws region"
  type        = string
}

variable "NotificationEmail" {
  description = "Email address to notify when content has changed"
}

variable "NotificationSms" {
  description = "Phone number to notify when content has changed"
}