# terraform/dynamodb.tf - New file for DynamoDB table

# DynamoDB table for storing image metadata
resource "aws_dynamodb_table" "images_metadata" {
  name           = "${local.resource_prefix}-images-metadata"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "image_id"

  attribute {
    name = "image_id"
    type = "S"
  }

  attribute {
    name = "upload_date"
    type = "S"
  }

  attribute {
    name = "user_id"
    type = "S"
  }

  # Global Secondary Index for querying by upload date
  global_secondary_index {
    name               = "upload-date-index"
    hash_key           = "upload_date"
    projection_type    = "ALL"
  }

  # Global Secondary Index for querying by user
  global_secondary_index {
    name               = "user-index"
    hash_key           = "user_id"
    projection_type    = "ALL"
  }

  tags = {
    Name        = "${local.resource_prefix}-images-metadata"
    Environment = var.environment
  }
}

# IAM role for DynamoDB access
resource "aws_iam_role_policy" "lambda_dynamodb_policy" {
  name = "${local.resource_prefix}-lambda-dynamodb-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
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