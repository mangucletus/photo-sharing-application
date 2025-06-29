# terraform/iam.tf - Updated with Cognito and enhanced permissions

# IAM role for Lambda function
resource "aws_iam_role" "lambda_role" {
  name = "${local.resource_prefix}-lambda-role"

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

# IAM policy for Lambda to access S3, CloudWatch, and DynamoDB
resource "aws_iam_role_policy" "lambda_policy" {
  name = "${local.resource_prefix}-lambda-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "${aws_s3_bucket.images.arn}",
          "${aws_s3_bucket.images.arn}/*",
          "${aws_s3_bucket.thumbnails.arn}",
          "${aws_s3_bucket.thumbnails.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          aws_dynamodb_table.images_metadata.arn,
          "${aws_dynamodb_table.images_metadata.arn}/index/*"
        ]
      }
    ]
  })
}

# IAM role for API Gateway to invoke Lambda functions
resource "aws_iam_role" "api_gateway_role" {
  name = "${local.resource_prefix}-api-gateway-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      }
    ]
  })
}

# IAM policy for API Gateway to invoke Lambda
resource "aws_iam_role_policy" "api_gateway_policy" {
  name = "${local.resource_prefix}-api-gateway-policy"
  role = aws_iam_role.api_gateway_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = [
          aws_lambda_function.upload_handler.arn,
          aws_lambda_function.list_handler.arn,
          aws_lambda_function.image_resizer.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}