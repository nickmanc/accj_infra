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
# API
###########################################################################
resource "aws_api_gateway_rest_api" "subscription_api" {
  name = "Subscription"
}

resource "aws_api_gateway_deployment" "test" {
  depends_on = [
    aws_api_gateway_method.subscription_post,
    aws_api_gateway_integration.subscription_post_integration,
    aws_api_gateway_method.subscription_options,
    aws_api_gateway_integration.subscription_options_integration,
    aws_api_gateway_method.subscription_delete,
    aws_api_gateway_integration.subscription_delete_integration
  ]
  rest_api_id = aws_api_gateway_rest_api.subscription_api.id

  triggers = {
    redeployment = sha1(jsonencode(aws_api_gateway_rest_api.subscription_api.body))
  }

  lifecycle {
    create_before_destroy = true
  }
  stage_description = md5(file("main.tf"))
}

resource "aws_api_gateway_stage" "test" {
  deployment_id = aws_api_gateway_deployment.test.id
  rest_api_id   = aws_api_gateway_rest_api.subscription_api.id
  cache_cluster_size    = "0.5"
  stage_name    = "test"
}

resource "aws_api_gateway_resource" "subscription_resource" {
  rest_api_id = aws_api_gateway_rest_api.subscription_api.id
  parent_id   = aws_api_gateway_rest_api.subscription_api.root_resource_id
  path_part   = "subscriptionmanager"
}

###########################################################################
# LAMBDAS
###########################################################################
data "archive_file" "SubscribeLambdaZip" {
  type = "zip"
  source {
    content = templatefile("${path.module}/code/Subscribe.js",
      { tableName = aws_dynamodb_table.subscriptions.name,
        new_subscription_queue_url = aws_sqs_queue.new_subscription_queue.url} )
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
          "Effect": "Allow",
          "Action": "sqs:SendMessage",
          "Resource": aws_sqs_queue.new_subscription_queue.arn
        },
        {
          "Effect": "Allow",
          "Action": "ses:SendEmail",
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
      { tableName = aws_dynamodb_table.subscriptions.name } )
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

###########################################################################
# POST  /  SUBSCRIBE
###########################################################################
resource "aws_api_gateway_method" "subscription_post" {
  rest_api_id   = aws_api_gateway_rest_api.subscription_api.id
  resource_id   = aws_api_gateway_resource.subscription_resource.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_method_response" "subscription_post_response" {
  http_method     = "POST"
  resource_id     = aws_api_gateway_resource.subscription_resource.id
  response_models = {
    "application/json" = "Empty"
  }
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = false
  }
  rest_api_id = aws_api_gateway_rest_api.subscription_api.id
  status_code = "200"
}

resource "aws_api_gateway_integration" "subscription_post_integration" {
  rest_api_id             = aws_api_gateway_rest_api.subscription_api.id
  resource_id             = aws_api_gateway_resource.subscription_resource.id
  http_method             = aws_api_gateway_method.subscription_post.http_method
  integration_http_method = "POST"
  type                    = "AWS"
  uri                     = aws_lambda_function.SubscribeLambda.invoke_arn
}

resource "aws_api_gateway_integration_response" "subscription_post_integration_response" {
  depends_on          = [aws_api_gateway_integration.subscription_options_integration]
  http_method         = "POST"
  resource_id         = aws_api_gateway_resource.subscription_resource.id
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
  }
  response_templates = {
    "application/json" = ""
  }
  rest_api_id = aws_api_gateway_rest_api.subscription_api.id
  status_code = "200"
}

resource "aws_lambda_permission" "subscribe_lambda_permission" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.SubscribeLambda.function_name
  principal     = "apigateway.amazonaws.com"
  # More: http://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-control-access-using-iam-policies-to-invoke-api.html
  source_arn    = "arn:aws:execute-api:${var.region}:${data.aws_caller_identity.current.account_id}:${aws_api_gateway_rest_api.subscription_api.id}/*/${aws_api_gateway_method.subscription_post.http_method}${aws_api_gateway_resource.subscription_resource.path}"
}
###########################################################################
# DELETE  /  UNSUBSCRIBE
###########################################################################
resource "aws_api_gateway_method" "subscription_delete" {
  rest_api_id   = aws_api_gateway_rest_api.subscription_api.id
  resource_id   = aws_api_gateway_resource.subscription_resource.id
  http_method   = "DELETE"
  authorization = "NONE"
}

resource "aws_api_gateway_method_response" "subscription_delete_response" {
  http_method     = "DELETE"
  resource_id     = aws_api_gateway_resource.subscription_resource.id
  response_models = {
    "application/json" = "Empty"
  }
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = false
  }
  rest_api_id = aws_api_gateway_rest_api.subscription_api.id
  status_code = "200"
}

resource "aws_api_gateway_integration" "subscription_delete_integration" {
  rest_api_id             = aws_api_gateway_rest_api.subscription_api.id
  resource_id             = aws_api_gateway_resource.subscription_resource.id
  http_method             = aws_api_gateway_method.subscription_delete.http_method
  integration_http_method = "POST"
  type                    = "AWS"
  uri                     = aws_lambda_function.UnsubscribeLambda.invoke_arn
}

resource "aws_api_gateway_integration_response" "subscription_delete_integration_response" {
  depends_on          = [aws_api_gateway_integration.subscription_options_integration]
  http_method         = "POST"
  resource_id         = aws_api_gateway_resource.subscription_resource.id
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
  }
  response_templates = {
    "application/json" = ""
  }
  rest_api_id = aws_api_gateway_rest_api.subscription_api.id
  status_code = "200"
}

resource "aws_lambda_permission" "unsubscribe_lambda_permission" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.UnsubscribeLambda.function_name
  principal     = "apigateway.amazonaws.com"
  # More: http://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-control-access-using-iam-policies-to-invoke-api.html
  source_arn    = "arn:aws:execute-api:${var.region}:${data.aws_caller_identity.current.account_id}:${aws_api_gateway_rest_api.subscription_api.id}/*/${aws_api_gateway_method.subscription_delete.http_method}${aws_api_gateway_resource.subscription_resource.path}"
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
  rest_api_id             = aws_api_gateway_rest_api.subscription_api.id
  resource_id             = aws_api_gateway_resource.subscription_resource.id
  http_method             = aws_api_gateway_method.subscription_options.http_method
  integration_http_method = "OPTIONS"
  type                    = "MOCK"
}

resource "aws_api_gateway_integration_response" "subscription_options_integration_response" {
  depends_on          = [aws_api_gateway_integration.subscription_options_integration]
  http_method         = "OPTIONS"
  resource_id         = aws_api_gateway_resource.subscription_resource.id
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'OPTIONS,POST,DELETE'"
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
  validation_record_fqdns = [for record in aws_route53_record.route53_record : record.fqdn]
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