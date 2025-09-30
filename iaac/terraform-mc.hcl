# terraform/aws/main.tf
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  default = "us-east-1"
}

# DynamoDB Table
resource "aws_dynamodb_table" "credit_applications" {
  name         = "CreditApplications"
  billing_mode = "PAY_PER_REQUEST"  # Serverless
  hash_key     = "userId"
  range_key    = "applicationId"

  attribute {
    name = "userId"
    type = "S"
  }

  attribute {
    name = "applicationId"
    type = "S"
  }

  attribute {
    name = "status"
    type = "S"
  }

  attribute {
    name = "submittedDate"
    type = "S"
  }

  # Global Secondary Index for querying by status
  global_secondary_index {
    name            = "StatusIndex"
    hash_key        = "status"
    range_key       = "submittedDate"
    projection_type = "ALL"
  }

  tags = {
    Environment = "production"
    Project     = "CreditApp"
  }
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "credit_app_lambda_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# IAM Policy for DynamoDB access
resource "aws_iam_role_policy" "lambda_dynamodb_policy" {
  name = "lambda_dynamodb_access"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          aws_dynamodb_table.credit_applications.arn,
          "${aws_dynamodb_table.credit_applications.arn}/index/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# Lambda Function
resource "aws_lambda_function" "process_credit_app" {
  filename      = "lambda.zip"
  function_name = "ProcessCreditApplication"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler"
  runtime       = "nodejs18.x"
  timeout       = 30

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.credit_applications.name
      AWS_REGION     = var.aws_region
    }
  }

  # Provisioned concurrency to avoid cold starts
  reserved_concurrent_executions = 10

  tags = {
    Environment = "production"
  }
}

# Lambda Alias with Provisioned Concurrency
resource "aws_lambda_alias" "prod" {
  name             = "prod"
  function_name    = aws_lambda_function.process_credit_app.arn
  function_version = "$LATEST"
}

resource "aws_lambda_provisioned_concurrency_config" "prod" {
  function_name                     = aws_lambda_function.process_credit_app.function_name
  provisioned_concurrent_executions = 5
  qualifier                         = aws_lambda_alias.prod.name
}

# API Gateway
resource "aws_apigatewayv2_api" "credit_api" {
  name          = "credit-application-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id           = aws_apigatewayv2_api.credit_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.process_credit_app.invoke_arn
}

resource "aws_apigatewayv2_route" "post_application" {
  api_id    = aws_apigatewayv2_api.credit_api.id
  route_key = "POST /applications"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_apigatewayv2_stage" "prod" {
  api_id      = aws_apigatewayv2_api.credit_api.id
  name        = "prod"
  auto_deploy = true
}

# Lambda permission for API Gateway
resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.process_credit_app.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.credit_api.execution_arn}/*/*"
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.process_credit_app.function_name}"
  retention_in_days = 7
}

# Outputs
output "api_endpoint" {
  value = aws_apigatewayv2_stage.prod.invoke_url
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.credit_applications.name
}

output "lambda_function_name" {
  value = aws_lambda_function.process_credit_app.function_name
}
