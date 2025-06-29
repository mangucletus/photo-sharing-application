# terraform/outputs.tf - Fixed to remove domain reference

# Output important resource information
output "images_bucket_name" {
  description = "Name of the S3 bucket for original images"
  value       = aws_s3_bucket.images.bucket
}

output "thumbnails_bucket_name" {
  description = "Name of the S3 bucket for thumbnails"
  value       = aws_s3_bucket.thumbnails.bucket
}

output "frontend_bucket_name" {
  description = "Name of the S3 bucket for frontend"
  value       = aws_s3_bucket.frontend.bucket
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table for image metadata"
  value       = aws_dynamodb_table.images_metadata.name
}

output "frontend_url" {
  description = "URL of the frontend website"
  value       = "https://${aws_s3_bucket.frontend.bucket}.s3-website.${data.aws_region.current.name}.amazonaws.com"
}

# API Gateway URL using the stage resource
output "api_gateway_url" {
  description = "URL of the API Gateway"
  value       = "https://${aws_api_gateway_rest_api.photo_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.main.stage_name}"
}

output "lambda_function_name" {
  description = "Name of the image resizer Lambda function"
  value       = aws_lambda_function.image_resizer.function_name
}

output "upload_handler_function_name" {
  description = "Name of the upload handler Lambda function"
  value       = aws_lambda_function.upload_handler.function_name
}

output "list_handler_function_name" {
  description = "Name of the list handler Lambda function"
  value       = aws_lambda_function.list_handler.function_name
}

output "images_bucket_upload_url" {
  description = "Base URL for uploading images"
  value       = "https://${aws_s3_bucket.images.bucket}.s3.amazonaws.com"
}

output "thumbnails_bucket_url" {
  description = "Base URL for accessing thumbnails"
  value       = "https://${aws_s3_bucket.thumbnails.bucket}.s3.amazonaws.com"
}

# API Gateway endpoints
output "upload_endpoint" {
  description = "API Gateway upload endpoint"
  value       = "https://${aws_api_gateway_rest_api.photo_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.main.stage_name}/images/upload"
}

output "list_endpoint" {
  description = "API Gateway list endpoint"
  value       = "https://${aws_api_gateway_rest_api.photo_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.main.stage_name}/images/list"
}

# Cognito outputs
output "cognito_user_pool_id" {
  description = "ID of the Cognito User Pool"
  value       = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_client_id" {
  description = "ID of the Cognito User Pool Client"
  value       = aws_cognito_user_pool_client.main.id
}

output "cognito_identity_pool_id" {
  description = "ID of the Cognito Identity Pool"
  value       = aws_cognito_identity_pool.main.id
}

output "cognito_region" {
  description = "AWS region for Cognito"
  value       = data.aws_region.current.name
}