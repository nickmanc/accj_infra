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

data "archive_file" "SubscribeLambdaZip" {
  type        = "zip"
  source {
    content  = templatefile("${path.module}/code/Subscribe.js",
      { tableName = aws_dynamodb_table.subscriptions.name } )
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

data "aws_caller_identity" "current" {}

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
          Action    = "dynamodb:PutItem"
          Condition = {
            StringEqualsIfExists = {
              "aws:SourceAccount" : data.aws_caller_identity.current.account_id
            }
          }
          Effect   = "Allow"
          Resource = aws_dynamodb_table.subscriptions.arn
        },
        {
          "Effect": "Allow",
          "Action": [
            "logs:CreateLogGroup",
            "logs:CreateLogStream",
            "logs:PutLogEvents"
          ],
          "Resource": "*"
        }
      ]
    })
  }
}

resource "aws_api_gateway_rest_api" "subscribe_api" {
  name                         = "Subscribe"
}

resource "aws_api_gateway_deployment" "test" {
  depends_on = [
    aws_api_gateway_method.subscribe_post,
    aws_api_gateway_integration.subscribe_post_integration,
    aws_api_gateway_method.subscribe_options,
    aws_api_gateway_integration.subscribe_options_integration
  ]
  rest_api_id = aws_api_gateway_rest_api.subscribe_api.id

  triggers = {
    redeployment = sha1(jsonencode(aws_api_gateway_rest_api.subscribe_api.body))
  }

  lifecycle {
    create_before_destroy = true
  }
  stage_description = "${md5(file("main.tf"))}"
}

resource "aws_api_gateway_stage" "test" {
  deployment_id = aws_api_gateway_deployment.test.id
  rest_api_id   = aws_api_gateway_rest_api.subscribe_api.id
  stage_name    = "test"
}

resource "aws_api_gateway_resource" "subscribe_resource" {
  rest_api_id = aws_api_gateway_rest_api.subscribe_api.id
  parent_id   = aws_api_gateway_rest_api.subscribe_api.root_resource_id
  path_part   = "subscriptionmanager"
}

resource "aws_api_gateway_method" "subscribe_post" {
  rest_api_id   = aws_api_gateway_rest_api.subscribe_api.id
  resource_id   = aws_api_gateway_resource.subscribe_resource.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "subscribe_options" {
  rest_api_id   = aws_api_gateway_rest_api.subscribe_api.id
  resource_id   = aws_api_gateway_resource.subscribe_resource.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_method_response" "subscribe_options_response" {
  http_method         = "OPTIONS"
  resource_id         = aws_api_gateway_resource.subscribe_resource.id
  response_models     = {
    "application/json" = "Empty"
  }
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = false
    "method.response.header.Access-Control-Allow-Methods" = false
    "method.response.header.Access-Control-Allow-Origin"  = false
  }
  rest_api_id         = aws_api_gateway_rest_api.subscribe_api.id
  status_code         = "200"
}

resource "aws_api_gateway_integration_response" "subscribe_options_response" {
  depends_on = [aws_api_gateway_integration.subscribe_options_integration]
  http_method         = "OPTIONS"
  resource_id         = aws_api_gateway_resource.subscribe_resource.id
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'OPTIONS,POST'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
  response_templates  = {
    "application/json" = ""
  }
  rest_api_id         = aws_api_gateway_rest_api.subscribe_api.id
  status_code         = "200"
}

resource "aws_api_gateway_method_response" "subscribe_post_response" {
  http_method         = "POST"
  resource_id         = aws_api_gateway_resource.subscribe_resource.id
  response_models     = {
    "application/json" = "Empty"
  }
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = false
  }
  rest_api_id         = aws_api_gateway_rest_api.subscribe_api.id
  status_code         = "200"
}

resource "aws_api_gateway_integration_response" "subscribe_post_response" {
  depends_on = [aws_api_gateway_integration.subscribe_options_integration]
  http_method         = "POST"
  resource_id         = aws_api_gateway_resource.subscribe_resource.id
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
  response_templates  = {
    "application/json" = ""
  }
  rest_api_id         = aws_api_gateway_rest_api.subscribe_api.id
  status_code         = "200"
}

#resource "aws_api_gateway_method_settings" "all" {
#  rest_api_id = aws_api_gateway_rest_api.subscribe_api.id
#  stage_name  = aws_api_gateway_stage.test.stage_name
#  method_path = "*/*"
#
#  settings {
##    metrics_enabled = true
##    logging_level   = "ERROR"
#  }
#}

resource "aws_api_gateway_integration" "subscribe_post_integration" {
  rest_api_id             = aws_api_gateway_rest_api.subscribe_api.id
  resource_id             = aws_api_gateway_resource.subscribe_resource.id
  http_method             = aws_api_gateway_method.subscribe_post.http_method
  integration_http_method = "POST"
  type                    = "AWS"
  uri                     = aws_lambda_function.SubscribeLambda.invoke_arn
}

resource "aws_api_gateway_integration" "subscribe_options_integration" {
  rest_api_id             = aws_api_gateway_rest_api.subscribe_api.id
  resource_id             = aws_api_gateway_resource.subscribe_resource.id
  http_method             = aws_api_gateway_method.subscribe_options.http_method
  integration_http_method = "OPTIONS"
  type                    = "MOCK"
}

resource "aws_lambda_permission" "apigw_lambda" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.SubscribeLambda.function_name
  principal     = "apigateway.amazonaws.com"
  # More: http://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-control-access-using-iam-policies-to-invoke-api.html
  source_arn = "arn:aws:execute-api:${var.region}:${data.aws_caller_identity.current.account_id}:${aws_api_gateway_rest_api.subscribe_api.id}/*/${aws_api_gateway_method.subscribe_post.http_method}${aws_api_gateway_resource.subscribe_resource.path}"
}


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
  api_id      = aws_api_gateway_rest_api.subscribe_api.id
  stage_name  = aws_api_gateway_stage.test.stage_name
  domain_name = aws_api_gateway_domain_name.custom_api_domain_name.domain_name
}

data "aws_route53_zone" "route53_hosted_zone" {
  name         = var.RootDomainName
  private_zone = false
}

resource "aws_route53_record" "custom_api_dns_record" {
  zone_id = data.aws_route53_zone.route53_hosted_zone.zone_id

  name = aws_api_gateway_domain_name.custom_api_domain_name.domain_name
  type = "CNAME"

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