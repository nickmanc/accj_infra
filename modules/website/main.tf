provider "aws" {
  region = var.region
  default_tags {
    tags = {
      tfModule = "website"
    }
  }
}

provider "aws" {
  region = "us-east-1"
  alias  = "useast1"
}

resource "aws_s3_bucket" "SiteContentBucket" {
  bucket        = var.bucketName
  force_destroy = true #happy for logs to be destroyed by terraform?
  tags          = {
    Name = "content Bucket"
  }
}
resource "aws_s3_bucket_server_side_encryption_configuration" "SiteContentBucketEncryption" {
  bucket = aws_s3_bucket.SiteContentBucket.bucket

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "SiteContentVersioning" {
  bucket = aws_s3_bucket.SiteContentBucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_logging" "SiteContentBucketLogging" {
  bucket = aws_s3_bucket.SiteContentBucket.bucket

  target_bucket = aws_s3_bucket.SiteLoggingBucket.id
  target_prefix = "log/"
}

resource "aws_s3_bucket_public_access_block" "SiteContentBucketPublicAccessBlock" {
  bucket = aws_s3_bucket.SiteContentBucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket" "SiteLoggingBucket" {

  bucket        = "${var.bucketName}.logging"
  force_destroy = true #happy for logs to be destroyed by terraform?
}

resource "aws_s3_bucket_server_side_encryption_configuration" "SiteLoggingBucketEncryption" {
  bucket = aws_s3_bucket.SiteLoggingBucket.bucket

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "SiteLoggingVersioning" {
  bucket = aws_s3_bucket.SiteLoggingBucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "SiteLoggingBucketPublicAccessBlock" {
  bucket                  = aws_s3_bucket.SiteLoggingBucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "LoggingBucketPolicy" {
  bucket = aws_s3_bucket.SiteLoggingBucket.id
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "AllowSSLRequestsOnly",
        "Action" : "s3:*",
        "Effect" : "Deny",
        "Resource" : [
          aws_s3_bucket.SiteLoggingBucket.arn,
          "${aws_s3_bucket.SiteLoggingBucket.arn}/*"
        ],
        "Condition" : {
          "Bool" : {
            "aws:SecureTransport" : "false"
          }
        },
        "Principal" : "*"
      }
    ]
  })
}

resource "aws_s3_bucket_lifecycle_configuration" "SiteLoggingBucketLifecycleConfiguration" {
  bucket = aws_s3_bucket.SiteLoggingBucket.bucket
  rule {
    id = "DeleteOldLogs"
    expiration {
      days = 28
    }
    filter {
      prefix = "${var.bucketName}.log"
    }
    status = "Enabled"
  }
}


resource "aws_iam_group" "SiteContentUpdateGroup" {
  name = "${var.bucketName}_update_group"
}

resource "aws_iam_group_policy_attachment" "SiteContentUpdateGroupChangePasswordPolicyAttachment" {
  group      = aws_iam_group.SiteContentUpdateGroup.name
  policy_arn = "arn:aws:iam::aws:policy/IAMUserChangePassword"
}

resource "aws_iam_group_policy" "SiteContentUpdateGroupPolicy" {
  name   = "${var.bucketName}_update_group_policy"
  group  = aws_iam_group.SiteContentUpdateGroup.name
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Action" : [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObjectVersion",
          "s3:ListBucketVersions",
          "s3:ListBucket",
          "s3:GetBucketVersioning",
          "s3:DeleteObject",
          "s3:GetObjectVersion"
        ],
        "Resource" : [
          "arn:aws:s3:::${var.bucketName}/*",
          "arn:aws:s3:::${var.bucketName}"
        ],
        "Effect" : "Allow"
      },
      {
        "Action" : [
          "s3:ListAllMyBuckets"
        ],
        "Resource" : "*",
        "Effect" : "Allow"
      }
    ]
  })
}

resource "aws_iam_user" "SiteContentUpdateUser" {
  name = "${var.bucketName}_update_user"
}

resource "aws_iam_user_group_membership" "SiteContentUpdateUserGroup" {
  user   = aws_iam_user.SiteContentUpdateUser.name
  groups = [
    aws_iam_group.SiteContentUpdateGroup.name
  ]
}

resource "aws_iam_user_login_profile" "SiteContentUpdateLoginProfile" {
  user                    = aws_iam_user.SiteContentUpdateUser.name
  password_reset_required = true
  password_length         = 14
}

resource "aws_cloudfront_origin_access_identity" "ContentCloudFrontOriginAccessIdentity" {
  comment = "Origin Access Identity for site"
}

resource "aws_cloudfront_distribution" "ContentDistribution" {
  origin {
    domain_name = "${var.fqdn}.s3.eu-west-2.amazonaws.com" #TODO should use current region?
    origin_id   = "SiteContentBucketOrigin"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.ContentCloudFrontOriginAccessIdentity.cloudfront_access_identity_path
    }
  }
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  enabled             = true
  comment             = "CloudFront distribution for ${var.fqdn}"
  http_version        = "http2"
  default_root_object = "index.html"
  logging_config {
    bucket          = aws_s3_bucket.SiteLoggingBucket.bucket_regional_domain_name
    prefix          = "cf.${var.fqdn}.log"
    include_cookies = "false"
  }
  aliases = [var.fqdn]
  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "SiteContentBucketOrigin"
    viewer_protocol_policy = "redirect-to-https"
    cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6" #Managed-CachingOptimized
    function_association {
      event_type   = "viewer-response"
      function_arn = aws_cloudfront_function.AddContentSecurityHeadersFunction.arn
    }
  }
  price_class = "PriceClass_100" #US-EUROPE (cheapest)
  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.wildcard_certificate.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
  custom_error_response {
    error_code            = 403
    error_caching_min_ttl = 10
    response_code         = 404
    response_page_path    = "/404.html"
  }
}

resource "aws_cloudfront_function" "AddContentSecurityHeadersFunction" {
  name    = "AddContentSecurityHeadersFunction_${replace(var.fqdn,".","_")}"
  runtime = "cloudfront-js-1.0"
  comment = "Adds security headers to responses"
  publish = true
  code    = file("${path.module}/code/AddContentSecurityHeadersFunction.js")
}

data "archive_file" "InvalidateCloudFrontDistributionLambdaZip" {
  type        = "zip"
  source {
    content  = templatefile("${path.module}/code/InvalidateCloudFrontDistributionLambdaTemplate.js",
      { distributionId = aws_cloudfront_distribution.ContentDistribution.id } )
    filename = "InvalidateCloudFrontDistributionLambda.js"
  }
  output_path = "InvalidateCloudFrontDistributionLambda.zip"
}

resource "aws_lambda_function" "InvalidateCloudFrontDistributionLambda" {
  function_name    = "${replace(var.fqdn,".","_")}_invalidate_cf_distribution"
  role             = aws_iam_role.InvalidateCloudFrontDistributionRole.arn
  filename         = data.archive_file.InvalidateCloudFrontDistributionLambdaZip.output_path
  source_code_hash = filebase64sha256(data.archive_file.InvalidateCloudFrontDistributionLambdaZip.output_path)
  handler          = "InvalidateCloudFrontDistributionLambda.handler"
  runtime          = "nodejs14.x"
  publish          = "true"
}

data "aws_caller_identity" "current" {}

resource "aws_iam_role" "InvalidateCloudFrontDistributionRole" {
  name               = "${replace(var.fqdn,".","_")}_invalidate_cf_distributiontes_role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
  inline_policy {
    name   = "help_invalidate_distribution_policy"
    policy = jsonencode({
      Version   = "2012-10-17"
      Statement = [
        {
          Action    = "cloudfront:CreateInvalidation"
          Condition = {
            StringEqualsIfExists = {
              "aws:SourceAccount" : data.aws_caller_identity.current.account_id
            }
          }
          Effect   = "Allow"
          Resource = "arn:aws:cloudfront::${data.aws_caller_identity.current.account_id}:distribution/${aws_cloudfront_distribution.ContentDistribution.id}"
        }
      ]
    })
  }
}

resource "aws_lambda_permission" "aws_permission" {
  statement_id   = "AllowExecutionFromS3Bucket"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.InvalidateCloudFrontDistributionLambda.arn
  principal      = "s3.amazonaws.com"
  source_arn     = aws_s3_bucket.SiteContentBucket.arn
  source_account = data.aws_caller_identity.current.account_id
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket     = aws_s3_bucket.SiteContentBucket.id
  depends_on = [aws_iam_role.InvalidateCloudFrontDistributionRole, aws_lambda_function.InvalidateCloudFrontDistributionLambda]
  //seems to be tf bug: https://stackoverflow.com/questions/67010382/terraform-error-putting-s3-notification-configuration-invalidargument-unable
  lambda_function {
    id                  = "SiteContentChangedEvent"
    lambda_function_arn = aws_lambda_function.InvalidateCloudFrontDistributionLambda.arn
    events              = [
      "s3:ObjectCreated:*",
      "s3:ObjectRemoved:*",
      "s3:ObjectRestore:*"
    ]
  }
}


resource "aws_s3_bucket_policy" "ContentBucketPolicy" {
  bucket = aws_s3_bucket.SiteContentBucket.bucket
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "AllowSSLRequestsOnly",
        "Action" : "s3:*",
        "Effect" : "Deny",
        "Resource" : [
          aws_s3_bucket.SiteContentBucket.arn,
          "${aws_s3_bucket.SiteContentBucket.arn}/*"
        ],
        "Condition" : {
          "Bool" : {
            "aws:SecureTransport" : "false"
          }
        },
        "Principal" : "*"
      },
      {
        "Effect" : "Allow",
        "Principal" : {
          "AWS" : aws_cloudfront_origin_access_identity.ContentCloudFrontOriginAccessIdentity.iam_arn
        },
        "Action" : "s3:GetObject",
        "Resource" : "${aws_s3_bucket.SiteContentBucket.arn}/*"
      }
    ]
  })
}


resource "aws_route53_record" "DNSRecord" {
  zone_id = data.aws_route53_zone.route53_hosted_zone.zone_id
  name    = var.fqdn
  type    = "CNAME"
  ttl     = "300"
  records = [aws_cloudfront_distribution.ContentDistribution.domain_name]
}

resource "aws_acm_certificate" "wildcard_certificate" {
  provider          = aws.useast1 //certificate has to be from us-east-1 for CloudFront
  domain_name       = var.fqdn
  validation_method = "DNS"
  # (resource arguments)
}

data "aws_route53_zone" "route53_hosted_zone" {
  name         = var.hostedZone
  private_zone = false
}

resource "aws_route53_record" "route53_record" {
  for_each = {
  for dvo in aws_acm_certificate.wildcard_certificate.domain_validation_options : dvo.domain_name => {
    name   = dvo.resource_record_name
    record = dvo.resource_record_value
    type   = dvo.resource_record_type
  }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.route53_hosted_zone.zone_id
}

resource "aws_acm_certificate_validation" "certificate_validation" {
  provider                = aws.useast1 //certificate has to be from us-east-1 for CloudFront
  certificate_arn         = aws_acm_certificate.wildcard_certificate.arn
  validation_record_fqdns = [for record in aws_route53_record.route53_record : record.fqdn]
}
