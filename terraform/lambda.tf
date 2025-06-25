# terraform/lambda.tf - Updated with additional Lambda functions

# Create ZIP file for Lambda deployment
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "../lambda"
  output_path = "lambda_function.zip"
}

# Lambda function for image resizing
resource "aws_lambda_function" "image_resizer" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${local.resource_prefix}-image-resizer"
  role            = aws_iam_role.lambda_role.arn
  handler         = "image_resizer.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      THUMBNAIL_BUCKET = aws_s3_bucket.thumbnails.bucket
      THUMBNAIL_SIZE   = var.thumbnail_size
      DYNAMODB_TABLE   = aws_dynamodb_table.images_metadata.name
    }
  }

  depends_on = [
    aws_iam_role_policy.lambda_policy,
    aws_cloudwatch_log_group.lambda_logs
  ]
}

# Lambda function for handling uploads via API Gateway
resource "aws_lambda_function" "upload_handler" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${local.resource_prefix}-upload-handler"
  role            = aws_iam_role.lambda_role.arn
  handler         = "upload_handler.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      IMAGES_BUCKET    = aws_s3_bucket.images.bucket
      THUMBNAIL_BUCKET = aws_s3_bucket.thumbnails.bucket
      DYNAMODB_TABLE   = aws_dynamodb_table.images_metadata.name
    }
  }

  depends_on = [
    aws_iam_role_policy.lambda_policy,
    aws_cloudwatch_log_group.upload_lambda_logs
  ]
}

# Lambda function for listing images
resource "aws_lambda_function" "list_handler" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${local.resource_prefix}-list-handler"
  role            = aws_iam_role.lambda_role.arn
  handler         = "list_handler.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      THUMBNAIL_BUCKET = aws_s3_bucket.thumbnails.bucket
      DYNAMODB_TABLE   = aws_dynamodb_table.images_metadata.name
    }
  }

  depends_on = [
    aws_iam_role_policy.lambda_policy,
    aws_cloudwatch_log_group.list_lambda_logs
  ]
}

# CloudWatch Log Groups for Lambda functions
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.resource_prefix}-image-resizer"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "upload_lambda_logs" {
  name              = "/aws/lambda/${local.resource_prefix}-upload-handler"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "list_lambda_logs" {
  name              = "/aws/lambda/${local.resource_prefix}-list-handler"
  retention_in_days = 14
}

# Permission for S3 to invoke Lambda
resource "aws_lambda_permission" "s3_invoke" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.image_resizer.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.images.arn
}