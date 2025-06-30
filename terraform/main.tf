terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  backend "s3" {
    bucket = "cletus-photo-sharing-tfstate-bucket-2753"
    key    = "photo-sharing-app/terraform.tfstate"
    region = "eu-west-1"
  }
}

provider "aws" {
  region = var.aws_region
}

# Variables
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-1"
}

variable "app_name" {
  description = "Application name"
  type        = string
  default     = "photo-sharing-app"
}

# Random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# S3 Bucket for Original Images
resource "aws_s3_bucket" "images" {
  bucket = "${var.app_name}-images-${random_string.suffix.result}"
}

resource "aws_s3_bucket_cors_configuration" "images_cors" {
  bucket = aws_s3_bucket.images.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "POST", "PUT", "DELETE"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }

  depends_on = [aws_s3_bucket.images]
}

resource "aws_s3_bucket_notification" "images_notification" {
  bucket = aws_s3_bucket.images.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.image_resizer.arn
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_lambda_permission.allow_s3]
}

# S3 Bucket for Thumbnails
resource "aws_s3_bucket" "thumbnails" {
  bucket = "${var.app_name}-thumbnails-${random_string.suffix.result}"
}

resource "aws_s3_bucket_cors_configuration" "thumbnails_cors" {
  bucket = aws_s3_bucket.thumbnails.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET"]
    allowed_origins = ["*"]
    max_age_seconds = 3000
  }

  depends_on = [aws_s3_bucket.thumbnails]
}

resource "aws_s3_bucket_public_access_block" "thumbnails_pab" {
  bucket = aws_s3_bucket.thumbnails.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "thumbnails_policy" {
  bucket = aws_s3_bucket.thumbnails.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.thumbnails.arn}/*"
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.thumbnails_pab]
}

# S3 Bucket for Frontend Hosting
resource "aws_s3_bucket" "frontend" {
  bucket = "${var.app_name}-frontend-${random_string.suffix.result}"
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

resource "aws_s3_bucket_cors_configuration" "frontend_cors" {
  bucket = aws_s3_bucket.frontend.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "HEAD"]
    allowed_origins = ["*"]
    max_age_seconds = 3000
  }

  depends_on = [aws_s3_bucket.frontend]
}

resource "aws_s3_bucket_public_access_block" "frontend_pab" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "frontend_policy" {
  bucket = aws_s3_bucket.frontend.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.frontend.arn}/*"
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.frontend_pab]
}

# DynamoDB Table for Image Metadata
resource "aws_dynamodb_table" "image_metadata" {
  name         = "${var.app_name}-metadata"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "image_id"

  attribute {
    name = "image_id"
    type = "S"
  }

  attribute {
    name = "user_id"
    type = "S"
  }

  global_secondary_index {
    name            = "user-id-index"
    hash_key        = "user_id"
    projection_type = "ALL"
  }
}

# Cognito User Pool
resource "aws_cognito_user_pool" "users" {
  name = "${var.app_name}-users"

  # Password policy
  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
    require_uppercase = true
  }

  # User name attributes
  username_attributes = ["email"]

  # Auto-verified attributes
  auto_verified_attributes = ["email"]

  # User name configuration
  username_configuration {
    case_sensitive = false
  }

  # Account recovery setting
  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  # Email configuration (using default Cognito email)
  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }

  # User pool add-ons
  user_pool_add_ons {
    advanced_security_mode = "OFF"
  }

  # Schema for additional user attributes
  schema {
    attribute_data_type      = "String"
    developer_only_attribute = false
    mutable                  = true
    name                     = "email"
    required                 = true

    string_attribute_constraints {
      min_length = 1
      max_length = 256
    }
  }

  schema {
    attribute_data_type      = "String"
    developer_only_attribute = false
    mutable                  = true
    name                     = "name"
    required                 = false

    string_attribute_constraints {
      min_length = 1
      max_length = 256
    }
  }

  # Verification message template
  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
    email_subject        = "Account Confirmation"
    email_message        = "Your confirmation code is {####}"
  }

  tags = {
    Name = "${var.app_name}-user-pool"
  }
}

# Cognito Identity Pool for S3 access
resource "aws_cognito_identity_pool" "identity_pool" {
  identity_pool_name               = "${var.app_name}-identity-pool"
  allow_unauthenticated_identities = false

  cognito_identity_providers {
    client_id     = aws_cognito_user_pool_client.app_client.id
    provider_name = aws_cognito_user_pool.users.endpoint
  }
}

# IAM role for authenticated users
resource "aws_iam_role" "authenticated_role" {
  name = "${var.app_name}-authenticated-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = "cognito-identity.amazonaws.com"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "cognito-identity.amazonaws.com:aud" = aws_cognito_identity_pool.identity_pool.id
          }
          "ForAnyValue:StringLike" = {
            "cognito-identity.amazonaws.com:amr" = "authenticated"
          }
        }
      }
    ]
  })
}

# Policy for authenticated users to access S3
resource "aws_iam_role_policy" "authenticated_s3_policy" {
  name = "${var.app_name}-authenticated-s3-policy"
  role = aws_iam_role.authenticated_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:GetObject",
          "s3:DeleteObject"
        ]
        Resource = [
          "${aws_s3_bucket.images.arn}/public/*",
          "${aws_s3_bucket.images.arn}/protected/$${cognito-identity.amazonaws.com:sub}/*",
          "${aws_s3_bucket.images.arn}/private/$${cognito-identity.amazonaws.com:sub}/*",
          "${aws_s3_bucket.images.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = [
          "${aws_s3_bucket.thumbnails.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.images.arn,
          aws_s3_bucket.thumbnails.arn
        ]
        Condition = {
          StringLike = {
            "s3:prefix" = [
              "public/",
              "public/*",
              "protected/",
              "protected/*",
              "private/$${cognito-identity.amazonaws.com:sub}/",
              "private/$${cognito-identity.amazonaws.com:sub}/*"
            ]
          }
        }
      }
    ]
  })
}

# Attach the role to the identity pool
resource "aws_cognito_identity_pool_roles_attachment" "identity_pool_roles" {
  identity_pool_id = aws_cognito_identity_pool.identity_pool.id

  roles = {
    "authenticated" = aws_iam_role.authenticated_role.arn
  }
}

resource "aws_cognito_user_pool_client" "app_client" {
  name         = "${var.app_name}-client"
  user_pool_id = aws_cognito_user_pool.users.id

  generate_secret = false

  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "${var.app_name}-lambda-role"

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

resource "aws_iam_role_policy" "lambda_s3_policy" {
  name = "${var.app_name}-lambda-s3-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = [
          "${aws_s3_bucket.images.arn}/*",
          "${aws_s3_bucket.thumbnails.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem"
        ]
        Resource = aws_dynamodb_table.image_metadata.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_role.name
}

# Create placeholder Lambda code for image resizer
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "image_resizer.zip"

  source {
    content  = <<EOF
import json
def lambda_handler(event, context):
    return {
        'statusCode': 200,
        'body': json.dumps('Placeholder function - will be updated by CI/CD')
    }
EOF
    filename = "lambda_function.py"
  }
}

# Create placeholder API Lambda code
data "archive_file" "api_lambda_zip" {
  type        = "zip"
  output_path = "api_lambda.zip"

  source {
    content  = <<EOF
import json
def lambda_handler(event, context):
    return {
        'statusCode': 200,
        'headers': {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Headers': 'Content-Type',
            'Access-Control-Allow-Methods': 'GET,POST,DELETE,OPTIONS'
        },
        'body': json.dumps({'message': 'API placeholder'})
    }
EOF
    filename = "lambda_function.py"
  }
}

# Lambda Function for Image Resizing
resource "aws_lambda_function" "image_resizer" {
  filename      = data.archive_file.lambda_zip.output_path
  function_name = "${var.app_name}-image-resizer"
  role          = aws_iam_role.lambda_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.9"
  timeout       = 30

  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      THUMBNAIL_BUCKET = aws_s3_bucket.thumbnails.bucket
      METADATA_TABLE   = aws_dynamodb_table.image_metadata.name
    }
  }
}

# Lambda Function for API
resource "aws_lambda_function" "api_lambda" {
  filename      = data.archive_file.api_lambda_zip.output_path
  function_name = "${var.app_name}-api"
  role          = aws_iam_role.api_lambda_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.9"
  timeout       = 30

  source_code_hash = data.archive_file.api_lambda_zip.output_base64sha256

  environment {
    variables = {
      METADATA_TABLE   = aws_dynamodb_table.image_metadata.name
      THUMBNAIL_BUCKET = aws_s3_bucket.thumbnails.bucket
    }
  }
}

# IAM Role for API Lambda
resource "aws_iam_role" "api_lambda_role" {
  name = "${var.app_name}-api-lambda-role"

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

# Enhanced policy for API Lambda to support DELETE operations
resource "aws_iam_role_policy" "api_lambda_policy" {
  name = "${var.app_name}-api-lambda-policy"
  role = aws_iam_role.api_lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:Query",
          "dynamodb:GetItem",
          "dynamodb:Scan",
          "dynamodb:DeleteItem"
        ]
        Resource = [
          aws_dynamodb_table.image_metadata.arn,
          "${aws_dynamodb_table.image_metadata.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:DeleteObject"
        ]
        Resource = [
          "${aws_s3_bucket.thumbnails.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "api_lambda_basic" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.api_lambda_role.name
}

resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.image_resizer.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.images.arn
}

# IAM Role for API Gateway to access S3
resource "aws_iam_role" "api_gateway_role" {
  name = "${var.app_name}-api-gateway-role"

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

resource "aws_iam_role_policy" "api_gateway_s3_policy" {
  name = "${var.app_name}-api-gateway-s3-policy"
  role = aws_iam_role.api_gateway_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = "${aws_s3_bucket.thumbnails.arn}/*"
      }
    ]
  })
}

# API Gateway
resource "aws_api_gateway_rest_api" "api" {
  name = "${var.app_name}-api"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "images_resource" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "images"
}

# Add path parameter for image key
resource "aws_api_gateway_resource" "image_key_resource" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_resource.images_resource.id
  path_part   = "{key+}"
}

resource "aws_api_gateway_method" "get_image_key" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.image_key_resource.id
  http_method   = "GET"
  authorization = "NONE"

  request_parameters = {
    "method.request.path.key" = true
  }
}

resource "aws_api_gateway_integration" "get_image_key_integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.image_key_resource.id
  http_method = aws_api_gateway_method.get_image_key.http_method

  integration_http_method = "GET"
  type                    = "AWS"
  uri                     = "arn:aws:apigateway:${var.aws_region}:s3:path/${aws_s3_bucket.thumbnails.bucket}/{key}"
  credentials             = aws_iam_role.api_gateway_role.arn

  request_parameters = {
    "integration.request.path.key" = "method.request.path.key"
  }
}

# API Lambda Integration
resource "aws_api_gateway_resource" "api_resource" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "api"
}

resource "aws_api_gateway_resource" "user_images_resource" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_resource.api_resource.id
  path_part   = "user"
}

resource "aws_api_gateway_resource" "user_id_resource" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_resource.user_images_resource.id
  path_part   = "{user_id}"
}

resource "aws_api_gateway_resource" "user_images_endpoint" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_resource.user_id_resource.id
  path_part   = "images"
}

# Resource for individual image operations (for DELETE)
resource "aws_api_gateway_resource" "user_image_endpoint" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_resource.user_images_endpoint.id
  path_part   = "{image_id}"
}

# GET method for fetching user images
resource "aws_api_gateway_method" "get_user_images" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.user_images_endpoint.id
  http_method   = "GET"
  authorization = "NONE"

  request_parameters = {
    "method.request.path.user_id" = true
  }
}

resource "aws_api_gateway_integration" "get_user_images_integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.user_images_endpoint.id
  http_method = aws_api_gateway_method.get_user_images.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.api_lambda.invoke_arn
}

# DELETE method for deleting specific image
resource "aws_api_gateway_method" "delete_user_image" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.user_image_endpoint.id
  http_method   = "DELETE"
  authorization = "NONE"

  request_parameters = {
    "method.request.path.user_id"  = true
    "method.request.path.image_id" = true
  }
}

resource "aws_api_gateway_integration" "delete_user_image_integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.user_image_endpoint.id
  http_method = aws_api_gateway_method.delete_user_image.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.api_lambda.invoke_arn
}

# OPTIONS method for CORS on images endpoint
resource "aws_api_gateway_method" "options_user_images" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.user_images_endpoint.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options_user_images_integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.user_images_endpoint.id
  http_method = aws_api_gateway_method.options_user_images.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "options_user_images_200" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.user_images_endpoint.id
  http_method = aws_api_gateway_method.options_user_images.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "options_user_images_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.user_images_endpoint.id
  http_method = aws_api_gateway_method.options_user_images.http_method
  status_code = aws_api_gateway_method_response.options_user_images_200.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,DELETE,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

# OPTIONS method for CORS on individual image endpoint
resource "aws_api_gateway_method" "options_user_image" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.user_image_endpoint.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options_user_image_integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.user_image_endpoint.id
  http_method = aws_api_gateway_method.options_user_image.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "options_user_image_200" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.user_image_endpoint.id
  http_method = aws_api_gateway_method.options_user_image.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "options_user_image_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.user_image_endpoint.id
  http_method = aws_api_gateway_method.options_user_image.http_method
  status_code = aws_api_gateway_method_response.options_user_image_200.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'DELETE,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

# Lambda permission for API Gateway
resource "aws_lambda_permission" "allow_api_gateway" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

resource "aws_api_gateway_method_response" "get_image_key_200" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.image_key_resource.id
  http_method = aws_api_gateway_method.get_image_key.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

resource "aws_api_gateway_integration_response" "get_image_key_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.image_key_resource.id
  http_method = aws_api_gateway_method.get_image_key.http_method
  status_code = aws_api_gateway_method_response.get_image_key_200.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
  }
}

resource "aws_api_gateway_method" "options_images" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.images_resource.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

# CORS for API Gateway
resource "aws_api_gateway_method_response" "options_200" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.images_resource.id
  http_method = aws_api_gateway_method.options_images.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration" "options_integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.images_resource.id
  http_method = aws_api_gateway_method.options_images.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_integration_response" "options_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.images_resource.id
  http_method = aws_api_gateway_method.options_images.http_method
  status_code = aws_api_gateway_method_response.options_200.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

resource "aws_api_gateway_deployment" "api_deployment" {
  depends_on = [
    aws_api_gateway_method.get_image_key,
    aws_api_gateway_method.options_images,
    aws_api_gateway_method.get_user_images,
    aws_api_gateway_method.delete_user_image,
    aws_api_gateway_method.options_user_images,
    aws_api_gateway_method.options_user_image,
    aws_api_gateway_integration.get_image_key_integration,
    aws_api_gateway_integration.options_integration,
    aws_api_gateway_integration.get_user_images_integration,
    aws_api_gateway_integration.delete_user_image_integration,
    aws_api_gateway_integration.options_user_images_integration,
    aws_api_gateway_integration.options_user_image_integration
  ]

  rest_api_id = aws_api_gateway_rest_api.api.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.images_resource.id,
      aws_api_gateway_resource.image_key_resource.id,
      aws_api_gateway_resource.api_resource.id,
      aws_api_gateway_resource.user_images_endpoint.id,
      aws_api_gateway_resource.user_image_endpoint.id,
      aws_api_gateway_method.get_image_key.id,
      aws_api_gateway_method.options_images.id,
      aws_api_gateway_method.get_user_images.id,
      aws_api_gateway_method.delete_user_image.id,
      aws_api_gateway_method.options_user_images.id,
      aws_api_gateway_method.options_user_image.id,
      aws_api_gateway_integration.get_image_key_integration.id,
      aws_api_gateway_integration.options_integration.id,
      aws_api_gateway_integration.get_user_images_integration.id,
      aws_api_gateway_integration.delete_user_image_integration.id,
      aws_api_gateway_integration.options_user_images_integration.id,
      aws_api_gateway_integration.options_user_image_integration.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "api_stage" {
  deployment_id = aws_api_gateway_deployment.api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.api.id
  stage_name    = "prod"
}

# Outputs
output "images_bucket_name" {
  value = aws_s3_bucket.images.bucket
}

output "thumbnails_bucket_name" {
  value = aws_s3_bucket.thumbnails.bucket
}

output "frontend_bucket_name" {
  value = aws_s3_bucket.frontend.bucket
}

output "frontend_url" {
  value = aws_s3_bucket_website_configuration.frontend_website.website_endpoint
}

output "api_gateway_url" {
  value = aws_api_gateway_stage.api_stage.invoke_url
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.users.id
}

output "cognito_client_id" {
  value = aws_cognito_user_pool_client.app_client.id
}

output "cognito_identity_pool_id" {
  value = aws_cognito_identity_pool.identity_pool.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.image_metadata.name
}

output "lambda_function_name" {
  value = aws_lambda_function.image_resizer.function_name
}

output "api_lambda_function_name" {
  value = aws_lambda_function.api_lambda.function_name
}