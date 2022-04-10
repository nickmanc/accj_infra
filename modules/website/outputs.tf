output "distribution" {
  value       = aws_cloudfront_distribution.ContentDistribution
  description = "cloudfront distribution"
}

output "SiteContentBucket" {
  value       = aws_s3_bucket.SiteContentBucket
  description = "bucket for website content"
}

output "SiteContentLoggingBucket" {
  value       = aws_s3_bucket.SiteLoggingBucket
  description = "logging bucket for website"
}

output "UpdateUser" {
  value       = aws_iam_user.SiteContentUpdateUser
  description = "User with permissions to update content bucket"
}

output "UpdateUserPassword" {
  value       = aws_iam_user_login_profile.SiteContentUpdateLoginProfile.password
  description = "Initial password for the update user"
}