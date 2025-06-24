# API Gateway REST API
resource "aws_api_gateway_rest_api" "photo_api" {
  name        = "${local.resource_prefix}-api"
  description = "API for Photo Sharing App"
  
  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

# API Gateway Resource for images
resource "aws_api_gateway_resource" "images" {
  rest_api_id = aws_api_gateway_rest_api.photo_api.id
  parent_id   = aws_api_gateway_rest_api.photo_api.root_resource_id
  path_part   = "images"
}

# API Gateway Resource for specific image
resource "aws_api_gateway_resource" "image" {
  rest_api_id = aws_api_gateway_rest_api.photo_api.id
  parent_id   = aws_api_gateway_resource.images.id
  path_part   = "{image}"
}

# API Gateway Method for GET
resource "aws_api_gateway_method" "get_image" {
  rest_api_id   = aws_api_gateway_rest_api.photo_api.id
  resource_id   = aws_api_gateway_resource.image.id
  http_method   = "GET"
  authorization = "NONE"
}

# API Gateway Integration with S3
resource "aws_api_gateway_integration" "s3_integration" {
  rest_api_id = aws_api_gateway_rest_api.photo_api.id
  resource_id = aws_api_gateway_resource.image.id
  http_method = aws_api_gateway_method.get_image.http_method

  integration_http_method = "GET"
  type                   = "AWS"
  uri                    = "arn:aws:apigateway:${data.aws_region.current.name}:s3:path/${aws_s3_bucket.thumbnails.bucket}/{image}"
  credentials            = aws_iam_role.api_gateway_s3_role.arn

  request_parameters = {
    "method.request.path.image" = true
    "integration.request.path.image" = "method.request.path.image"
  }
}

# Method Response
resource "aws_api_gateway_method_response" "response_200" {
  rest_api_id = aws_api_gateway_rest_api.photo_api.id
  resource_id = aws_api_gateway_resource.image.id
  http_method = aws_api_gateway_method.get_image.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

# Integration Response
resource "aws_api_gateway_integration_response" "response_200" {
  rest_api_id = aws_api_gateway_rest_api.photo_api.id
  resource_id = aws_api_gateway_resource.image.id
  http_method = aws_api_gateway_method.get_image.http_method
  status_code = aws_api_gateway_method_response.response_200.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
  }

  depends_on = [aws_api_gateway_integration.s3_integration]
}

# API Gateway Deployment
resource "aws_api_gateway_deployment" "deployment" {
  rest_api_id = aws_api_gateway_rest_api.photo_api.id
  stage_name  = var.environment

  depends_on = [
    aws_api_gateway_integration.s3_integration,
    aws_api_gateway_integration_response.response_200
  ]

  lifecycle {
    create_before_destroy = true
  }
}

# IAM Role for API Gateway to access S3
resource "aws_iam_role" "api_gateway_s3_role" {
  name = "${local.resource_prefix}-api-gateway-s3-role"

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

# IAM Policy for API Gateway S3 access
resource "aws_iam_role_policy" "api_gateway_s3_policy" {
  name = "${local.resource_prefix}-api-gateway-s3-policy"
  role = aws_iam_role.api_gateway_s3_role.id

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