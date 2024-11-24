provider "aws" {
  # Terraform will use the default AWS CLI credentials and region
  #region = "ap-south-1" # Optional; Terraform uses AWS CLI's default region if omitted
}

# Random ID for bucket uniqueness
resource "random_id" "suffix" {
  byte_length = 8
}

# S3 Bucket to store Lambda ZIP
resource "aws_s3_bucket" "lambda_bucket" {
  bucket        = "dotnet-lambda-${random_id.suffix.hex}"
  force_destroy = true
}

# Upload Lambda ZIP to S3
resource "aws_s3_object" "lambda_zip" {
  bucket = aws_s3_bucket.lambda_bucket.id
  key    = "LambdaTestAPI.zip"
  source = "${path.module}/LambdaTestAPI.zip"
}

resource "aws_iam_role" "lambda_role" {
  name               = "terraform_aws_lambda_role"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

# IAM policy for logging from a lambda

resource "aws_iam_policy" "iam_policy_for_lambda" {

  name        = "aws_iam_policy_for_terraform_aws_lambda_role"
  path        = "/"
  description = "AWS IAM Policy for managing aws lambda role"
  policy      = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*",
      "Effect": "Allow"
    }
  ]
}
EOF
}

# Policy Attachment on the role.

resource "aws_iam_role_policy_attachment" "attach_iam_policy_to_iam_role" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.iam_policy_for_lambda.arn
}


# Create the API Gateway
resource "aws_apigatewayv2_api" "lambda_api" {
  name          = "lambda-test-api"
  protocol_type = "HTTP"
}

# Create a Lambda Integration for the API
resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id                 = aws_apigatewayv2_api.lambda_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.terraform_lambda_func_test_api.arn
  payload_format_version = "2.0"
}

# Define routes for each HTTP method
resource "aws_apigatewayv2_route" "get_route" {
  api_id    = aws_apigatewayv2_api.lambda_api.id
  route_key = "GET /"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_apigatewayv2_route" "get_id_route" {
  api_id    = aws_apigatewayv2_api.lambda_api.id
  route_key = "GET /{id}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_apigatewayv2_route" "post_route" {
  api_id    = aws_apigatewayv2_api.lambda_api.id
  route_key = "POST /"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_apigatewayv2_route" "put_route" {
  api_id    = aws_apigatewayv2_api.lambda_api.id
  route_key = "PUT /"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_apigatewayv2_route" "delete_id_route" {
  api_id    = aws_apigatewayv2_api.lambda_api.id
  route_key = "DELETE /{id}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

# Create a Deployment for the API Gateway
resource "aws_apigatewayv2_stage" "default_stage" {
  api_id      = aws_apigatewayv2_api.lambda_api.id
  name        = "$default"
  auto_deploy = true
}

# Allow API Gateway to invoke Lambda function
resource "aws_lambda_permission" "apigw_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.terraform_lambda_func_test_api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.lambda_api.execution_arn}/*"
}

# Create a lambda function
# In terraform ${path.module} is the current directory.
resource "aws_lambda_function" "terraform_lambda_func_test_api" {
  function_name = "Test-Lambda-Function"
  runtime       = "dotnet8" # Specify .NET runtime
  role          = aws_iam_role.lambda_role.arn
  handler       = "LambdaTestAPI::LambdaTestAPI.LambdaEntryPoint::FunctionHandlerAsync" # Format: Assembly::Class::Method
  #filename         = "${path.module}/LambdaTestAPI.zip"
  s3_bucket        = aws_s3_bucket.lambda_bucket.id
  s3_key           = aws_s3_object.lambda_zip.key
  source_code_hash = filebase64sha256("${path.module}/LambdaTestAPI.zip")
  memory_size      = 512
  timeout          = 30
  depends_on       = [aws_iam_role_policy_attachment.attach_iam_policy_to_iam_role]
}


output "teraform_aws_role_output" {
  value = aws_iam_role.lambda_role.name
}

output "teraform_aws_role_arn_output" {
  value = aws_iam_role.lambda_role.arn
}

output "teraform_logging_arn_output" {
  value = aws_iam_policy.iam_policy_for_lambda.arn
}

output "api_endpoint" {
  value       = aws_apigatewayv2_api.lambda_api.api_endpoint
  description = "API Gateway Endpoint"
}
