provider "aws" {
  region = var.region
  default_tags {
    tags = {
      tfModule = "api"
    }
  }
}

provider "aws" {
  region = "us-east-1"
  alias  = "useast1"
}

data "aws_caller_identity" "current" {}

###########################################################################
# DYNAMO DB
###########################################################################
resource "aws_dynamodb_table" "subscriptions" {
  name           = "subscriptions"
  billing_mode   = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 5
  hash_key       = "email"

  attribute {
    name = "email"
    type = "S"
  }
}

###########################################################################
# SUBSCRIPTION API
###########################################################################
resource "aws_api_gateway_rest_api" "subscription_api" {
  name = "Subscription"
}

resource "aws_api_gateway_deployment" "test" {
  rest_api_id = aws_api_gateway_rest_api.subscription_api.id

  triggers = {
    redeployment = sha1(jsonencode([
      md5(file("../modules/api/code/Subscribe.js")),#assumes this module is being run from directory above modules
      md5(file("../modules/api/code/Unsubscribe.js")),#assumes this module is being run from directory above modules
      md5(file("../modules/api/code/Verify.js")),#assumes this module is being run from directory above modules
      md5(file("../modules/api/main.tf"))#assumes this module is being run from directory above modules
    ]))
  }
  lifecycle {
    create_before_destroy = true
  }
  stage_description = sha256(file("../modules/api/main.tf"))#assumes this module is being run from directory above modules
}

resource "aws_api_gateway_stage" "test" {
  deployment_id      = aws_api_gateway_deployment.test.id
  rest_api_id        = aws_api_gateway_rest_api.subscription_api.id
  cache_cluster_size = "0.5"
  stage_name         = "test"
}

resource "aws_api_gateway_resource" "subscription_resource" {
  rest_api_id = aws_api_gateway_rest_api.subscription_api.id
  parent_id   = aws_api_gateway_rest_api.subscription_api.root_resource_id
  path_part   = "subscriptionmanager"
}

resource "aws_api_gateway_model" "html_model" {
  rest_api_id  = aws_api_gateway_rest_api.subscription_api.id
  name         = "html"
  content_type = "text/html"

  schema = <<EOF
{
  "type": "object"
}
EOF
}

resource "aws_api_gateway_resource" "verify_resource" {
  rest_api_id = aws_api_gateway_rest_api.subscription_api.id
  parent_id   = aws_api_gateway_resource.subscription_resource.id
  path_part   = "verify"
}

resource "aws_api_gateway_request_validator" "parameter_validator" {
  name                        = "parameter_validator"
  rest_api_id                 = aws_api_gateway_rest_api.subscription_api.id
  validate_request_parameters = true
}

resource "aws_api_gateway_method" "verify_get" {
  rest_api_id        = aws_api_gateway_rest_api.subscription_api.id
  resource_id        = aws_api_gateway_resource.verify_resource.id
  request_parameters = {
    "method.request.querystring.email" = true
    "method.request.querystring.id"    = true
  }
  request_validator_id = aws_api_gateway_request_validator.parameter_validator.id
  http_method          = "GET"
  authorization        = "NONE"
}

resource "aws_api_gateway_integration" "verify_get_integration" {
  rest_api_id             = aws_api_gateway_rest_api.subscription_api.id
  resource_id             = aws_api_gateway_resource.verify_resource.id
  http_method             = aws_api_gateway_method.verify_get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  content_handling        = "CONVERT_TO_TEXT"
  uri                     = aws_lambda_function.VerifyLambda.invoke_arn
}
resource "aws_api_gateway_integration_response" "verify_get_integration_response" {
  depends_on          = [aws_api_gateway_integration.subscription_options_integration]
  http_method         = "GET"
  resource_id         = aws_api_gateway_resource.verify_resource.id
  response_parameters = {}
  response_templates  = { "application/json" : "" }
  rest_api_id         = aws_api_gateway_rest_api.subscription_api.id
  status_code         = "200"
}
resource "aws_lambda_permission" "verify_lambda_permission" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.VerifyLambda.function_name
  principal     = "apigateway.amazonaws.com"
  # More: http://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-control-access-using-iam-policies-to-invoke-api.html
  source_arn    = "arn:aws:execute-api:${var.region}:${data.aws_caller_identity.current.account_id}:${aws_api_gateway_rest_api.subscription_api.id}/*/${aws_api_gateway_method.verify_get.http_method}${aws_api_gateway_resource.verify_resource.path}"
}

###########################################################################
# LAMBDAS
###########################################################################
data "archive_file" "SubscribeLambdaZip" {
  type = "zip"
  source {
    content = templatefile("${path.module}/code/Subscribe.js",
      {
        tableName                  = aws_dynamodb_table.subscriptions.name,
        new_subscription_queue_url = aws_sqs_queue.new_subscription_queue.url,
        email_template_name        = aws_ses_template.verification_email_template.name
        api_address                = aws_api_gateway_domain_name.custom_api_domain_name.domain_name
        verify_resource            = aws_api_gateway_resource.verify_resource.path
        unsubscribe_resource       = aws_api_gateway_resource.unsubscribe_resource.path
        email_from                 = var.EmailFromName
        root_domain_name           = var.RootDomainName
      } )
    filename = "SubscribeLambda.js"
  }
  output_path = "Subscribe.zip"
}

resource "aws_lambda_function" "SubscribeLambda" {
  function_name    = "Subscribe"
  role             = aws_iam_role.SubscribeRole.arn
  filename         = data.archive_file.SubscribeLambdaZip.output_path
  source_code_hash = filebase64sha256(data.archive_file.SubscribeLambdaZip.output_path)
  handler          = "SubscribeLambda.handler"
  runtime          = "nodejs14.x"
  publish          = "true"
}

resource "aws_iam_role" "SubscribeRole" {
  name               = "subscribe_role"
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
    name   = "subscribe_policy"
    policy = jsonencode({
      Version   = "2012-10-17"
      Statement = [
        {
          Action = [
            "dynamodb:PutItem",
            "dynamodb:GetItem",
          ]
          Condition = {
            StringEqualsIfExists = {
              "aws:SourceAccount" : data.aws_caller_identity.current.account_id
            }
          }
          Effect   = "Allow"
          Resource = aws_dynamodb_table.subscriptions.arn
        },
        {
          "Effect" : "Allow",
          "Action" : [
            "logs:CreateLogGroup",
            "logs:CreateLogStream",
            "logs:PutLogEvents"
          ],
          "Resource" : "*"
        },
        {
          "Effect" : "Allow",
          "Action" : "sqs:SendMessage",
          "Resource" : aws_sqs_queue.new_subscription_queue.arn
        },
        {
          "Effect" : "Allow",
          "Action" : ["ses:SendEmail", "ses:SendTemplatedEmail"]
          "Resource" : "*"
        }
      ]
    })
  }
}

data "archive_file" "UnsubscribeLambdaZip" {
  type = "zip"
  source {
    content = templatefile("${path.module}/code/Unsubscribe.js",
      {
        tableName        = aws_dynamodb_table.subscriptions.name,
        root_domain_name = var.RootDomainName
      } )
    filename = "UnsubscribeLambda.js"
  }
  output_path = "Unsubscribe.zip"
}

resource "aws_lambda_function" "UnsubscribeLambda" {
  function_name    = "Unsubscribe"
  role             = aws_iam_role.UnsubscribeRole.arn
  filename         = data.archive_file.UnsubscribeLambdaZip.output_path
  source_code_hash = filebase64sha256(data.archive_file.UnsubscribeLambdaZip.output_path)
  handler          = "UnsubscribeLambda.handler"
  runtime          = "nodejs14.x"
  publish          = "true"
}

resource "aws_iam_role" "UnsubscribeRole" {
  name               = "unsubscribe_role"
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
    name   = "unsubscribe_policy"
    policy = jsonencode({
      Version   = "2012-10-17"
      Statement = [
        {
          Action = [
            "dynamodb:DeleteItem",
            "dynamodb:GetItem"
          ]
          Condition = {
            StringEqualsIfExists = {
              "aws:SourceAccount" : data.aws_caller_identity.current.account_id
            }
          }
          Effect   = "Allow"
          Resource = aws_dynamodb_table.subscriptions.arn
        },
        {
          "Effect" : "Allow",
          "Action" : [
            "logs:CreateLogGroup",
            "logs:CreateLogStream",
            "logs:PutLogEvents"
          ],
          "Resource" : "*"
        }
      ]
    })
  }
}

data "archive_file" "VerifyLambdaZip" {
  type = "zip"
  source {
    content = templatefile("${path.module}/code/Verify.js",
      {
        tableName        = aws_dynamodb_table.subscriptions.name,
        root_domain_name = var.RootDomainName,
        api_address                = aws_api_gateway_domain_name.custom_api_domain_name.domain_name,
        unsubscribe_resource       = aws_api_gateway_resource.unsubscribe_resource.path
      } )
    filename = "VerifyLambda.js"
  }
  output_path = "Verify.zip"
}

resource "aws_lambda_function" "VerifyLambda" {
  function_name    = "Verify"
  role             = aws_iam_role.VerifyRole.arn
  filename         = data.archive_file.VerifyLambdaZip.output_path
  source_code_hash = filebase64sha256(data.archive_file.VerifyLambdaZip.output_path)
  handler          = "VerifyLambda.handler"
  runtime          = "nodejs14.x"
  publish          = "true"
}

resource "aws_iam_role" "VerifyRole" {
  name               = "verify_role"
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
    name   = "verify_policy"
    policy = jsonencode({
      Version   = "2012-10-17"
      Statement = [
        {
          Action = [
            "dynamodb:UpdateItem"
          ]
          Condition = {
            StringEqualsIfExists = {
              "aws:SourceAccount" : data.aws_caller_identity.current.account_id
            }
          }
          Effect   = "Allow"
          Resource = aws_dynamodb_table.subscriptions.arn
        },
        {
          "Effect" : "Allow",
          "Action" : [
            "logs:CreateLogGroup",
            "logs:CreateLogStream",
            "logs:PutLogEvents"
          ],
          "Resource" : "*"
        }
      ]
    })
  }
}

############################################################################
## POST  /  SUBSCRIBE
############################################################################
#resource "aws_api_gateway_method" "subscription_post" {
#  rest_api_id   = aws_api_gateway_rest_api.subscription_api.id
#  resource_id   = aws_api_gateway_resource.subscription_resource.id
#  http_method   = "POST"
#  authorization = "NONE"
#}
#
#resource "aws_api_gateway_method_response" "subscription_post_response" {
#  http_method     = "POST"
#  resource_id     = aws_api_gateway_resource.subscription_resource.id
#  response_models = {
#    "application/json" = "Empty"
#  }
#  response_parameters = {
#    "method.response.header.Access-Control-Allow-Origin" = false
#  }
#  rest_api_id = aws_api_gateway_rest_api.subscription_api.id
#  status_code = "200"
#}
#
#resource "aws_api_gateway_integration" "subscription_post_integration" {
#  rest_api_id             = aws_api_gateway_rest_api.subscription_api.id
#  resource_id             = aws_api_gateway_resource.subscription_resource.id
#  http_method             = aws_api_gateway_method.subscription_post.http_method
#  integration_http_method = "POST"
#  type                    = "AWS"
#  uri                     = aws_lambda_function.SubscribeLambda.invoke_arn
#}
#
#resource "aws_api_gateway_integration_response" "subscription_post_integration_response" {
#  depends_on          = [aws_api_gateway_integration.subscription_options_integration]
#  http_method         = "POST"
#  resource_id         = aws_api_gateway_resource.subscription_resource.id
#  response_parameters = {
#    "method.response.header.Access-Control-Allow-Origin" = "'*'"
#  }
#  response_templates = {
#    "application/json" = ""
#  }
#  rest_api_id = aws_api_gateway_rest_api.subscription_api.id
#  status_code = "200"
#}
#
#resource "aws_lambda_permission" "subscribe_lambda_permission" {
#  statement_id  = "AllowExecutionFromAPIGateway"
#  action        = "lambda:InvokeFunction"
#  function_name = aws_lambda_function.SubscribeLambda.function_name
#  principal     = "apigateway.amazonaws.com"
#  # More: http://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-control-access-using-iam-policies-to-invoke-api.html
#  source_arn    = "arn:aws:execute-api:${var.region}:${data.aws_caller_identity.current.account_id}:${aws_api_gateway_rest_api.subscription_api.id}/*/${aws_api_gateway_method.subscription_post.http_method}${aws_api_gateway_resource.subscription_resource.path}"
#}
###########################################################################
#  SUBSCRIBE
###########################################################################

resource "aws_api_gateway_resource" "subscribe_resource" {
  rest_api_id = aws_api_gateway_rest_api.subscription_api.id
  parent_id   = aws_api_gateway_resource.subscription_resource.id
  path_part   = "subscribe"
}

resource "aws_api_gateway_method" "subscribe_post" {
  rest_api_id        = aws_api_gateway_rest_api.subscription_api.id
  resource_id        = aws_api_gateway_resource.subscribe_resource.id
  http_method          = "POST"
  authorization        = "NONE"
}

resource "aws_api_gateway_method_response" "sub_post_response" {
  http_method     = "POST"
  resource_id     = aws_api_gateway_resource.subscribe_resource.id
  response_models = {
    "text/html" = aws_api_gateway_model.html_model.name
  }
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = false
  }
  rest_api_id = aws_api_gateway_rest_api.subscription_api.id
  status_code = "200"
}

resource "aws_api_gateway_integration" "subscribe_post_integration" {
  rest_api_id             = aws_api_gateway_rest_api.subscription_api.id
  resource_id             = aws_api_gateway_resource.subscribe_resource.id
  http_method             = aws_api_gateway_method.subscribe_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  content_handling        = "CONVERT_TO_TEXT"
  uri                     = aws_lambda_function.SubscribeLambda.invoke_arn
}

resource "aws_api_gateway_integration_response" "sub_post_integration_response" {
  depends_on          = [aws_api_gateway_integration.subscription_options_integration]
  http_method         = "POST"
  resource_id         = aws_api_gateway_resource.subscribe_resource.id
  response_parameters = {}
  response_templates  = { "application/json" : "" }
  rest_api_id         = aws_api_gateway_rest_api.subscription_api.id
  status_code         = "200"
}

resource "aws_lambda_permission" "subscribe_lambda_permission" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.SubscribeLambda.function_name
  principal     = "apigateway.amazonaws.com"
  # More: http://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-control-access-using-iam-policies-to-invoke-api.html
  source_arn    = "arn:aws:execute-api:${var.region}:${data.aws_caller_identity.current.account_id}:${aws_api_gateway_rest_api.subscription_api.id}/*/${aws_api_gateway_method.subscribe_post.http_method}${aws_api_gateway_resource.subscribe_resource.path}"
}
###########################################################################
#  UNSUBSCRIBE
###########################################################################

resource "aws_api_gateway_resource" "unsubscribe_resource" {
  rest_api_id = aws_api_gateway_rest_api.subscription_api.id
  parent_id   = aws_api_gateway_resource.subscription_resource.id
  path_part   = "unsubscribe"
}

resource "aws_api_gateway_method" "unsubscribe_get" {
  rest_api_id        = aws_api_gateway_rest_api.subscription_api.id
  resource_id        = aws_api_gateway_resource.unsubscribe_resource.id
  request_parameters = {
    "method.request.querystring.email" = true
    "method.request.querystring.id"    = true
  }
  request_validator_id = aws_api_gateway_request_validator.parameter_validator.id
  http_method          = "GET"
  authorization        = "NONE"
}

resource "aws_api_gateway_method_response" "unsubscribe_get_response" {
  http_method     = "GET"
  resource_id     = aws_api_gateway_resource.unsubscribe_resource.id
  response_models = {
    "text/html" = aws_api_gateway_model.html_model.name
  }
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = false
  }
  rest_api_id = aws_api_gateway_rest_api.subscription_api.id
  status_code = "200"
}

resource "aws_api_gateway_integration" "unsubscribe_get_integration" {
  rest_api_id             = aws_api_gateway_rest_api.subscription_api.id
  resource_id             = aws_api_gateway_resource.unsubscribe_resource.id
  http_method             = aws_api_gateway_method.unsubscribe_get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  content_handling        = "CONVERT_TO_TEXT"
  uri                     = aws_lambda_function.UnsubscribeLambda.invoke_arn
}

resource "aws_api_gateway_integration_response" "unsub_get_integration_response" {
  depends_on          = [aws_api_gateway_integration.subscription_options_integration]
  http_method         = "GET"
  resource_id         = aws_api_gateway_resource.unsubscribe_resource.id
  response_parameters = {}
  response_templates  = { "application/json" : "" }
  rest_api_id         = aws_api_gateway_rest_api.subscription_api.id
  status_code         = "200"
}

resource "aws_lambda_permission" "unsub_lambda_permission" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.UnsubscribeLambda.function_name
  principal     = "apigateway.amazonaws.com"
  # More: http://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-control-access-using-iam-policies-to-invoke-api.html
  source_arn    = "arn:aws:execute-api:${var.region}:${data.aws_caller_identity.current.account_id}:${aws_api_gateway_rest_api.subscription_api.id}/*/${aws_api_gateway_method.unsubscribe_get.http_method}${aws_api_gateway_resource.unsubscribe_resource.path}"
}
###########################################################################
# OPTIONS
###########################################################################
resource "aws_api_gateway_method" "subscription_options" {
  rest_api_id   = aws_api_gateway_rest_api.subscription_api.id
  resource_id   = aws_api_gateway_resource.subscription_resource.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_method_response" "subscription_options_response" {
  http_method     = "OPTIONS"
  resource_id     = aws_api_gateway_resource.subscription_resource.id
  response_models = {
    "application/json" = "Empty"
  }
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = false
    "method.response.header.Access-Control-Allow-Methods" = false
    "method.response.header.Access-Control-Allow-Origin"  = false
  }
  rest_api_id = aws_api_gateway_rest_api.subscription_api.id
  status_code = "200"
}

resource "aws_api_gateway_integration" "subscription_options_integration" {
  rest_api_id = aws_api_gateway_rest_api.subscription_api.id
  resource_id = aws_api_gateway_resource.subscription_resource.id
  http_method = aws_api_gateway_method.subscription_options.http_method
  #  integration_http_method = "OPTIONS" #https://stackoverflow.com/questions/69380162/api-gateway-resources-are-creating-multiple-times-with-terraform-without-conside
  type        = "MOCK"
}

resource "aws_api_gateway_integration_response" "subscription_options_integration_response" {
  depends_on          = [aws_api_gateway_integration.subscription_options_integration]
  http_method         = "OPTIONS"
  resource_id         = aws_api_gateway_resource.subscription_resource.id
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'DELETE,OPTIONS,POST'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
  response_templates = {
    "application/json" = ""
  }
  rest_api_id = aws_api_gateway_rest_api.subscription_api.id
  status_code = "200"
}

###########################################################################
# DNS
###########################################################################

resource "aws_acm_certificate" "api_certificate" {
  provider          = aws.useast1 //certificate has to be from us-east-1 for CloudFront
  domain_name       = "api.${var.RootDomainName}"
  validation_method = "DNS"
  # (resource arguments)
}

resource "aws_route53_record" "route53_record" {
  for_each = {
  for dvo in aws_acm_certificate.api_certificate.domain_validation_options : dvo.domain_name => {
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

resource "aws_acm_certificate_validation" "api_certificate_validation" {
  provider                = aws.useast1 //certificate has to be from us-east-1 for CloudFront
  certificate_arn         = aws_acm_certificate.api_certificate.arn
  validation_record_fqdns = [
  for record in aws_route53_record.route53_record : record.fqdn
  ]
}


resource "aws_api_gateway_domain_name" "custom_api_domain_name" {
  certificate_arn = aws_acm_certificate.api_certificate.arn
  domain_name     = "api.${var.RootDomainName}"
}

resource "aws_api_gateway_base_path_mapping" "example" {
  api_id      = aws_api_gateway_rest_api.subscription_api.id
  stage_name  = aws_api_gateway_stage.test.stage_name
  domain_name = aws_api_gateway_domain_name.custom_api_domain_name.domain_name
}

data "aws_route53_zone" "route53_hosted_zone" {
  name         = var.RootDomainName
  private_zone = false
}

resource "aws_route53_record" "api_dns_record" {
  zone_id = data.aws_route53_zone.route53_hosted_zone.zone_id

  name = aws_api_gateway_domain_name.custom_api_domain_name.domain_name
  type = "A"

  alias {
    name                   = aws_api_gateway_domain_name.custom_api_domain_name.cloudfront_domain_name
    zone_id                = aws_api_gateway_domain_name.custom_api_domain_name.cloudfront_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_health_check" "accj_website_check" {
  reference_name    = "accj_website_check"
  fqdn              = "api.${var.RootDomainName}"
  port              = 443
  resource_path     = "/subscriptionmanager"
  failure_threshold = "5"
  request_interval  = "30"
  type              = "HTTPS"

  tags = {
    Name = "accj_api_check"
  }
}

###########################################################################
# SQS
###########################################################################
resource "aws_sqs_queue" "new_subscription_queue" {
  name = "new_subscription_queue"
}

###########################################################################
# SES
###########################################################################
data "local_file" "verification_email_template_html" {
  filename = "${path.module}/resources/VerificationEmailTemplate.html"
}

resource "aws_ses_template" "verification_email_template" {
  #TODO - move html into a data file
  name    = "EmailVerificationTemplate"
  subject = "Please confirm your subscription to ${var.RootDomainName}"
  html    = data.local_file.verification_email_template_html.content
  text    = "Hello,\r\nThank-you for subscribing for updates to ${var.RootDomainName}.\r\n.  To confirm your subscription please click {{verification_url}}"
}