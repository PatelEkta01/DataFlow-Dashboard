terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }

  required_version = ">= 1.0"
}

provider "aws" {
  region = "us-east-1"
}

# Frontend hosting bucket
resource "aws_s3_bucket" "frontend" {
  bucket = "dataflow-dashboard-site"
  force_destroy = true

  tags = {
    Name = "Dataflow Frontend Site"
  }
}

resource "aws_s3_bucket_website_configuration" "frontend_website" {
  bucket = aws_s3_bucket.frontend.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}


resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# Upload bucket for CSV
resource "aws_s3_bucket" "uploads" {
  bucket = "dataflow-dashboard-uploads"
  force_destroy = true

  tags = {
    Name = "Dataflow Upload Bucket"
  }
}

# DynamoDB table for processed data
resource "aws_dynamodb_table" "dashboard_data" {
  name         = "dashboard_data"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "record_id"

  attribute {
    name = "record_id"
    type = "S"
  }

  tags = {
    Name = "Dashboard Data Table"
  }
}
# Zip the Lambda code
data "archive_file" "upload_lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda_upload/lambda_function.py"
  output_path = "${path.module}/lambda_upload/lambda_function.zip"
}

# Lambda function using LabRole
resource "aws_lambda_function" "process_upload" {
  function_name = "process_upload"
  filename      = data.archive_file.upload_lambda.output_path
  source_code_hash = filebase64sha256(data.archive_file.upload_lambda.output_path)
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"
  role          = "arn:aws:iam::314310821739:role/LabRole"

  environment {
    variables = {
      DDB_TABLE = aws_dynamodb_table.dashboard_data.name
    }
  }

  depends_on = [aws_dynamodb_table.dashboard_data]
}

# Allow S3 to trigger the Lambda
resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowExecutionFromS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.process_upload.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.uploads.arn
}

# S3 → Lambda trigger
resource "aws_s3_bucket_notification" "upload_trigger" {
  bucket = aws_s3_bucket.uploads.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.process_upload.arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = ".csv"
  }

  depends_on = [aws_lambda_permission.allow_s3]
}
# Archive query lambda
data "archive_file" "query_lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda_query/lambda_function.py"
  output_path = "${path.module}/lambda_query/lambda_function.zip"
}

# Lambda function to serve API responses
resource "aws_lambda_function" "query_data" {
  function_name = "query_data"
  filename      = data.archive_file.query_lambda.output_path
  source_code_hash = filebase64sha256(data.archive_file.query_lambda.output_path)
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"
  role          = "arn:aws:iam::314310821739:role/LabRole"

  environment {
    variables = {
      DDB_TABLE = aws_dynamodb_table.dashboard_data.name
    }
  }

  depends_on = [aws_dynamodb_table.dashboard_data]
}
# Create REST API
resource "aws_api_gateway_rest_api" "api" {
  name        = "DataflowAPI"
  description = "API for dashboard chart data"
}

# Define GET /get-data path
resource "aws_api_gateway_resource" "get_data" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "get-data"
}

resource "aws_api_gateway_method" "get_data_method" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.get_data.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.get_data.id
  http_method             = aws_api_gateway_method.get_data_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.query_data.invoke_arn
}

# Allow API Gateway to call Lambda
resource "aws_lambda_permission" "api_gw_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.query_data.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

# Deploy the API
resource "aws_api_gateway_deployment" "deployment" {
  depends_on = [aws_api_gateway_integration.lambda_integration]
  rest_api_id = aws_api_gateway_rest_api.api.id
}

# Define the /prod stage
resource "aws_api_gateway_stage" "prod" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.deployment.id
}

resource "aws_sns_topic" "etl_summary" {
  name = "dataflow-etl-summary"
}

resource "aws_sns_topic_subscription" "email_alert" {
  topic_arn = aws_sns_topic.etl_summary.arn
  protocol  = "email"
  endpoint  = "patelekta1703@gmail.com"  # 🔁 Replace this with your real email
}
# 🔔 Alarm if Lambda throws any error
resource "aws_cloudwatch_metric_alarm" "etl_errors" {
  alarm_name          = "ETLFunctionErrors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "ETL Lambda has failed at least once"
  dimensions = {
    FunctionName = aws_lambda_function.process_upload.function_name
  }
  alarm_actions = [aws_sns_topic.etl_summary.arn]
}

# 🚨 Alarm if ETL Lambda hasn't been triggered at all (broken trigger)
resource "aws_cloudwatch_metric_alarm" "etl_zero_invokes" {
  alarm_name          = "ETLFunctionZeroInvokes"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Invocations"
  namespace           = "AWS/Lambda"
  period              = 900  # 15 minutes
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "ETL Lambda has not been invoked in the last 15 minutes"
  dimensions = {
    FunctionName = aws_lambda_function.process_upload.function_name
  }
  alarm_actions = [aws_sns_topic.etl_summary.arn]
}

# ⏱ Alarm if Lambda runs for more than 10 seconds
resource "aws_cloudwatch_metric_alarm" "etl_duration" {
  alarm_name          = "ETLFunctionHighDuration"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Average"
  threshold           = 10000  # milliseconds = 10 seconds
  alarm_description   = "ETL Lambda is running slower than expected"
  dimensions = {
    FunctionName = aws_lambda_function.process_upload.function_name
  }
  alarm_actions = [aws_sns_topic.etl_summary.arn]
}

# Output the full API URL
output "api_url" {
  value = "https://${aws_api_gateway_rest_api.api.id}.execute-api.us-east-1.amazonaws.com/prod/get-data"
}

