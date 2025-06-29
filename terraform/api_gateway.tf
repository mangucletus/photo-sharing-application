# terraform/api_gateway.tf - Optimized for React frontend

# API Gateway REST API
resource "aws_api_gateway_rest_api" "photo_api" {
  name        = "${local.resource_prefix}-api"
  description = "API for Photo Sharing App with Cognito Authentication"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  binary_media_types = ["*/*"]

  lifecycle {
    prevent_destroy = false
  }
}

# Cognito Authorizer for API Gateway
resource "aws_api_gateway_authorizer" "cognito" {
  name          = "${local.resource_prefix}-cognito-authorizer"
  rest_api_id   = aws_api_gateway_rest_api.photo_api.id
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.main.arn]

  # Use Authorization header for token
  identity_source = "method.request.header.Authorization"
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
}

# Lambda integration for list
resource "aws_api_gateway_integration" "list_lambda" {
  rest_api_id = aws_api_gateway_rest_api.photo_api.id
  resource_id = aws_api_gateway_resource.list.id
  http_method = aws_api_gateway_method.get_list.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.list_handler.invoke_arn
}

# CORS OPTIONS methods
resource "aws_api_gateway_method" "options_root" {
  rest_api_id   = aws_api_gateway_rest_api.photo_api.id
  resource_id   = aws_api_gateway_rest_api.photo_api.root_resource_id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "options_images" {
  rest_api_id   = aws_api_gateway_rest_api.photo_api.id
  resource_id   = aws_api_gateway_resource.images.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

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

# CORS integrations
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

resource "aws_api_gateway_integration" "options_images" {
  rest_api_id = aws_api_gateway_rest_api.photo_api.id
  resource_id = aws_api_gateway_resource.images.id
  http_method = aws_api_gateway_method.options_images.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = jsonencode({
      statusCode = 200
    })
  }
}

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

# CORS method responses
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

resource "aws_api_gateway_method_response" "options_images" {
  rest_api_id = aws_api_gateway_rest_api.photo_api.id
  resource_id = aws_api_gateway_resource.images.id
  http_method = aws_api_gateway_method.options_images.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

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

# CORS integration responses
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

resource "aws_api_gateway_integration_response" "options_images" {
  rest_api_id = aws_api_gateway_rest_api.photo_api.id
  resource_id = aws_api_gateway_resource.images.id
  http_method = aws_api_gateway_method.options_images.http_method
  status_code = aws_api_gateway_method_response.options_images.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS,POST,PUT'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

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

# API Gateway Deployment
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

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_method.post_upload.id,
      aws_api_gateway_method.get_list.id,
      aws_api_gateway_integration.upload_lambda.id,
      aws_api_gateway_integration.list_lambda.id,
      aws_api_gateway_authorizer.cognito.id,
    ]))
  }
}

# API Gateway Stage
resource "aws_api_gateway_stage" "main" {
  deployment_id = aws_api_gateway_deployment.deployment.id
  rest_api_id   = aws_api_gateway_rest_api.photo_api.id
  stage_name    = var.environment

  # Enable X-Ray tracing
  xray_tracing_enabled = true

  # Stage variables for Lambda aliases
  variables = {
    lambdaAlias = var.environment
  }

  lifecycle {
    ignore_changes = [stage_name]
  }

  tags = {
    Environment = var.environment
    Name        = "${local.resource_prefix}-api-stage"
  }
}

# CloudWatch log group for API Gateway (optional)
resource "aws_cloudwatch_log_group" "api_gateway_logs" {
  name              = "/aws/apigateway/${local.resource_prefix}"
  retention_in_days = 14

  lifecycle {
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