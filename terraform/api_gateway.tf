# terraform/api_gateway.tf - Fixed without problematic access logging

# API Gateway REST API
resource "aws_api_gateway_rest_api" "photo_api" {
  name        = "${local.resource_prefix}-api"
  description = "API for Photo Sharing App with Cognito Authentication"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  lifecycle {
    # Prevent destruction if imported
    prevent_destroy = false
  }
}

# Cognito Authorizer for API Gateway
resource "aws_api_gateway_authorizer" "cognito" {
  name                   = "${local.resource_prefix}-cognito-authorizer"
  rest_api_id            = aws_api_gateway_rest_api.photo_api.id
  type                   = "COGNITO_USER_POOLS"
  provider_arns          = [aws_cognito_user_pool.main.arn]
  identity_source        = "method.request.header.Authorization"
  authorizer_credentials = aws_iam_role.api_gateway_role.arn
}

# CORS OPTIONS method for the root resource
resource "aws_api_gateway_method" "options_root" {
  rest_api_id   = aws_api_gateway_rest_api.photo_api.id
  resource_id   = aws_api_gateway_rest_api.photo_api.root_resource_id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options_root" {
  rest_api_id = aws_api_gateway_rest_api.photo_api.id
  resource_id = aws_api_gateway_rest_api.photo_api.root_resource_id
  http_method = aws_api_gateway_method.options_root.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = jsonencode({
      statusCode = 200
    })
  }
}

resource "aws_api_gateway_method_response" "options_root" {
  rest_api_id = aws_api_gateway_rest_api.photo_api.id
  resource_id = aws_api_gateway_rest_api.photo_api.root_resource_id
  http_method = aws_api_gateway_method.options_root.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "options_root" {
  rest_api_id = aws_api_gateway_rest_api.photo_api.id
  resource_id = aws_api_gateway_rest_api.photo_api.root_resource_id
  http_method = aws_api_gateway_method.options_root.http_method
  status_code = aws_api_gateway_method_response.options_root.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS,POST,PUT'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

# API Gateway Resource for images
resource "aws_api_gateway_resource" "images" {
  rest_api_id = aws_api_gateway_rest_api.photo_api.id
  parent_id   = aws_api_gateway_rest_api.photo_api.root_resource_id
  path_part   = "images"
}

# API Gateway Resource for upload
resource "aws_api_gateway_resource" "upload" {
  rest_api_id = aws_api_gateway_rest_api.photo_api.id
  parent_id   = aws_api_gateway_resource.images.id
  path_part   = "upload"
}

# API Gateway Resource for list
resource "aws_api_gateway_resource" "list" {
  rest_api_id = aws_api_gateway_rest_api.photo_api.id
  parent_id   = aws_api_gateway_resource.images.id
  path_part   = "list"
}

# POST method for upload with Cognito authorization
resource "aws_api_gateway_method" "post_upload" {
  rest_api_id   = aws_api_gateway_rest_api.photo_api.id
  resource_id   = aws_api_gateway_resource.upload.id
  http_method   = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id

  request_parameters = {
    "method.request.header.Authorization" = true
  }
}

# GET method for list with Cognito authorization
resource "aws_api_gateway_method" "get_list" {
  rest_api_id   = aws_api_gateway_rest_api.photo_api.id
  resource_id   = aws_api_gateway_resource.list.id
  http_method   = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id

  request_parameters = {
    "method.request.header.Authorization" = true
  }
}

# Lambda integration for upload
resource "aws_api_gateway_integration" "upload_lambda" {
  rest_api_id = aws_api_gateway_rest_api.photo_api.id
  resource_id = aws_api_gateway_resource.upload.id
  http_method = aws_api_gateway_method.post_upload.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.upload_handler.invoke_arn
  credentials             = aws_iam_role.api_gateway_role.arn
}

# Lambda integration for list
resource "aws_api_gateway_integration" "list_lambda" {
  rest_api_id = aws_api_gateway_rest_api.photo_api.id
  resource_id = aws_api_gateway_resource.list.id
  http_method = aws_api_gateway_method.get_list.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.list_handler.invoke_arn
  credentials             = aws_iam_role.api_gateway_role.arn
}

# OPTIONS methods for CORS
resource "aws_api_gateway_method" "options_upload" {
  rest_api_id   = aws_api_gateway_rest_api.photo_api.id
  resource_id   = aws_api_gateway_resource.upload.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "options_list" {
  rest_api_id   = aws_api_gateway_rest_api.photo_api.id
  resource_id   = aws_api_gateway_resource.list.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

# OPTIONS integrations
resource "aws_api_gateway_integration" "options_upload" {
  rest_api_id = aws_api_gateway_rest_api.photo_api.id
  resource_id = aws_api_gateway_resource.upload.id
  http_method = aws_api_gateway_method.options_upload.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = jsonencode({
      statusCode = 200
    })
  }
}

resource "aws_api_gateway_integration" "options_list" {
  rest_api_id = aws_api_gateway_rest_api.photo_api.id
  resource_id = aws_api_gateway_resource.list.id
  http_method = aws_api_gateway_method.options_list.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = jsonencode({
      statusCode = 200
    })
  }
}

# Method responses for OPTIONS
resource "aws_api_gateway_method_response" "options_upload" {
  rest_api_id = aws_api_gateway_rest_api.photo_api.id
  resource_id = aws_api_gateway_resource.upload.id
  http_method = aws_api_gateway_method.options_upload.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_method_response" "options_list" {
  rest_api_id = aws_api_gateway_rest_api.photo_api.id
  resource_id = aws_api_gateway_resource.list.id
  http_method = aws_api_gateway_method.options_list.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

# Integration responses for OPTIONS
resource "aws_api_gateway_integration_response" "options_upload" {
  rest_api_id = aws_api_gateway_rest_api.photo_api.id
  resource_id = aws_api_gateway_resource.upload.id
  http_method = aws_api_gateway_method.options_upload.http_method
  status_code = aws_api_gateway_method_response.options_upload.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

resource "aws_api_gateway_integration_response" "options_list" {
  rest_api_id = aws_api_gateway_rest_api.photo_api.id
  resource_id = aws_api_gateway_resource.list.id
  http_method = aws_api_gateway_method.options_list.http_method
  status_code = aws_api_gateway_method_response.options_list.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

# API Gateway Deployment WITHOUT deprecated stage_name
resource "aws_api_gateway_deployment" "deployment" {
  rest_api_id = aws_api_gateway_rest_api.photo_api.id

  depends_on = [
    aws_api_gateway_integration.upload_lambda,
    aws_api_gateway_integration.list_lambda,
    aws_api_gateway_integration_response.options_upload,
    aws_api_gateway_integration_response.options_list,
    aws_api_gateway_authorizer.cognito
  ]

  lifecycle {
    create_before_destroy = true
  }

  # Force redeployment when configuration changes
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_method.post_upload.id,
      aws_api_gateway_method.get_list.id,
      aws_api_gateway_integration.upload_lambda.id,
      aws_api_gateway_integration.list_lambda.id,
    ]))
  }
}

# FIXED: API Gateway Stage without problematic access logging
resource "aws_api_gateway_stage" "main" {
  deployment_id = aws_api_gateway_deployment.deployment.id
  rest_api_id   = aws_api_gateway_rest_api.photo_api.id
  stage_name    = var.environment

  # Enable X-Ray tracing (this works without additional setup)
  xray_tracing_enabled = true

  # REMOVED: access_log_settings to fix the CloudWatch Logs role error
  # To enable logging, you'd need to set up the CloudWatch Logs role first

  lifecycle {
    # Handle existing stages gracefully
    ignore_changes = [stage_name]
  }

  tags = {
    Environment = var.environment
    Name        = "${local.resource_prefix}-api-stage"
  }
}

# CloudWatch log group (kept for future use, but not referenced by stage)
resource "aws_cloudwatch_log_group" "api_gateway_logs" {
  name              = "/aws/apigateway/${local.resource_prefix}"
  retention_in_days = 14

  lifecycle {
    # Don't fail if log group already exists
    ignore_changes = [name]
  }

  tags = {
    Environment = var.environment
    Name        = "${local.resource_prefix}-api-logs"
  }
}

# Lambda permissions
resource "aws_lambda_permission" "api_gateway_upload" {
  statement_id  = "AllowAPIGatewayInvokeUpload"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.upload_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.photo_api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "api_gateway_list" {
  statement_id  = "AllowAPIGatewayInvokeList"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.list_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.photo_api.execution_arn}/*/*"
}