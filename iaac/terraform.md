resource "aws_dynamodb_table" "credit_apps" {
  name         = "CreditApplications"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "userId"

  attribute {
    name = "userId"
    type = "S"
  }
}

resource "aws_lambda_function" "process_app" {
  filename      = "lambda.zip"
  function_name = "ProcessCreditApp"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler"
  runtime       = "nodejs18.x"

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.credit_apps.name
    }
  }
}
