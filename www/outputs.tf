output "SiteContentBucketURL" {
  value       = module.website.SiteContentBucket.bucket
  description = "URL for website hosted on S3"
}

output "UpdateUser" {
  value       = module.website.UpdateUser.name
  description = "User for updating content"
}

output "Password" {
  value       = module.website.UpdateUserPassword
  description = "Password for UpdateUser"
}

output "CloudFrontURL" {
  value       = module.website.distribution.domain_name
  description = "URL for CloudFront Distribution"
}